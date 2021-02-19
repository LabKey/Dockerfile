#!/bin/sh

if [ -n "${DEBUG:-}" ]; then
  set -x
fi

# set -eu

keystore_pass="${TOMCAT_KEYSTORE_PASSWORD:-}"
keystore_filename="${TOMCAT_KEYSTORE_FILENAME:-labkey.p12}"
keystore_alias="${TOMCAT_KEYSTORE_ALIAS:-}"

main() {

  if env | grep -qs 'DEBUG=1' && grep -qs  -v 'DEBUG=1' /build.env; then
    echo 'DEBUG set at runtime, but not at build time, unsetting'
    unset DEBUG
  fi

  cd "$LABKEY_HOME"

  if [ -z "$keystore_pass" ]; then
    keystore_pass="$(
      openssl rand -base64 64 \
        | tr '/' '#' | tr -d "'" \
          | tr -d '\n' 2>/dev/null
    )"
  fi

  openssl req \
    -x509 \
    -newkey rsa:4096 \
    -keyout 'privkey.pem' \
    -out 'cert.pem' \
    -days 365 \
    -nodes \
    -subj "/C=${CERT_C:?}/ST=${CERT_ST:?}/L=${CERT_L}/O=${CERT_O}/OU=${CERT_OU}/CN=${CERT_CN}" \
      >/dev/null 2>&1

  openssl pkcs12 \
      -export \
      -out "$keystore_filename" \
      -inkey 'privkey.pem' \
      -in 'cert.pem' \
      -name "$keystore_alias" \
      -passout "pass:${keystore_pass}" \
        >/dev/null 2>&1

  if [ -n "${DEBUG:-}" ]; then
    tail -n+1 config/*.properties "${JAVA_HOME:-}"/release

    tree "$LABKEY_HOME"

    env | sort

    openssl pkcs12 \
      -nokeys \
      -info \
      -in "$keystore_filename" \
      -passin "pass:${keystore_pass}"
  fi

  exec java \
    \
    -Duser.timezone="${JAVA_TIMEZONE}" \
    \
    "-Xms${MIN_JVM_MEMORY}" \
    "-Xmx${MAX_JVM_MEMORY}" \
    \
    -XX:-HeapDumpOnOutOfMemoryError \
    \
    -Djava.net.preferIPv4Stack=true \
    \
    -Dlabkey.home="$LABKEY_HOME" \
    \
    -Djava.io.tmpdir="$JAVA_TMPDIR" \
    \
    -Dlog4j.configurationFile="${LABKEY_HOME}/log4j2.xml" \
    \
    -jar app.jar \
    \
    --server.ssl.key-store-password="${keystore_pass}" \
    --trust.store.password="${keystore_pass}" \
    \
    ;

}

main
