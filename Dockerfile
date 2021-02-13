FROM adoptopenjdk:15-jre
LABEL maintainer="Labkey Systems Engineering <ops@labkey.com>"

ENV SHELL=/bin/bash

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
    LABKEY_PORT=8443 \
    LABKEY_HOME=/app \
    \
    LABKEY_VERSION="${LABKEY_VERSION}" \
    LABKEY_DISTRIBUTION="${LABKEY_DISTRIBUTION}"

ADD entrypoint.sh /entrypoint.sh

RUN [ -n "${DEBUG}" ] && set -x; \
    set -eu; \
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
