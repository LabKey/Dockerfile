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
    "-Dlabkey.home=${LABKEY_HOME}" \
    "--spring.config.location=${LABKEY_HOME}/application.properties" \
    ;

}

main
