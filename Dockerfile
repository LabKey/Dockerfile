FROM adoptopenjdk:15-jre
LABEL maintainer="Labkey Systems Engineering <ops@labkey.com>"

ENV SHELL=/bin/bash

ADD entrypoint.sh /entrypoint.sh

EXPOSE 8443

ENTRYPOINT /entrypoint.sh
