#!/bin/sh

if [ -n "${DEBUG:-}" ]; then
  set -x
fi

# set -eu

keystore_pass="${TOMCAT_KEYSTORE_PASSWORD:-}"
keystore_filename="${TOMCAT_KEYSTORE_FILENAME:-labkey.p12}"
keystore_alias="${TOMCAT_KEYSTORE_ALIAS:-}"
keystore_format="${TOMCAT_KEYSTORE_FORMAT:-}"

LABKEY_CUSTOM_PROPERTIES_S3_URI="${LABKEY_CUSTOM_PROPERTIES_S3_URI:=none}"
LABKEY_OPTIONAL_APP_PROPERTIES_S3_URI="${LABKEY_OPTIONAL_APP_PROPERTIES_S3_URI:=none}"
LABKEY_DEFAULT_PROPERTIES_S3_URI="${LABKEY_DEFAULT_PROPERTIES_S3_URI:=none}"

# set below to 'labkeywebapp/WEB-INF/classes/log4j2.xml' to use embedded tomcat version from the built .jar
LOG4J_CONFIG_FILE="${LOG4J_CONFIG_FILE:=log4j2.xml}"

# below assumes using local log4j2.xml file, as the embedded version is not available for edits until after server is running
JSON_OUTPUT="${JSON_OUTPUT:-false}"

# for ecs/datadog, optionally enable APM and JMX metrics
DD_COLLECT_APM="${DD_COLLECT_APM:-false}"
JAVA_RMI_SERVER_HOSTNAME="${JAVA_RMI_SERVER_HOSTNAME:-}"

# set age past which old heap and error log directories are removed
PURGE_HEAP_AND_ERROR_LOGS_OLDER_THAN_DAYS="${PURGE_HEAP_AND_ERROR_LOGS_OLDER_THAN_DAYS:-90}"

SLEEP="${SLEEP:=0}"

