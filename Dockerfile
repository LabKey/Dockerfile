# uncomment for "unofficial" adoptopenjdk-- which is alpine-based
# ARG FROM_REPO_IMAGE=adoptopenjdk/openjdk15
# ARG FROM_TAG=alpine-jre

# "official" adoptopenjdk which is debian-based
ARG FROM_REPO_IMAGE=adoptopenjdk
ARG FROM_TAG=15-jre

FROM ${FROM_REPO_IMAGE}:${FROM_TAG}

LABEL maintainer="LabKey Systems Engineering <ops@labkey.com>"

# have to re-assign these after FROM - must match above
# ARG FROM_TAG=alpine-jre
ARG FROM_TAG=15-jre

ENV FROM_TAG="${FROM_TAG}"

ARG DEBUG=
ARG LABKEY_VERSION
ARG LABKEY_DISTRIBUTION

# dependent ENVs declared separately
ENV POSTGRES_USER="postgres" \
    \
    LABKEY_PORT="8443" \
    LABKEY_HOME="/labkey" \
    LABKEY_DEFAULT_DOMAIN="localhost" \
    LABKEY_SYSTEM_SHORT_NAME="Sirius Cybernetics" \
    \
    TOMCAT_BASE_DIR="/"

WORKDIR "${LABKEY_HOME}"

ENV DEBUG="${DEBUG}" \
    \
    CATALINA_HOME="${TOMCAT_BASE_DIR}" \
    \
    POSTGRES_PASSWORD= \
    POSTGRES_HOST="localhost" \
    POSTGRES_PORT="5432" \
    POSTGRES_DB="${POSTGRES_USER}" \
    POSTGRES_PARAMETERS= \
    \
    LABKEY_MEK= \
    LABKEY_GUID= \
    \
    LABKEY_VERSION="${LABKEY_VERSION}" \
    LABKEY_DISTRIBUTION="${LABKEY_DISTRIBUTION}" \
    \
    LABKEY_FILES_ROOT="${LABKEY_HOME}/files" \
    \
    LABKEY_COMPANY_NAME="${LABKEY_SYSTEM_SHORT_NAME}" \
    LABKEY_SYSTEM_DESCRIPTION="${LABKEY_SYSTEM_SHORT_NAME}" \
    LABKEY_SYSTEM_EMAIL_ADDRESS="do_not_reply@${LABKEY_DEFAULT_DOMAIN}" \
    LABKEY_BASE_SERVER_URL="https://${LABKEY_DEFAULT_DOMAIN}:${LABKEY_PORT}" \
    \
    LABKEY_STARTUP_BASIC_EXTRA= \
    LABKEY_STARTUP_DISTRIBUTION_EXTRA= \
    \
    TOMCAT_KEYSTORE_FILENAME="labkey.p12" \
    TOMCAT_KEYSTORE_FORMAT="PKCS12" \
    TOMCAT_KEYSTORE_ALIAS="tomcat" \
    \
    TOMCAT_SSL_CIPHERS="HIGH:!ADH:!EXP:!SSLv2:!SSLv3:!MEDIUM:!LOW:!NULL:!aNULL" \
    TOMCAT_SSL_PROTOCOL="TLS" \
    TOMCAT_SSL_ENABLED_PROTOCOLS="-TLSv1.3,+TLSv1.2" \
    \
    TOMCAT_ENABLE_ACCESS_LOG= \
    \
    CERT_C="US" \
    CERT_ST="Washington" \
    CERT_L="Seattle" \
    CERT_O="${LABKEY_COMPANY_NAME}" \
    CERT_OU="IT" \
    CERT_CN="localhost" \
    \
    SMTP_HOST="localhost" \
    SMTP_USER="root" \
    SMTP_PORT="25" \
    SMTP_PASSWORD= \
    SMTP_FROM= \
    SMTP_STARTTLS= \
    \
    MAX_JVM_RAM_PERCENT="90.0" \
    \
    JAVA_PRE_JAR_EXTRA= \
    JAVA_POST_JAR_EXTRA= \
    JAVA_TMPDIR="/var/tmp" \
    JAVA_TIMEZONE="America/Los_Angeles" \
    \
    LOGGER_PATTERN="%-40.40logger{39}" \
    LOG_LEVEL_DEFAULT= \
    \
    LOG_LEVEL_LABKEY_DEFAULT= \
    LOG_LEVEL_API_MODULELOADER= \
    LOG_LEVEL_API_SETTINGS=

