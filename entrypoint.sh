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

  debug_string='false'

  if [ -n "$DEBUG" ]; then
    debug_string='true'

    #
    # see Dockerfile for default LOGGER_PATTERN value
    #
    # shellcheck disable=SC2034
    export \
      LOG_LEVEL_LABKEY_DEFAULT='INFO' \
      LOG_LEVEL_API_MODULE_MODULELOADER='TRACE' \
      LOG_LEVEL_API_SETTINGS='TRACE' \
      \
      LOGGER_PATTERN='%-80.80logger{79}'

    env | sort
  fi

  if [ -n "$keystore_format" ]; then
    openssl_format_flag="$(
      echo "$keystore_format" | tr '[:upper:]' '[:lower:]'
    )"
  else
    openssl_format_flag='pkcs12'
  fi

  #
  # relative paths below here are relative to LABKEY_HOME
  #
  cd "$LABKEY_HOME" || exit 1

  OLD_IFS="$IFS"
  IFS="$(printf '\nx')" && IFS="${IFS%x}" # ensure IFS is a single newline
  for key_value in $(
      # list all LABKEY_* ENVs, ignore optional ones like GUID or MEK
      env | grep -E '^LABKEY_' \
        | grep -vE 'GUID' \
        | grep -vE 'MEK' \
        ;
  ); do
    if [ -z "${key_value#*=}" ]; then
      >&2 echo "value required for '${key_value%%=*}'"
      exit 1
    fi
  done
  export IFS="$OLD_IFS"

  if \
    echo "$LABKEY_BASE_SERVER_URL" \
      | grep -v -qs -E "https*://.+" \
  ; then
    >&2 echo "value for 'LABKEY_BASE_SERVER_URL' did not resemble a URI"
    exit 1
  fi

  if \
    echo "$LABKEY_BASE_SERVER_URL" \
      | grep -v -qs -E ":${LABKEY_PORT}" \
  ; then
    >&2 echo "LABKEY_PORT (${LABKEY_PORT}) value did not appear in 'LABKEY_BASE_SERVER_URL'"
    >&2 echo "LABKEY_BASE_SERVER_URL: '${LABKEY_BASE_SERVER_URL}'"
    exit 1
  fi

  for prop_file in server/startup/*.properties; do
    envsubst < "$prop_file" > "${prop_file}.tmp" \
      && mv "${prop_file}.tmp" "$prop_file"
  done

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

  touch server/startup/newinstall

  if [ -n "${DEBUG:-}" ]; then
    tail -n+1 \
      config/*.properties \
      server/startup/*.properties \
      "${JAVA_HOME:-}"/release

    if command -v tree >/dev/null 2>&1; then
      tree .
    fi

    sleep 1

    openssl "$openssl_format_flag" \
      -nokeys \
      -info \
      -in "$keystore_filename" \
      -passin "pass:${keystore_pass}"
  fi

  # shellcheck disable=SC2086
  exec java \
    \
    -Duser.timezone="${JAVA_TIMEZONE}" \
    \
    "-Xms${MIN_JVM_MEMORY}" \
    "-Xmx${MAX_JVM_MEMORY}" \
    \
    -XX:-HeapDumpOnOutOfMemoryError \
    \
    -XX:ErrorFile="${LABKEY_HOME}/logs/error_%p.log" \
    \
    -Djava.net.preferIPv4Stack=true \
    \
    -Dlabkey.home="$LABKEY_HOME" \
    -Dlabkey.log.home="${LABKEY_HOME}/logs" \
    -Dlabkey.externalModulesDir="${LABKEY_HOME}/externalModules" \
    \
    -Djava.library.path=/usr/lib \
    \
    -Djava.security.egd=file:/dev/./urandom \
    \
    -Djava.io.tmpdir="$JAVA_TMPDIR" \
    \
    -Dlogback.debug="$debug_string" \
    \
    -Dlog4j.debug="$debug_string" \
    -Dlog4j.configurationFile=log4j2.xml \
    \
    -Dorg.apache.catalina.startup.EXIT_ON_INIT_FAILURE=true \
    \
    -DsynchronousStartup=true \
    -DterminateOnStartupFailure=true \
    \
    ${JAVA_PRE_JAR_EXTRA} \
    \
    -jar app.jar \
    \
    ${JAVA_POST_JAR_EXTRA} \
    \
    --server.ssl.key-store-password="$keystore_pass" \
    --server.ssl.key-store="$TOMCAT_KEYSTORE_FILENAME" \
    --server.ssl.key-alias="$keystore_alias" \
    \
    ;

}

main
