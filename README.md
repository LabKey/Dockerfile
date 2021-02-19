# LabKey Dockerfile Repository

This repo contains a Dockerfile, `docker-compose.yml`, and various other files for creating a docker container of LabKey products.

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
