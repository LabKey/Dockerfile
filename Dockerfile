# "unofficial" adoptopenjdk-- which is alpine-based
ARG FROM_REPO_IMAGE=adoptopenjdk/openjdk15
ARG FROM_TAG=alpine-jre

# uncomment for "official" adoptopenjdk which is debian-based
# ARG FROM_REPO_IMAGE=adoptopenjdk
# ARG FROM_TAG=15-jre

FROM ${FROM_REPO_IMAGE}:${FROM_TAG}

LABEL maintainer="Labkey Systems Engineering <ops@labkey.com>"

# have to re-assign these after FROM - must match above
ARG FROM_TAG=alpine-jre
# ARG FROM_TAG=15-jre

ENV FROM_TAG="${FROM_TAG}"

ARG DEBUG=
ARG LABKEY_VERSION
ARG LABKEY_DISTRIBUTION

# dependent ENVs declared separately
ENV POSTGRES_USER="postgres" \
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
    LABKEY_PORT="8443" \
    LABKEY_HOME="/labkey" \
    \
    LABKEY_MEK= \
    LABKEY_GUID= \
    \
    LABKEY_VERSION="${LABKEY_VERSION}" \
    LABKEY_DISTRIBUTION="${LABKEY_DISTRIBUTION}" \
    \
    TOMCAT_KEYSTORE_FILENAME="labkey.p12" \
    TOMCAT_KEYSTORE_FORMAT="PKCS12" \
    TOMCAT_KEYSTORE_ALIAS="tomcat" \
    \
    TOMCAT_SSL_CIPHERS="HIGH:!ADH:!EXP:!SSLv2:!SSLv3:!MEDIUM:!LOW:!NULL:!aNULL" \
    TOMCAT_SSL_PROTOCOL="TLSv1.2" \
    TOMCAT_SSL_ENABLED_PROTOCOLS="TLSv1.3,TLSv1.2" \
    \
    CERT_C="US" \
    CERT_ST="Washington" \
    CERT_L="Seattle" \
    CERT_O="Business Inc." \
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
    JAVA_TMPDIR="/var/tmp" \
    JAVA_TIMEZONE="America/Los_Angeles"

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
            ; \
        [ -n "${DEBUG}" ] && apk add tree; \
        apk upgrade; \
    else \
        export DEBIAN_FRONTEND=noninteractive; \
        apt-get update; \
        apt-get -yq install \
            libtcnative-1 \
            openssl \
            ; \
        [ -n "${DEBUG}" ] && apt-get -yq install tree; \
        apt-get -yq upgrade; \
        apt-get -yq clean all; \
        rm -rfv /var/lib/apt/lists/*; \
    fi; \
    \
    mkdir -pv \
        "${LABKEY_HOME}/logs" \
        "${LABKEY_HOME}/startup" \
        "${LABKEY_HOME}/externalModules" \
        "${LABKEY_HOME}/files" \
        "${LABKEY_HOME}/config" \
        "${TOMCAT_BASE_DIR}" \
    \
    && ln -sfv /proc/1/fd/1 /tmp/access.log \
    \
    && env | sort | tee /buid.env;

WORKDIR "${LABKEY_HOME}"

ADD "labkeyServer-${LABKEY_VERSION}.jar" \
    "app.jar"

ADD application.properties "${LABKEY_HOME}/config/"
# ADD logging.properties "${LABKEY_HOME}/"
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

VOLUME "${LABKEY_HOME}/externalModules"
VOLUME "${LABKEY_HOME}/files"
VOLUME "${LABKEY_HOME}/logs"

EXPOSE "${LABKEY_PORT}"

STOPSIGNAL SIGTERM

# shell form e.g. executed w/ /bin/sh -c
ENTRYPOINT /entrypoint.sh
