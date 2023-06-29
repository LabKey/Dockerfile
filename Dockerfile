# main eclipse-temurin jre, which is debian-based
ARG FROM_REPO_IMAGE=eclipse-temurin
ARG FROM_TAG=17-jre

# uncomment for alpine-based eclipse-temurin jre
# ARG FROM_TAG=17-jre-alpine

FROM ${FROM_REPO_IMAGE}:${FROM_TAG} as base

LABEL maintainer="LabKey Systems Engineering <ops@labkey.com>"

FROM base

# this will assume whatever FROM_TAG was set in first stage above
ARG FROM_TAG

ARG DEBUG=
ARG LABKEY_VERSION
ARG LABKEY_DISTRIBUTION
ARG LABKEY_EK

# dependent ENVs declared separately
ENV POSTGRES_USER="postgres" \
    \
    LABKEY_PORT="8443" \
    LABKEY_HOME="/labkey" \
    LABKEY_DEFAULT_DOMAIN="localhost" \
    LABKEY_SYSTEM_SHORT_NAME="Sirius Cybernetics" \
    \
    TOMCAT_BASE_DIR="/"

ENV LABKEY_SYSTEM_EMAIL_ADDRESS="noreply@${LABKEY_DEFAULT_DOMAIN}"

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
    LABKEY_EK= \
    LABKEY_GUID= \
    \
    LABKEY_VERSION="${LABKEY_VERSION}" \
    LABKEY_DISTRIBUTION="${LABKEY_DISTRIBUTION}" \
    LABKEY_EK="${LABKEY_EK}" \
    \
    LABKEY_FILES_ROOT="${LABKEY_HOME}/files" \
    \
    LABKEY_COMPANY_NAME="${LABKEY_SYSTEM_SHORT_NAME}" \
    LABKEY_SYSTEM_DESCRIPTION="${LABKEY_SYSTEM_SHORT_NAME}" \
    LABKEY_BASE_SERVER_URL="https://${LABKEY_DEFAULT_DOMAIN}:${LABKEY_PORT}" \
    \
    LABKEY_STARTUP_BASIC_EXTRA= \
    LABKEY_STARTUP_DISTRIBUTION_EXTRA= \
    \
    LABKEY_CREATE_INITIAL_USER= \
    LABKEY_INITIAL_USER_EMAIL="toor@localhost" \
    LABKEY_INITIAL_USER_ROLE="SiteAdminRole" \
    LABKEY_INITIAL_USER_GROUP="Administrators" \
    \
    LABKEY_CREATE_INITIAL_USER_APIKEY= \
    LABKEY_INITIAL_USER_APIKEY= \
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
    SMTP_FROM="${LABKEY_SYSTEM_EMAIL_ADDRESS}" \
    SMTP_STARTTLS= \
    SMTP_AUTH="false" \
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
    LOG_LEVEL_API_SETTINGS= \
    LOG_LEVEL_API_PIPELINE=

COPY entrypoint.sh /entrypoint.sh

WORKDIR "${LABKEY_HOME}"

RUN [ -n "${DEBUG}" ] && set -x; \
    set -eu; \
    \
    sort < $JAVA_HOME/release || true; \
    \
    if echo "${FROM_TAG}" | grep -i 'alpine'; then \
        apk update \
        && apk add --no-cache \
            tomcat-native \
            openssl \
            gettext \
            zip \
            curl \
            ; \
        [ -n "${DEBUG}" ] && apk add --no-cache tree; \
        apk upgrade; \
        \
        addgroup -S labkey \
            --gid=2005; \
        adduser --system \
            --ingroup labkey \
            --uid 2005 \
            --home ${LABKEY_HOME} \
            --shell /bin/bash \
            labkey; \
        \
        chmod u-s /usr/bin/passwd; \
    else \
        export DEBIAN_FRONTEND=noninteractive; \
        apt-get update; \
        apt-get -yq install \
            libtcnative-1 \
            openssl \
            gettext-base \
            zip \
            ; \
        [ -n "${DEBUG}" ] && apt-get -yq install tree; \
        apt-get -yq upgrade; \
        apt-get -yq clean all; \
        \
        groupadd -r labkey \
            --gid=2005; \
        useradd -r \
            -g labkey \
            --uid=2005 \
            --home-dir=${LABKEY_HOME} \
            --shell=/bin/bash \
            labkey; \
        \
        chmod u-s /usr/bin/su /usr/bin/mount /usr/bin/chfn /usr/bin/gpasswd /usr/bin/newgrp /usr/bin/umount /usr/bin/chsh /usr/bin/passwd; \
        chmod g-s /usr/bin/expiry /usr/bin/chage /usr/bin/wall /usr/sbin/pam_extrausers_chkpwd /usr/sbin/unix_chkpwd; \
    rm -rfv /var/lib/apt/lists; \
    fi; \
    \
    mkdir -pv \
        "${LABKEY_FILES_ROOT}/@files" \
        "config" \
        "externalModules" \
        "logs" \
        "server/startup" \
        "${TOMCAT_BASE_DIR}" \
    \
    && env | sort | tee /buid.env; \
    \
    chown -Rc labkey:labkey ${LABKEY_HOME};


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
COPY log4j2.xml log4j2.xml

# add aws cli
RUN mkdir -p /usr/src/awsclizip \
    && wget -q -O /usr/src/awsclizip/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    && unzip -q -d /usr/src/awsclizip/ /usr/src/awsclizip/awscliv2.zip \
    && rm /usr/src/awsclizip/awscliv2.zip \
    && /usr/src/awsclizip/aws/install

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
    HEALTHCHECK_ENDPOINT="/_/health"

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

VOLUME "${LABKEY_FILES_ROOT}/@files"
VOLUME "${LABKEY_HOME}/externalModules"
VOLUME "${LABKEY_HOME}/logs"

EXPOSE ${LABKEY_PORT}

STOPSIGNAL SIGTERM

USER labkey

# shell form e.g. executed w/ /bin/sh -c
ENTRYPOINT /entrypoint.sh
