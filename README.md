# LabKey Dockerfile Repository

This repo contains a Dockerfile, `docker-compose.yml`, and various other files for creating a docker container of LabKey products. Please review this document and especially the "Tips" section below.

## Prerequisites

To fully use this repo, you will need installed:

- Docker
- `docker-compose`
- GNU Make
- AWS CLI

## Building a Container

This repo includes a `Makefile` who's aim is to ease the running of the necessary commands for creating containers. The **default action** of the `Makefile` is to log into the AWS ECR service, build, tag, and push a docker container (the `all:` target) to an ECR repo named after the chosen distribution.

Building a container is as simple as `make build`:

```shell
$make build
docker build \
  --rm \
  --compress \
  --no-cache \
  -t labkey/community:21.3-snapshot \
  -t labkey/community:latest \
  --build-arg 'DEBUG=' \
  --build-arg 'LABKEY_VERSION=21.3-SNAPSHOT' \
  --build-arg 'LABKEY_DISTRIBUTION=community' \
  .
Sending build context to Docker daemon  756.1MB
...
Step 27/27 : ENTRYPOINT /entrypoint.sh
 ---> Running in db19946ff9de
Removing intermediate container db19946ff9de
 ---> 6c15d5de57a6
Successfully built 6c15d5de57a6
Successfully tagged labkey/community:21.3-snapshot
Successfully tagged labkey/community:latest
```

## Whats different about this Dockerfile versus others?

This repo and Dockerfile have been built from the ground up to support LabKey products that include Spring Boot/Embedded Tomcat which can be configured using `application.properties` files.

## Crucial Environment Variables

### Build Time & Run Time

Environment variables (ENVs) are used to control both halves of the lifecycle of the container: "build time" (when the container is built) and "run time" (when the container is being used after having been built). **As such, the list of Docker "build args" is pretty short;** being limited to just the base container to use w/ `FROM`, the distribution/version of LabKey, and `DEBUG`. Environment variables are instead used by scripts within the `Dockerfile` itself, and from within the `entrypoint.sh` script (which ultimately executes `java -jar`). The container will fail to start if any required `LABKEY_*` environment variables are not supplied as in the following:

```shell
labkey_1    | value required for 'LABKEY_SYSTEM_DESCRIPTION'
dockerfile_labkey_1 exited with code 1
```

These crucial ENVs can be broken up into a couple categories relating to their function and/or relevance to LabKey or Docker, build time or run time.

## General

Setting `DEBUG` to any value will suffice: `docker build ... --build-arg DEBUG=1` or `make DEBUG=1 build`.

| name  | purpose                                                           | default   |
| ----- | ----------------------------------------------------------------- | --------- |
| DEBUG | whether or not to print extra information during build & run time | `<empty>` |

## Docker

The `Dockerfile` currently supports 2 base-container operating systems, Alpine Linux and Debian-based Linux. Both of which originate from `adoptopenjdk`. Toggling between the two or overriding them can be achieved by changing the `FROM_REPO_IMAGE` and `FROM_TAG` Docker build args. The `Dockerfile` provides 2 examples:

- "unofficial" adoptopenjdk-- which is alpine-based and
  - FROM_REPO_IMAGE=adoptopenjdk/openjdk15
  - FROM_TAG=alpine-jre
- "official" adoptopenjdk which is debian-based
  - FROM_REPO_IMAGE=adoptopenjdk
  - FROM_TAG=15-jre

| name            | purpose                                                | default                  |
| --------------- | ------------------------------------------------------ | ------------------------ |
| FROM_REPO_IMAGE | Docker repository & image to use as basis of container | `adoptopenjdk/openjdk15` |
| FROM_TAG        | repository tag to use as basis of container            | `alpine-jre`             |

## LabKey

Original locations for these configuration details range from XML file contents from `server.xml` to `context.xml` (`ROOT.xml` or `labkey.xml`), to ENVs consumed by java (`JAVA_OPTS`), ENVs consumed directly by LabKey, and ENVs consumed by tomcat (`setenv.sh`, `CATALINA_OPTS`). The goal here is to expose them all as ENVs configurable via Docker at both build time and run time.

