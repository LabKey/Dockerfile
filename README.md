# LabKey Dockerfile Repository

This repo contains a Dockerfile, `docker-compose.yml`, and various other files for creating a docker container of LabKey products.

## Prequisites

To fully use this repo, you will need installed:

- Docker
- `docker-compose`
- GNU Make
- AWS CLI

## Building a Container

This repo includes a `Makefile` who's aim is to ease the running of the neccessary commands for creating containers.
The **default action** of the `Makefile` is to log into the AWS ECR service, build, tag, and push a docker container (the `all:` target) to an ECR repo.

## **_Disclaimer_**

This repo is a work in progress. Do not run containers created from these sources in production. Containers created from these sources are untested.

### Reference

- [Sample `application.properties` file](https://github.com/LabKey/server/blob/develop/server/configs/application.properties)
- [Sample `pg.properties` file](https://github.com/LabKey/server/blob/develop/server/configs/application.properties) -- contains some values referenced in application.properties above
- [Dockerfile Reference](https://docs.docker.com/engine/reference/builder/)
- [Compose file v3 Reference](https://docs.docker.com/compose/compose-file/compose-file-v3/)
- [`logback` "pattern" Reference](http://logback.qos.ch/manual/layouts.html#conversionWord)
- [`log4j2` "pattern" Reference](https://logging.apache.org/log4j/log4j-2.0/manual/layouts.html)
- [`log4j` Migration Reference](https://logging.apache.org/log4j/2.x/manual/migration.html)
