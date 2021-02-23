#!/bin/sh

if [ -n "${DEBUG:-}" ]; then
  set -x
fi

# set -eu

keystore_pass="${TOMCAT_KEYSTORE_PASSWORD:-}"
keystore_filename="${TOMCAT_KEYSTORE_FILENAME:-labkey.p12}"
keystore_alias="${TOMCAT_KEYSTORE_ALIAS:-}"
keystore_format="${TOMCAT_KEYSTORE_FORMAT:-}"

main() {

  if env | grep -qs 'DEBUG=1' && grep -qs  -v 'DEBUG=1' /build.env; then
    echo 'DEBUG set at runtime, but not at build time, unsetting'
    unset DEBUG
  fi

  debug_string='false'

  if [ -n "$DEBUG" ]; then
    debug_string='true'
  fi

  if [ -n "$keystore_format" ]; then
    openssl_format_flag="$(
      echo "$keystore_format" | tr '[:upper:]' '[:lower:]'
    )"
  else
    openssl_format_flag='pkcs12'
  fi

  cd "$LABKEY_HOME" || exit 1

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

  openssl "$openssl_format_flag" \
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

    openssl "$openssl_format_flag" \
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
    -Dlabkey.externalModulesDir="${LABKEY_HOME}/externalModules" \
    \
    -Djava.library.path=/usr/lib \
    \
    -Djava.security.egd=file:/dev/./urandom \
    \
    -Djava.io.tmpdir="$JAVA_TMPDIR" \
    \
    -Dlog4j.debug="$debug_string" \
    -Dlog4j.configurationFile="${LABKEY_HOME}/log4j2.xml" \
    \
    -Dorg.apache.catalina.startup.EXIT_ON_INIT_FAILURE=true \
    \
    -jar app.jar \
    \
    -DsynchronousStartup=true \
    \
    --server.ssl.key-store-password="${keystore_pass}" \
    --server.ssl.key-store="${LABKEY_HOME}/${TOMCAT_KEYSTORE_FILENAME}" \
    --server.ssl.key-alias="${keystore_alias}" \
    \
    ;

}

main