A better description of the LabKey settings can be found [in the LabKey docs](https://www.labkey.org/Documentation/wiki-page.view?name=customizeLook#properties).

`LABKEY_GUID` and `LABKEY_MEK` are only relevant if you are attempting to created/run a container destined to connect to a pre-existing database belonging to a pre-existing LabKey.

| name                        | purpose                                                                                                  | default                  |
| --------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------ |
| LABKEY_BASE_SERVER_URL      | full URI LabKey will use to refer to itself                                                              | `https://localhost:8443` |
| LABKEY_COMPANY_NAME         | name of your organization; appears in emails                                                             | `Sirius Cybernetics`     |
| LABKEY_DEFAULT_DOMAIN       | (DNS) domain where the LabKey server resides                                                             | `localhost`              |
| LABKEY_DISTRIBUTION         | "flavor" of labkey;                                                                                      | `community`              |
| LABKEY_FILES_ROOT           | path within which will serve as the root of the "files" directory                                        | `/labkey/files`          |
| LABKEY_GUID                 | LabKey [server GUID](https://www.labkey.org/Documentation/wiki-page.view?name=stagingServerTips#guid)    | `<empty>`                |
| LABKEY_MEK                  | LabKey [master encryption key](https://www.labkey.org/Documentation/wiki-page.view?name=cpasxml#encrypt) | `<empty>`                |
| LABKEY_PORT                 | port to which labkey will bind within the container                                                      | `8443`                   |
| LABKEY_SYSTEM_DESCRIPTION   | brief description of server; appears in emails                                                           | `Sirius Cybernetics`     |
| LABKEY_SYSTEM_EMAIL_ADDRESS | email address system email will be sent "from"                                                           | `do_not_reply@localhost` |
| LABKEY_SYSTEM_SHORT_NAME    | name of server displayed in header                                                                       | `Sirius Cybernetics`     |

## Postgres

The `POSTGRES_*` default values are meant to match those of the [library/postgres](https://hub.docker.com/_/postgres) containers.

| name                | purpose                                                                   | default     |
| ------------------- | ------------------------------------------------------------------------- | ----------- |
| POSTGRES_DB         | "name" of database; compounds to URI connection string                    | `postgres`  |
| POSTGRES_HOST       | (DNS) hostname of database ""; compounds to URI connection string         | `localhost` |
| POSTGRES_PARAMETERS | suffix of database URI; compounds to URI connection string                | `<empty>`   |
| POSTGRES_PASSWORD   | password of database user which container will utilize as main dataSource | `<empty>`   |
| POSTGRES_PORT       | port of database; compounds to URI connection string                      | `5432`      |
| POSTGRES_USER       | user of database which container will utilize as main dataSource          | `postgres`  |

## SMTP

These replace values previously housed in `context.xml` (`ROOT.xml` or `labkey.xml`) governing `mail/Session` resources.

| name          | purpose                     | default     |
| ------------- | --------------------------- | ----------- |
| SMTP_HOST     | SMTP host configuration     | `localhost` |
| SMTP_PASSWORD | SMTP password configuration | `<empty>`   |
| SMTP_PORT     | SMTP port configuration     | `25`        |
| SMTP_USER     | SMTP user configuration     | `root`      |

## SSL/Keystore/Self-signed Cert

The `CERT_*` ENVs should look familiar to anyone that has used the `openssl` command to generate a pkcs12 keystore.

| name                         | purpose                                                      | default                                                  |
| ---------------------------- | ------------------------------------------------------------ | -------------------------------------------------------- |
| TOMCAT_KEYSTORE_ALIAS        | self-signed cert/keystore "alias"                            | `tomcat`                                                 |
| TOMCAT_KEYSTORE_FILENAME     | self-signed cert/keystore filename                           | `labkey.p12`                                             |
| TOMCAT_KEYSTORE_FORMAT       | self-signed cert/keystore format                             | `PKCS12`                                                 |
| TOMCAT_SSL_CIPHERS           | allowable SSL ciphers for use by Spring Boot                 | `HIGH:!ADH:!EXP:!SSLv2:!SSLv3:!MEDIUM:!LOW:!NULL:!aNULL` |
| TOMCAT_SSL_ENABLED_PROTOCOLS | allowable SSL protocols and versions                         | `TLSv1.3,TLSv1.2`                                        |
| TOMCAT_SSL_PROTOCOL          | basic SSL protocol to use                                    | `TLS`                                                    |
| CERT_C                       | "Country" value for the generated self-signed cert           | `US`                                                     |
| CERT_CN                      | "Common Name" value for the generated self-signed cert       | `localhost`                                              |
| CERT_L                       | "Location" value for the generated self-signed cert          | `Seattle`                                                |
| CERT_O                       | "Organization" value for the generated self-signed cert      | `<empty>`                                                |
| CERT_OU                      | "Organization Unit" value for the generated self-signed cert | `IT`                                                     |
| CERT_ST                      | "State" value for the generated self-signed cert             | `Washington`                                             |

## Java

Since java can be picky about the position of CLI values, `JAVA_PRE_JAR_EXTRA` and `JAVA_POST_JAR_EXTRA` are provided to allow for additional CLI values (flags, etc.) to be added to the `java -jar` command at the end of `entrypoint.sh`. **This method is the preferred way of supplying additional flags and options to java over using `JAVA_OPTS`**

| name                | purpose                                               | default               |
| ------------------- | ----------------------------------------------------- | --------------------- |
| JAVA_TIMEZONE       | java configured Timezone                              | `America/Los_Angeles` |
| JAVA_TMPDIR         | java configured "temp" directory                      | `/var/tmp`            |
| MAX_JVM_MEMORY      | java maximum heapsize (`-Xmx`)                        | `4g`                  |
| MAX_JVM_MEMORY      | java maximum heapsize (`-Xmx`)                        | `4g`                  |
| JAVA_PRE_JAR_EXTRA  | additional CLI values to pass to `java` before `-jar` | `<empty>`             |
| JAVA_POST_JAR_EXTRA | additional CLI values to pass to `java` after `-jar`  | `<empty>`             |

## Development Notes

In contrast to `application.properties`, the "startup properties" files housed in `startup/`, are LabKey's own implementation of `.properties` file(s) and generally are less feature rich that Springs'. Environment Variable substitution for example does not function within LabKey `.properties` files, which is why `gettext` is required for `entrypoint.sh`'s use of `envsubst`.

## Tips

You may enabled Chrome to accept self-signed certificates, such as the one generated within `entrypoint.sh`, by enabling this Chrome flag:

```shell
chrome://flags/#allow-insecure-localhost
```

Users of Mac OS will have more luck using GNU Make as installed by **Homebrew** and executed as `gmake`.

  Q: Why is my labkey container "unhealthy"?

A: LabKey containers produced from this repo contain a `HEALTHCHECK` block which defines a simple "smoke" test Docker can use internally to determine if the container is healthy. The healthcheck built into this Dockerfile boils down to a `curl` to `localhost`-- but it can be customized based on a number of `HEALTHCHECK_*` ENVs that the Dockerfile defines. A customization that may be helpful would be to define a `HEALTHCHECK_HEADER_NAME` or `HEALTHCHECK_HEADER_USER_AGENT` that matches a value already filtered out of the access log by the application. Most container orchestrations tools either explicitely disable containers' built-in HEALTCHECKs or give you the option to disable able it. A succinct example of this is `docker-compose`'s own [healthcheck](https://docs.docker.com/compose/compose-file/compose-file-v3/#healthcheck) syntax.

## **_Disclaimer_**

This repo is a work in progress. Do not run containers created from these sources in production. Containers created from these sources are untested. Until further work is done, integrations with LabKey products that traditionally have rely on OS configuration such as R scripts/reports will NOT work.

### Reference

- [Sample `application.properties` file](https://github.com/LabKey/server/blob/develop/server/configs/application.properties)
- [Sample `pg.properties` file](https://github.com/LabKey/server/blob/develop/server/configs/application.properties) -- contains some values referenced in application.properties above
- [LabKey Bootstrap Properties](https://www.labkey.org/Documentation/wiki-page.view?name=bootstrapProperties)
- [Dockerfile Reference](https://docs.docker.com/engine/reference/builder/)
- [Compose file v3 Reference](https://docs.docker.com/compose/compose-file/compose-file-v3/)
- [`logback` "pattern" Reference](http://logback.qos.ch/manual/layouts.html#conversionWord)
- [`log4j2` "pattern" Reference](https://logging.apache.org/log4j/log4j-2.0/manual/layouts.html)
- [`log4j` Migration Reference](https://logging.apache.org/log4j/2.x/manual/migration.html)
