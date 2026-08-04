# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Does

Builds and publishes Docker images for LabKey Server (a biomedical data management platform) to AWS ECR. A single `Dockerfile` produces multiple distributions (`community`, `enterprise`, `lims_starter`, `allpg`) via the `LABKEY_DISTRIBUTION` build arg.

## Common Commands

```bash
# Local development cycle
make build          # Build image locally (uses local .jar if present)
make up             # Run community via docker-compose (https://localhost:8443)
make up-enterprise  # Run enterprise distribution
make up-lims_starter
make down           # Tear down containers
make test           # Run smoke.bash health check against running container

# Lint
# Hadolint runs in CI; run locally via:
docker run --rm -i hadolint/hadolint < Dockerfile

# AWS ECR workflow
make login          # Authenticate to ECR
make tag            # Tag image for ECR
make push           # Push to ECR
make all            # login → build → tag → push (default)
```

## Architecture

### Build Flow

`Dockerfile` downloads the LabKey `.tar.gz` from a URL (or uses a local `.jar` file placed in the repo root for development). The `LABKEY_VERSION` and `LABKEY_DISTRIBUTION` build args control which artifact is fetched. Base image is `eclipse-temurin:25-jre-noble` (Debian); Alpine variant is also supported.

### Runtime

`entrypoint.sh` is the container entry point. It:
1. Validates required `LABKEY_*` env vars (excludes `*SSM*`, `*GUID*`, `*MEK*`, initial-user vars)
2. Optionally downloads startup properties from S3
3. Handles SSM vs. non-AWS mode: if `LABKEY_SSM_PREFIX` is set, normalizes trailing slashes on both prefix vars; otherwise removes the `context.awsParameterStore.prefix` line and substitutes `ssm:` references in `application.properties` with direct env var values
4. Runs `envsubst` on all `.properties` files, then `sed` to substitute `@@placeholder@@` values
5. Generates a self-signed TLS keystore via `openssl`
6. Unsets connection/SMTP env vars, then `exec`s `java -jar labkeyServer.jar`

### Multi-Distribution

The `startup/` directory contains `basic.properties` and `manifest.properties` — per-distribution `.properties` files were removed since prod deployments always overwrite them anyway. `startup/manifest.properties` (copied to `startup/48_manifest.properties`) carries the distribution's `ModuleLoader.include`/`ModuleLoader.exclude` set instead, generated per-build from the SNAPSHOT Installers artifact. `LABKEY_DISTRIBUTION` still selects the docker-compose service and image tag, and is passed to the JVM as an env var.

### Configuration Surface

Almost all runtime behavior is controlled via environment variables. The major groups are documented in `README.md`:
- **DB**: `POSTGRES_*` — connection, pooling
- **App**: `LABKEY_*` — version, distribution, base URL, encryption key, initial user
- **SSM (AWS, 26.6+)**: `LABKEY_SSM_PREFIX` (app-level prefix) and `LABKEY_VPC_SSM_PREFIX` (VPC-level prefix) — when set, DB credentials (`database_user`, `database_password`), encryption key (`ek`), and SMTP credentials (`smtp_user`, `smtp_password`) are fetched from SSM instead of env vars; see `application.properties` for the `ssm:` references and `README.md` for the full SSM parameter table
- **JVM**: `JAVA_*`, `MAX_JVM_RAM_PERCENT`, `JAVA_PRE_JAR_EXTRA` / `JAVA_POST_JAR_EXTRA`
- **SSL**: `CERT_*`, `TOMCAT_KEYSTORE_*`
- **Observability**: Datadog APM (`dd-java-agent.jar` baked in), `LOG_LEVEL_*`, `LOGGER_PATTERN`
- **Debug**: `DEBUG=1` installs extra tools (ping, netcat, vim, etc.) at runtime

### CI/CD (GitHub Actions)

| Workflow | Trigger |
|----------|---------|
| `hadolint.yml` | Push to `fb_*` / `*_fb_*`; PRs to develop/release* |
| `validate_pr.yml` | PR opened/ready for review |
| `merge_release.yml` | PR review approved (auto-merges release branches) |
| `dockle_xeol.yml` | Security scanning |
| `branch_release.yml` | Release branch automation |

Feature branches follow the pattern `fb_<description>` or `<version>_fb_<description>`.

### Local JAR Development

Place a `labkeyServer.jar.*` file in the repo root (already gitignored). The `Makefile` detects it and uses it as the build artifact instead of downloading from a remote URL, enabling local iteration without publishing.