#!/bin/sh

if [ -n "${DEBUG:-}" ]; then
  set -x
fi

set -eu

main() {

  if env | grep -qs 'DEBUG=1' && grep -qs  -v 'DEBUG=1' /build.env; then
    echo 'DEBUG set at runtime, but not at build time'
    unset DEBUG
  fi

  cd "$LABKEY_HOME"

  exec java -jar app.jar \
    "-Duser.timezone=${JAVA_TIMEZONE}" \
    \
    "-Xms${MIN_JVM_MEMORY}" \
    "-Xmx${MAX_JVM_MEMORY}" \
    \
    -XX:-HeapDumpOnOutOfMemoryError \
    \
    -Djava.net.preferIPv4Stack=true \
    \
    -Dorg.apache.catalina.startup.EXIT_ON_INIT_FAILURE=true \
    \
    "-Dlabkey.home=${LABKEY_HOME}" \
    "--spring.config.location=${LABKEY_HOME}/application.properties" \
    ;

}

main