main() {
  random_string() {
    length="${1:-32}"

    # generate a random string 2 chars longer than request to weed out trailing
    # equal signs common to openssl output and then trim out some
    # shell-sensitive characters and then trim to desired length
    openssl rand -base64 "$(( length + 2 ))" \
      | tr '/' '#' | tr -d "'" | cut "-c1-${length}" | tr -d '\n' \
        2>/dev/null
  }

  debug_string='false'

  if [ -n "$DEBUG" ]; then
    debug_string='true'

    #
    # see Dockerfile for default LOGGER_PATTERN value
    #
    # shellcheck disable=SC2034
    export \
      LOG_LEVEL_LABKEY_DEFAULT='INFO' \
      LOG_LEVEL_API_MODULELOADER='TRACE' \
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
      env \
        | grep -E '^LABKEY_' \
        | grep -vE 'GUID' \
        | grep -vE 'MEK' \
        | grep -vE 'STARTUP' \
        | grep -vE 'INITIAL_USER' \
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

  if [ -n "$LABKEY_CREATE_INITIAL_USER" ]; then

    >&2 echo  "initial user creation triggered for ${LABKEY_INITIAL_USER_EMAIL}"
    >&2 echo  "use the \"forgot password\" link to set the initial user's password"

    LABKEY_STARTUP_BASIC_EXTRA="$(
      echo "
        UserRoles.${LABKEY_INITIAL_USER_EMAIL};startup = org.labkey.api.security.roles.${LABKEY_INITIAL_USER_ROLE}
        UserGroups.${LABKEY_INITIAL_USER_EMAIL};startup = ${LABKEY_INITIAL_USER_GROUP}
      " | sed -e 's/\ \{2,\}//g'
    )"

    if [ -n "$LABKEY_CREATE_INITIAL_USER_APIKEY" ]; then
      if [ -z "$LABKEY_INITIAL_USER_APIKEY" ]; then
        generated_password="$(random_string)"

        export LABKEY_INITIAL_USER_APIKEY="$generated_password"

        >&2 echo  "generated initial user apikey: apikey|${LABKEY_INITIAL_USER_APIKEY}"
      fi

      LABKEY_STARTUP_BASIC_EXTRA="
        ${LABKEY_STARTUP_BASIC_EXTRA}
        ApiKey.${LABKEY_INITIAL_USER_EMAIL} = apikey|${LABKEY_INITIAL_USER_APIKEY}
      "
    fi

    export LABKEY_STARTUP_BASIC_EXTRA
  fi

  # optional s3 uris to files with default or custom startup properties, formatted like startup/basic.properties
  if [ $LABKEY_DEFAULT_PROPERTIES_S3_URI != 'none' ]; then
    echo "trying to s3 cp '$LABKEY_DEFAULT_PROPERTIES_S3_URI'"
    awsclibin/aws s3 cp $LABKEY_DEFAULT_PROPERTIES_S3_URI startup/
  fi

  if [ $LABKEY_CUSTOM_PROPERTIES_S3_URI != 'none' ]; then
    echo "trying to s3 cp '$LABKEY_CUSTOM_PROPERTIES_S3_URI'"
    awsclibin/aws s3 cp $LABKEY_CUSTOM_PROPERTIES_S3_URI startup/
  fi

  if [ $LABKEY_OPTIONAL_APP_PROPERTIES_S3_URI != 'none' ]; then
    echo "trying to s3 cp '$LABKEY_OPTIONAL_APP_PROPERTIES_S3_URI'"
    awsclibin/aws s3 cp $LABKEY_OPTIONAL_APP_PROPERTIES_S3_URI config/
  fi

  echo "sleeping for $SLEEP seconds..."
  sleep $SLEEP

  # echo "deleting awscli and unsetting AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, & AWS_SESSION_TOKEN, if set..."
  # rm -rf awsclibin aws-cli
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

  # echo "sleeping for $SLEEP seconds..."
  # sleep $SLEEP

  for prop_file in startup/*.properties config/application.properties; do
    envsubst < "$prop_file" > "${prop_file}.tmp" \
      && mv "${prop_file}.tmp" "$prop_file"
  done

  if [ -z "$keystore_pass" ]; then
    keystore_pass="$(random_string 64)"
  fi

  # below only works if server.tomcat.accesslog settings in application.properties are set to go to file instead of stdout
  if [ -n "$TOMCAT_ENABLE_ACCESS_LOG" ]; then
    ln -sfv /proc/1/fd/1 /tmp/access.log
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
    tail -n+1 \
      config/*.properties \
      startup/*.properties \
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

  echo "Adding secrets to config/application.properties from environment variables..."
  sed -i "s/@@jdbcUrl@@/jdbc:postgresql:\/\/${POSTGRES_HOST:-localhost}:${POSTGRES_PORT:-5432}\/${POSTGRES_DB:-${POSTGRES_USER}}${POSTGRES_PARAMETERS:-}/" config/application.properties
  sed -i "s/@@jdbcUser@@/${POSTGRES_USER:-postgres}/" config/application.properties
  sed -i "s/@@jdbcPassword@@/${POSTGRES_PASSWORD:-}/" config/application.properties

  sed -i "s/@@smtpHost@@/${SMTP_HOST}/" config/application.properties
  sed -i "s/@@smtpUser@@/${SMTP_USER}/" config/application.properties
  sed -i "s/@@smtpPort@@/${SMTP_PORT}/" config/application.properties
  sed -i "s/@@smtpPassword@@/${SMTP_PASSWORD}/" config/application.properties
  sed -i "s/@@smtpAuth@@/${SMTP_AUTH}/" config/application.properties
  sed -i "s/@@smtpFrom@@/${SMTP_FROM}/" config/application.properties
  sed -i "s/@@smtpStartTlsEnable@@/${SMTP_STARTTLS}/" config/application.properties

  sed -i "s/@@encryptionKey@@/${LABKEY_EK}/" config/application.properties

  # TODO: do we need the JSON check anymore? should we just take the override if it is set?
  # Check if we want JSON output, we are using the base log4j2.xml config, and have an override config to use
  if [ "${JSON_OUTPUT}" = "true" ] && [ "${LOG4J_CONFIG_FILE}" = "log4j2.xml" ] && [ -s "config/${LOG4J_CONFIG_OVERRIDE}" ]; then
    echo "JSON_OUTPUT==true && LOG4J_CONFIG_FILE==log4j2.xml && LOG4J_CONFIG_OVERRIDE is set, so updating application.properties and log4j2.xml to output JSON to console"
    LOG4J_CONFIG_FILE="${LOG4J_CONFIG_FILE:=log4j2.xml},config/${LOG4J_CONFIG_OVERRIDE}"
    echo "Log4j configuration files: $LOG4J_CONFIG_FILE"
  else
    echo "saw JSON_OUTPUT=$JSON_OUTPUT and LOG4J_CONFIG_FILE=$LOG4J_CONFIG_FILE and LOG4J_CONFIG_OVERRIDE=$LOG4J_CONFIG_OVERRIDE"
  fi

  export DD_JAVA_AGENT=""
  export DD_JMX=""
  if [ "$DD_COLLECT_APM" = "true" ]; then
    echo "DD_COLLECT_APM==true , so adding EC2 host's private IP to env vars as DD_AGENT_HOST"
    export TOKEN=$(curl --max-time 3 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"); 
    export DD_AGENT_HOST=$(curl --max-time 3 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4);

    echo "Adding -javaagent and jmx settings to java command"
    export DD_JAVA_AGENT="-javaagent:./datadog/dd-java-agent.jar -Ddd.profiling.enabled=true -Ddd.logs.injection=true -XX:FlightRecorderOptions=stackdepth=256 -Ddd.trace.remove.integration-service-names.enabled=true"

    export DD_JMX="-Dspring.jmx.enabled=true \
        -Dcom.sun.management.jmxremote \
        -Dcom.sun.management.jmxremote.authenticate=false \
        -Dcom.sun.management.jmxremote.ssl=false \
        -Dcom.sun.management.jmxremote.local.only=false \
        -Dcom.sun.management.jmxremote.port=7199 \
        -Dcom.sun.management.jmxremote.rmi.port=7199 \
        -Djava.rmi.server.hostname=${JAVA_RMI_SERVER_HOSTNAME}" 
  fi

  echo "Purging secrets and other bits from environment variables..."
  unset POSTGRES_USER POSTGRES_PASSWORD POSTGRES_HOST POSTGRES_PORT POSTGRES_DB POSTGRES_PARAMETERS
  unset SMTP_HOST SMTP_USER SMTP_PORT SMTP_PASSWORD SMTP_AUTH SMTP_FROM SMTP_STARTTLS
  unset LABKEY_CREATE_INITIAL_USER LABKEY_CREATE_INITIAL_USER_APIKEY LABKEY_INITIAL_USER_APIKEY LABKEY_INITIAL_USER_EMAIL LABKEY_INITIAL_USER_GROUP LABKEY_INITIAL_USER_ROLE
  unset LABKEY_EK SLEEP CONTAINER_PRIVATE_IP

  echo "Creating new heap/error log directory..."
  HEAP_AND_ERROR_PATH="$LABKEY_HOME/files/heap_dumps_and_errors_$(date +%Y%m%d_%H%M%S)"
  mkdir -pv $HEAP_AND_ERROR_PATH

  # purge old heap/error directories
  echo "Purging heap/error log directories older than $PURGE_HEAP_AND_ERROR_LOGS_OLDER_THAN_DAYS days..."
  find "$LABKEY_HOME/files/" -mindepth 1 -maxdepth 1 -type d -ctime +${PURGE_HEAP_AND_ERROR_LOGS_OLDER_THAN_DAYS} -name "heap*" | xargs rm -rf 

  # shellcheck disable=SC2086
  exec java \
    \
    -Duser.timezone="${JAVA_TIMEZONE}" \
    \
    -XX:+HeapDumpOnOutOfMemoryError \
    -XX:HeapDumpPath="${HEAP_AND_ERROR_PATH}" \
    \
    -XX:MaxRAMPercentage="${MAX_JVM_RAM_PERCENT}" \
    \
    -XX:+UseContainerSupport \
    \
    -XX:ErrorFile="${HEAP_AND_ERROR_PATH}/error_%p.log" \
    \
    -Djava.net.preferIPv4Stack=true \
    \
    -Dlabkey.home="$LABKEY_HOME" \
    -Dlabkey.log.home="${LABKEY_HOME}/logs" \
    -Dlabkey.externalModulesDir="${LABKEY_HOME}/externalModules" \
    \
    -Djava.library.path=/usr/lib:/usr/lib/x86_64-linux-gnu \
    \
    -Djava.security.egd=file:/dev/./urandom \
    \
    -Djava.io.tmpdir="$JAVA_TMPDIR" \
    \
    -Dlogback.debug="$debug_string" \
    \
    -Dlog4j.debug="$debug_string" \
    -Dlog4j.configurationFile="$LOG4J_CONFIG_FILE" \
    \
    -Dorg.apache.catalina.startup.EXIT_ON_INIT_FAILURE=true \
    \
    -DsynchronousStartup=false \
    -DterminateOnExistingConnections=false \
    -DterminateOnStartupFailure=true \
    \
    ${DD_JAVA_AGENT} \
    \
    ${DD_JMX} \
    \
    ${JAVA_PRE_JAR_EXTRA} \
    \
    -jar labkeyServer.jar \
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
