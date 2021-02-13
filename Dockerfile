# "unofficial" adoptopenjdk-- which is alpine-based
ARG FROM_REPO_IMAGE=adoptopenjdk/openjdk15
ARG FROM_TAG=alpine-jre

# uncomment for "official" adoptopenjdk
# ARG FROM_REPO_IMAGE=adoptopenjdk
# ARG FROM_TAG=15-jre

FROM ${FROM_REPO_IMAGE}:${FROM_TAG}

LABEL maintainer="Labkey Systems Engineering <ops@labkey.com>"

ARG FROM_TAG=alpine-jre
ENV FROM_TAG="${FROM_TAG}"

ARG DEBUG=
ARG LABKEY_VERSION
ARG LABKEY_DISTRIBUTION

ENV POSTGRES_USER=postgres

ENV DEBUG="${DEBUG}" \
    \
    POSTGRES_PASSWORD= \
    POSTGRES_HOST=localhost \
    POSTGRES_PORT=5432 \
    POSTGRES_DB="${POSTGRES_USER}" \
    POSTGRES_PARAMETERS= \
    \
    LABKEY_PORT=8443 \
    LABKEY_HOME=/app \
    \
    LABKEY_MEK= \
    \
    LABKEY_VERSION="${LABKEY_VERSION}" \
    LABKEY_DISTRIBUTION="${LABKEY_DISTRIBUTION}" \
    \
    MIN_JVM_MEMORY="1g" \
    MAX_JVM_MEMORY="4g" \
    \
    JAVA_TIMEZONE=America/Los_Angeles

ADD entrypoint.sh /entrypoint.sh

RUN [ -n "${DEBUG}" ] && set -x; \
    set -eu; \
    \
    if echo "${FROM_TAG}" | grep -i 'alpine'; then \
        apk update \
        && apk add \
            tomcat-native \
            openssl \
            ; \
        [ -n "${DEBUG}" ] && apk add tree; \
        apk upgrade; \
    fi; \
    \
    mkdir -pv \
        /app/logs \
    \
    && env | sort | tee /buid.env;

WORKDIR /app

ADD "labkeyServer-${LABKEY_VERSION}.jar" \
    "app.jar"

ADD application.properties /app/

EXPOSE "${LABKEY_PORT}"

ENTRYPOINT /entrypoint.sh