COPY entrypoint.sh /entrypoint.sh

RUN [ -n "${DEBUG}" ] && set -x; \
    set -eu; \
    \
    sort < $JAVA_HOME/release || true; \
    \
    if echo "${FROM_TAG}" | grep -i 'alpine'; then \
        apk update \
        && apk add \
            tomcat-native \
            openssl \
            gettext \
            ; \
        [ -n "${DEBUG}" ] && apk add tree; \
        apk upgrade; \
    else \
        export DEBIAN_FRONTEND=noninteractive; \
        apt-get update; \
        apt-get -yq install \
            libtcnative-1 \
            openssl \
            gettext-base \
            ; \
        [ -n "${DEBUG}" ] && apt-get -yq install tree; \
        apt-get -yq upgrade; \
        apt-get -yq clean all; \
        rm -rfv /var/lib/apt/lists/*; \
    fi; \
    \
    mkdir -pv \
        "${LABKEY_FILES_ROOT}" \
        "config" \
        "externalModules" \
        "logs" \
        "server/startup" \
        "${TOMCAT_BASE_DIR}" \
    \
    && env | sort | tee /buid.env;

WORKDIR "${LABKEY_HOME}"

COPY "labkeyServer-${LABKEY_VERSION}.jar" \
    "app.jar"

# add spring properties
COPY application.properties config/

# add basic + distribution startup properties
COPY startup/basic.properties \
    server/startup/50_basic.properties

COPY "startup/${LABKEY_DISTRIBUTION}.properties" \
    server/startup/49_distribution.properties

# add logging config files
COPY log4j2.xml "${LABKEY_HOME}/"

# refrain from using shell significant characters in HEALTHCHECK_HEADER_*
ENV HEALTHCHECK_INTERVAL="6s" \
    HEALTHCHECK_TIMEOUT="10s" \
    HEALTHCHECK_START="60s" \
    HEALTHCHECK_RETRIES="10" \
    \
    HEALTHCHECK_METHOD_FLAG="get" \
    HEALTHCHECK_USER_AGENT="Docker" \
    HEALTHCHECK_HEADER_NAME="X-Healthcheck" \
    HEALTHCHECK_HEADER_VALUE="true" \
    HEALTHCHECK_SECURITY_FLAG="-k" \
    HEALTHCHECK_EXTRA_FLAGS="-s" \
    \
    HEALTHCHECK_ENDPOINT="/"

HEALTHCHECK \
    --interval=5s \
    --timeout=30s \
    --start-period=30s \
    --retries=10 \
    CMD \
        curl \
            "--${HEALTHCHECK_METHOD_FLAG}" \
            --user-agent "${HEALTHCHECK_USER_AGENT}" \
            --header "${HEALTHCHECK_HEADER_NAME}: ${HEALTHCHECK_HEADER_VALUE}" \
            "${HEALTHCHECK_SECURITY_FLAG}" \
            ${HEALTHCHECK_EXTRA_FLAGS} \
            -L \
            --fail \
            "https://localhost:${LABKEY_PORT}${HEALTHCHECK_ENDPOINT}" \
            || exit 1

VOLUME "${LABKEY_FILES_ROOT}"
VOLUME "${LABKEY_HOME}/externalModules"
VOLUME "${LABKEY_HOME}/logs"

EXPOSE "${LABKEY_PORT}"

STOPSIGNAL SIGTERM

# shell form e.g. executed w/ /bin/sh -c
ENTRYPOINT /entrypoint.sh
