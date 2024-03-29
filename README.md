# LabKey Dockerfile Repository

This repo contains a Dockerfile, `docker-compose.yml`, and various other files for creating a docker container of LabKey products. Please review this document and especially the "Tips" section below.

## **_Disclaimer_**

This repo is a work in progress. Containers created from these sources are untested. Until further work is done, integrations with LabKey products that traditionally have relied on OS configuration such as R reports or Python scripts will **NOT** work.

## Prerequisites

To fully use this repo, you will need installed:

- Docker >= v20.10.9 recommended 
- GNU Make
- GNU Awk

Optionally, to publish containers to AWS's ECR service using this repo's `Makefile`, you will need:

- AWS CLI

**You will also need the `.jar` file of an embedded LabKey distribution.**

A [`COPY` instruction](https://docs.docker.com/engine/reference/builder/#copy) in the Dockerfile expects this `.jar` file's filename to look like: "labkeyServer-${LABKEY_VERSION}.jar" (where `LABKEY_VERSION` is defined by the "LABKEY_VERSION" environment variable), and for it to be **in the root of this repo**. You will mostly likely _not_ need to rename the file, but you _will_ need to set `LABKEY_VERSION` according to the version within the file's name.

You can obtain this file by following these steps:

  1. Visit the [LabKey Server Community Edition downloads page](https://www.labkey.com/products-services/labkey-server/download-community-edition/) and fill in the required fields
  2. Download the "Embedded Tomcat Beta Installer" `.tar.gz` file
  3. Extract the `.jar` into the root of the repo: 

     `tar -xzf [path/to/.tar.gz] --include='LabKey*labkeyServer*.jar' --strip-components 1 -C [path/to/repo/]`

## TL;DR  ... Quick Start 
  1. brew install docker jq awscli
  1. Clone the repo to a local directory on a machine with docker installed
     
       `git clone https://github.com/LabKey/Dockerfile.git`
  1. Copy in the labkey community embedded `.jar` file to the same directory as the repo (see above on how to obtain)
  1. Export the minimal required environment variables or edit and source the quickstart_envs.sh
  
        `export LABKEY_VERSION="21.9.0"` ... 
     
        or
     
        `source ./quickstart_envs.sh`
  1. Run the Make Build command to create the container

        `make build`

  1. Run the Make Up command to start the container using the makefile docker-compose settings

        `make up`

  1. After a few minutes LabKey should be available by opening a browser window and connecting to https://localhost:8443
  1. enable Chrome to accept self-signed certificates, such as the one generated within `entrypoint.sh`, by enabling this Chrome flag:
      ```shell
      chrome://flags/#allow-insecure-localhost
      ```
  1. Explore 

## Building a Container

This repo includes a `Makefile` which aim is to ease the running of the necessary commands for creating containers. The **default action** of the `Makefile` is to log into the AWS ECR service, build, tag, and push a docker container (the `all:` target) to an ECR repo named after the chosen distribution.

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
  --build-arg 'LABKEY_DISTRIBUTION=community'
  --build-arg 'LABKEY_EK=123abc456' \
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

## What's different about this Dockerfile versus others?

This repo and Dockerfile have been built from the ground up to support LabKey products that include Spring Boot/Embedded Tomcat which can be configured using `application.properties` files. This change was made to simplify the installation of LabKey by reducing the dependencies required to get LabKey products off the ground. And to increase the configurability of LabKey products running within containers.

## Crucial Environment Variables

### Build Time & Run Time

Environment variables (ENVs) are used to control both halves of the lifecycle of the container: "build time" (when the container is built) and "run time" (when the container is being used after having been built). **As such, the list of Docker "build args" is pretty short;** being limited to just the base container to use w/ `FROM`, the distribution/version of LabKey, and `DEBUG`. Environment variables are instead used by scripts within the `Dockerfile` itself, and from within the `entrypoint.sh` script (which ultimately executes `java -jar`). The container will fail to start if any required `LABKEY_*` environment variables are not supplied as in the following:

```shell
labkey      | value required for 'LABKEY_SYSTEM_DESCRIPTION'
dockerfile_labkey_1 exited with code 1
```

These crucial ENVs can be broken up into a couple categories relating to their function and/or relevance to LabKey or Docker, build time or run time.

## General

Setting `DEBUG` to any value will suffice: `docker build ... --build-arg DEBUG=1` or `make DEBUG=1 build`.

| name  | purpose                                                           | default   |
| ----- | ----------------------------------------------------------------- | --------- |
| DEBUG | whether or not to print extra information during build & run time | `<empty>` |

## Docker

The `Dockerfile` currently supports 2 base-container operating systems, Alpine Linux and Debian-based Linux. Both of which originate from `eclipse-temurin`. Toggling between the two or overriding them can be achieved by changing the `FROM_TAG` Docker build arg. The `Dockerfile` provides 2 examples:

- alpine-based
  - FROM_REPO_IMAGE=eclipse-temurin
  - FROM_TAG=17-jre-alpine
- debian-based
  - FROM_REPO_IMAGE=eclipse-temurin
  - FROM_TAG=17-jre

| name            | purpose                                                | default                  |
| --------------- | ------------------------------------------------------ | ------------------------ |
| FROM_REPO_IMAGE | Docker repository & image to use as basis of container | `adoptopenjdk` |
| FROM_TAG        | repository tag to use as basis of container            | `16-jre`             |

## LabKey

Original locations for these configuration details range from XML file contents from `server.xml` to `context.xml` (`ROOT.xml` or `labkey.xml`), to ENVs consumed by java (`JAVA_OPTS`), ENVs consumed directly by LabKey, and ENVs consumed by tomcat (`setenv.sh`, `CATALINA_OPTS`). The goal here is to expose them all as ENVs configurable via Docker at both build time and run time.

A better description of the LabKey settings can be found [in the LabKey docs](https://www.labkey.org/Documentation/wiki-page.view?name=customizeLook#properties).

`LABKEY_GUID` is only relevant if you are attempting to created/run a container destined to connect to a pre-existing database belonging to a pre-existing LabKey.

| name                        | purpose                                                                                                  | default                  |
| --------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------ |
| LABKEY_BASE_SERVER_URL      | full URI LabKey will use to refer to itself                                                              | `https://localhost:8443` |
| LABKEY_COMPANY_NAME         | name of your organization; appears in emails                                                             | `Sirius Cybernetics`     |
| LABKEY_DEFAULT_DOMAIN       | (DNS) domain where the LabKey server resides                                                             | `localhost`              |
| LABKEY_DISTRIBUTION         | "flavor" of labkey;                                                                                      | `community`              |
| LABKEY_FILES_ROOT           | path within which will serve as the root of the "files" directory                                        | `/labkey/files`          |
| LABKEY_GUID                 | LabKey [server GUID](https://www.labkey.org/Documentation/wiki-page.view?name=stagingServerTips#guid)    | `<empty>`                |
| LABKEY_EK                  | LabKey [encryption key](https://www.labkey.org/Documentation/wiki-page.view?name=cpasxml#encrypt) | `123abc456`                |
| LABKEY_PORT                 | port to which labkey will bind within the container                                                      | `8443`                   |
| LABKEY_SYSTEM_DESCRIPTION   | brief description of server; appears in emails                                                           | `Sirius Cybernetics`     |
| LABKEY_SYSTEM_EMAIL_ADDRESS | email address system email will be sent "from"                                                           | `do_not_reply@localhost` |
| LABKEY_SYSTEM_SHORT_NAME    | name of server displayed in header                                                                       | `Sirius Cybernetics`     |

You can optionally bypass the initial user creation "wizard" by creating an initial user using the following environment variables. **At time of writing, there is no way to set the initial user's password.** Assuming valid SMTP configuration, the "forgot password" link can be used to accomplish this. Additionally, an API can be created for that user. If both `LABKEY_CREATE_INITIAL_USER` & `LABKEY_CREATE_INITIAL_USER_APIKEY` are set to a values other than empty strings, but `LABKEY_INITIAL_USER_APIKEY` is not set, a randomly generated string will be used. Setting `LABKEY_CREATE_INITIAL_USER_APIKEY` without having set `LABKEY_CREATE_INITIAL_USER` will result in NO initial user being added.

**Creating an initial user API key in this way will cause that API key to be output from the container in cleartext.**

Initial user/API key creation is a powerful feature that can be a security concern. If you're using this feature, care should be taken when considering where the container's output (and thus the cleartext API key) is directed.

Initial user API key creation was implemented in LabKey Server 20.11.

| name                              | purpose                                                                                  | default          |
| --------------------------------- | ---------------------------------------------------------------------------------------- | ---------------- |
| LABKEY_CREATE_INITIAL_USER        | set to a non-empty string to trigger initial user creation/bypass initial user wizard UI | `<empty>`        |
| LABKEY_INITIAL_USER_EMAIL         | email to be used for initial user                                                        | "toor@localhost" |
| LABKEY_INITIAL_USER_ROLE          | role to be used for initial user                                                         | "SiteAdminRole"  |
| LABKEY_INITIAL_USER_GROUP         | group to be used for initial user                                                        | "Administrators" |
| LABKEY_CREATE_INITIAL_USER_APIKEY | set to a non-empty string to also create an API key for the initial user                 | `<empty>`        |
| LABKEY_INITIAL_USER_APIKEY        | value to be used as the API key for the initial user, generated if missing               | `<empty>`        |

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
| SMTP_FROM     | SMTP from email address     | `<empty>`   |
| SMTP_AUTH     | SMTP Auth flag              |  `false`    |
| SMTP_STARTTLS | SMTP STARTTLS flag          | `<empty>`   |

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
| MAX_JVM_RAM_PERCENT | jvm maximum memory occupancy                          | `90.0`                |
| JAVA_PRE_JAR_EXTRA  | additional CLI values to pass to `java` before `-jar` | `<empty>`             |
| JAVA_POST_JAR_EXTRA | additional CLI values to pass to `java` after `-jar`  | `<empty>`             |

## Development Notes

In contrast to `application.properties`, the "startup properties" files housed in `startup/`, are LabKey's own implementation of `.properties` file(s) and generally are less feature rich that Springs'. Environment Variable substitution for example does not function within LabKey `.properties` files, which is why `gettext` is required for `entrypoint.sh`'s use of `envsubst`.

## Tips

Users of macOS will have more luck using GNU Make as installed by **Homebrew** and executed as `gmake`.

Q: Why is my labkey container "unhealthy"?

A: LabKey containers produced from this repo contain a [`HEALTHCHECK` instruction](https://docs.docker.com/engine/reference/builder/#healthcheck) which defines a simple "smoke" test Docker can use internally to determine if the container is healthy. The healthcheck built into this Dockerfile boils down to a `curl` to `localhost`-- but it can be customized based on a number of `HEALTHCHECK_*` ENVs that the Dockerfile defines. A customization that may be helpful would be to define a `HEALTHCHECK_HEADER_NAME` or `HEALTHCHECK_HEADER_USER_AGENT` that matches a value already filtered out of the access log by the application. Most container orchestrations tools either explicitely disable containers' built-in HEALTCHECKs or give you the option to disable able it. A succinct example of this is `docker-compose`'s own [healthcheck](https://docs.docker.com/compose/compose-file/compose-file-v3/#healthcheck) syntax.

### Reference

- [Sample `application.properties` file](https://github.com/LabKey/server/blob/develop/server/configs/application.properties)
- [Sample `pg.properties` file](https://github.com/LabKey/server/blob/develop/server/configs/pg.properties) -- contains some values referenced in application.properties above
- [LabKey Bootstrap Properties](https://www.labkey.org/Documentation/wiki-page.view?name=bootstrapProperties)
- [Dockerfile Reference](https://docs.docker.com/engine/reference/builder/)
- [Compose file v3 Reference](https://docs.docker.com/compose/compose-file/compose-file-v3/)
- [`logback` "pattern" Reference](http://logback.qos.ch/manual/layouts.html#conversionWord)
- [`log4j2` "pattern" Reference](https://logging.apache.org/log4j/log4j-2.0/manual/layouts.html)
- [`log4j` Migration Reference](https://logging.apache.org/log4j/2.x/manual/migration.html)
- [How the JVM Finally Plays Nice with Containers](https://www.atamanroman.dev/articles/usecontainersupport-to-the-rescue/)
- ["how to reduce spring boot memory usage?"](https://stackoverflow.com/a/52993285)
