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
    POSTGRES_MAX_TOTAL_CONNECTIONS= \
    POSTGRES_MAX_IDLE_CONNECTIONS= \
    POSTGRES_MAX_WAIT_MILLIS= \
    POSTGRES_ACCESS_UNDERLYING_CONNECTIONS= \
    POSTGRES_VALIDATION_QUERY= \
    \
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
    TOMCAT_ENABLE_ACCESS_LOG= 

ENV CERT_C="US" \
    CERT_ST="Washington" \
    CERT_L="Seattle" \
    CERT_O="${LABKEY_COMPANY_NAME}" \
    CERT_OU="IT" \
    CERT_CN="localhost" \
    \
    CSP_REPORT= \
    CSP_ENFORCE= \
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

# hadolint ignore=DL4006
RUN [ -n "${DEBUG}" ] && set -x; \
    set -eu; \
    \
    sort < "$JAVA_HOME/release" || true; \
    \
    if echo "${FROM_TAG}" | grep -i 'alpine'; then \
        apk update \
        && apk add --no-cache \
            openssl=3.1.1-r1 \
            gettext=0.21.1-r7 \
            unzip=6.0-r14 \
            curl=8.1.2-r0 \
            ; \
        [ -n "${DEBUG}" ] && apk add --no-cache tree=2.1.1-r0; \
        apk upgrade; \
        \
        addgroup -S labkey \
            --gid=2005; \
        adduser --system \
            --ingroup labkey \
            --uid 2005 \
            --home "${LABKEY_HOME}" \
            --shell /bin/bash \
            labkey; \
        \
        chmod u-s /usr/bin/passwd; \
    else \
        export DEBIAN_FRONTEND=noninteractive; \
        apt-get update; \
        apt-get -yq --no-install-recommends install \
            openssl=3.0.2-0ubuntu1.14 \
            gettext-base=0.21-4ubuntu4 \
            unzip=6.0-26ubuntu3.1 \
            ; \
        if [ -n "${DEBUG}" ]; then \
            # next 2 lines are to get postgres15 to install on ubuntu 22.04
            echo "deb http://apt.postgresql.org/pub/repos/apt $(grep VERSION_CODENAME /etc/os-release | cut -d "=" -f2)-pgdg main" > /etc/apt/sources.list.d/pgdg.list; \
            wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | tee /etc/apt/trusted.gpg.d/pgdg.asc > /dev/null 2>&1; \
            apt-get update; \
            apt-get -yq --no-install-recommends install \
                iputils-ping=3:20211215-1 \
                less=590-1ubuntu0.22.04.1 \
                netcat=1.218-4ubuntu1 \
                postgresql-client-15=15.5-1.pgdg22.04+1 \
                sudo=1.9.9-1ubuntu2.4 \
                tree=2.0.2-1 \
                vim=2:8.2.3995-1ubuntu2.13 \
                ; \
        fi; \
        apt-get -yq upgrade; \
        [ -z "${DEBUG}" ] && apt-get -yq clean all && rm -rf /var/lib/apt/lists/*; \
        \
        groupadd -r labkey \
            --gid=2005; \
        useradd -r \
            -g labkey \
            --uid=2005 \
            --home-dir="${LABKEY_HOME}" \
            --shell=/bin/bash \
            labkey; \
        \
        [ -n "${DEBUG}" ] && adduser labkey sudo && echo "labkey  ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/labkey; \
        [ -z "${DEBUG}" ] && chmod u-s /usr/bin/su /usr/bin/mount /usr/bin/chfn /usr/bin/gpasswd /usr/bin/newgrp /usr/bin/umount /usr/bin/chsh /usr/bin/passwd; \
        [ -z "${DEBUG}" ] && chmod g-s /usr/bin/expiry /usr/bin/chage /usr/bin/wall /usr/sbin/pam_extrausers_chkpwd /usr/sbin/unix_chkpwd; \
    [ -z "${DEBUG}" ] && rm -rfv /var/lib/apt/lists; \
    fi; \
    \
    mkdir -pv \
        "${LABKEY_FILES_ROOT}/@files" \
        "config" \
        "externalModules" \
        "logs" \
        "server/startup" \
        "${TOMCAT_BASE_DIR}" \
        "/work/Tomcat/localhost" \
    \
    && env | sort | tee /buid.env; \
    \
    chown -Rc labkey:labkey "/work/Tomcat/localhost"; \
    chown -Rc labkey:labkey "${LABKEY_HOME}";


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

# add aws cli & make it owned by labkey user so it can all be deleted after s3 downloads in entrypoint.sh
RUN mkdir -p /usr/src/awsclizip "${LABKEY_HOME}/awsclibin" "${LABKEY_HOME}/aws-cli" \
    && wget -q -O /usr/src/awsclizip/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    && unzip -q -d /usr/src/awsclizip/ /usr/src/awsclizip/awscliv2.zip \
    && /usr/src/awsclizip/aws/install --bin-dir "${LABKEY_HOME}/awsclibin" --install-dir "${LABKEY_HOME}/aws-cli" \
    && rm -rf /usr/src/awsclizip \
    && chown -R labkey:labkey "${LABKEY_HOME}/awsclibin" "${LABKEY_HOME}/aws-cli"

# install datadog tracing agent
RUN mkdir -p datadog \
    && wget -q -O datadog/dd-java-agent.jar https://dtdg.co/latest-java-tracer

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

RUN if [ -z "${DEBUG}" ]; then \
        find / -xdev -perm /6000 -type f -exec chmod a-s {} \; || true; \
    fi;

USER labkey

# shell form e.g. executed w/ /bin/sh -c
ENTRYPOINT ["/entrypoint.sh"]
