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
    TOMCAT_KEYSTORE_FILENAME="labkey.p12" \
    TOMCAT_KEYSTORE_FORMAT="PKCS12" \
    TOMCAT_KEYSTORE_ALIAS="tomcat" \
    \
    TOMCAT_SSL_CIPHERS="HIGH:!ADH:!EXP:!SSLv2:!SSLv3:!MEDIUM:!LOW:!NULL:!aNULL" \
    TOMCAT_SSL_PROTOCOL="TLS" \
    TOMCAT_SSL_ENABLED_PROTOCOLS="TLSv1.3,TLSv1.2" \
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
    MIN_JVM_MEMORY="1g" \
    MAX_JVM_MEMORY="4g" \
    \
    JAVA_PRE_JAR_EXTRA= \
    JAVA_POST_JAR_EXTRA= \
    JAVA_TMPDIR="/var/tmp" \
    JAVA_TIMEZONE="America/Los_Angeles" \
    \
    LOGGER_PATTERN="%-40.40logger{39}"

ADD entrypoint.sh /entrypoint.sh

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
        "${LABKEY_HOME}/config" \
        "${LABKEY_HOME}/externalModules" \
        "${LABKEY_HOME}/logs" \
        "${LABKEY_HOME}/server/startup" \
        "${TOMCAT_BASE_DIR}" \
    \
    && ln -sfv /proc/1/fd/1 /tmp/access.log \
    \
    && env | sort | tee /buid.env;

WORKDIR "${LABKEY_HOME}"

ADD "labkeyServer-${LABKEY_VERSION}.jar" \
    "app.jar"

# add spring properties
ADD application.properties config/

# add basic + distribution startup properties
ADD startup/basic.properties \
    server/startup/50_basic.properties

ADD "startup/${LABKEY_DISTRIBUTION}.properties" \
    server/startup/49_distribution.properties

# add logging config files
ADD log4j2.xml "${LABKEY_HOME}/"

ENV HEALTHCHECK_INTERVAL="6s" \
    HEALTHCHECK_TIMEOUT="10s" \
    HEALTHCHECK_START="60s" \
    HEALTHCHECK_RETRIES="10" \
    \
    HEALTHCHECK_METHOD_FLAG="head" \
    HEALTHCHECK_USER_AGENT="Docker" \
    HEALTHCHECK_HEADER_NAME="X-Healthcheck" \
    HEALTHCHECK_HEADER_VALUE="true" \
    HEALTHCHECK_ENDPOINT="/"

HEALTHCHECK \
    --interval=6s \
    --timeout=10s \
    --start-period=60s \
    --retries=10 \
    CMD [ \
        "curl", \
        "--${HEALTHCHECK_METHOD_FLAG}", \
        "--user-agent", "'${HEALTHCHECK_USER_AGENT}'", \
        "--header", "'${HEALTHCHECK_HEADER_NAME}: ${HEALTHCHECK_HEADER_VALUE}'", \
        "-k", \
        "-L", \
        "--fail", \
        "https://localhost:${LABKEY_PORT}${HEALTHCHECK_ENDPOINT}" \
        "||" \
        "exit 1" \
    ]

VOLUME "${LABKEY_FILES_ROOT}"
VOLUME "${LABKEY_HOME}/externalModules"
VOLUME "${LABKEY_HOME}/logs"

EXPOSE "${LABKEY_PORT}"

STOPSIGNAL SIGTERM

# shell form e.g. executed w/ /bin/sh -c
ENTRYPOINT /entrypoint.sh
