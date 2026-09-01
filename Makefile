SHELL := /usr/bin/env bash

ifeq ($(strip $(findstring Darwin,$(shell uname -a 2>&1 ; ))),)
	_G :=
else
	_G := g
endif

DEBUG ?=

FROM_TAG ?= 25-jre-noble

CACHE_FLAG ?= --no-cache

TAG_LATEST ?=
PUSH_LATEST ?=
IDENT ?= labkey

PULL_TAG ?= latest

ifeq ($(AWS_ACCESS_KEY_ID),)
	AWS_ACCOUNT_ID ?= 123456789
	AWS_REGION ?= us-west-2
else
	AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity | jq -r '.Account' | grep -E '[0-9]{12}' || exit 1)
	AWS_REGION ?= $(shell aws configure get region || exit 1)
endif

LABKEY_VERSION ?= 21.5-SNAPSHOT
LABKEY_DISTRIBUTION ?= community
LABKEY_EK ?= 123abc456

LIMS_MANIFEST_BUCKET ?= labkey-lims-manifests
FETCH_LIMS_MANIFEST ?=

# When running with SSM credentials, seed postgres with the same DB user/password
# that LabKey will fetch from SSM — otherwise the pg container initializes with
# its defaults (postgres/localdevpassword) and auth fails.
ifdef LABKEY_SSM_PREFIX
  _SSM_NORMED := $(shell echo '$(LABKEY_SSM_PREFIX)' | sed 's:/*$$:/:')
  _SSM_DB_USER := $(shell aws ssm get-parameter --name '$(_SSM_NORMED)database_user' --with-decryption --query 'Parameter.Value' --output text 2>/dev/null)
  _SSM_DB_PASS := $(shell aws ssm get-parameter --name '$(_SSM_NORMED)database_password' --with-decryption --query 'Parameter.Value' --output text 2>/dev/null)
  ifneq ($(_SSM_DB_USER),)
    POSTGRES_USER ?= $(_SSM_DB_USER)
  endif
  ifneq ($(_SSM_DB_PASS),)
    POSTGRES_PASSWORD ?= $(_SSM_DB_PASS)
  endif
endif

LOG4J_CONFIG_OVERRIDE ?= default.log4j2.xml

BUILD_ARCHITECTURE ?= linux/amd64

# repo/image:tags must be lowercase
BUILD_VERSION ?= $(shell      echo '$(LABKEY_VERSION)'      | tr A-Z a-z)
BUILD_DISTRIBUTION := $(shell echo '$(LABKEY_DISTRIBUTION)' | tr A-Z a-z)
BUILD_ARCHITECTURE ?= $(BUILD_ARCHITECTURE)

BUILD_REPO_URI ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
BUILD_REPO_NAME := labkey/$(BUILD_DISTRIBUTION)
BUILD_REMOTE_REPO := $(BUILD_REPO_URI)/$(BUILD_REPO_NAME)

BUILD_LOCAL_TAG ?= $(BUILD_REPO_NAME):$(BUILD_VERSION)
BUILD_REMOTE_TAG ?= $(BUILD_REMOTE_REPO):$(BUILD_VERSION)

ifeq (1,$(DEBUG))
  BUILD_LOCAL_TAG := $(addsuffix -debug,$(BUILD_LOCAL_TAG))
  BUILD_REMOTE_TAG ?= $(addsuffix -debug,$(BUILD_REMOTE_TAG))
endif

define tc
$(shell printf "%steamcity[progressMessage '%s%n']" '##' '$1' ; )
endef

.PHONY: all build fetch-manifest tag login push up up-build down clean

.EXPORT_ALL_VARIABLES:

# default actions are: login, build, tag, then push
all: login build tag push

# only runs inside LabKey's own TeamCity builds (this is a public repo - a community/external
# build has no access to, and no use for, our internal LIMS manifest bucket) - set
# FETCH_LIMS_MANIFEST=1 to opt in from a local build too (e.g. testing against a real manifest).
# Also a no-op for any LABKEY_DISTRIBUTION with no manifest published (community, enterprise,
# allpg, etc.) - no allowlist needed, absence of a matching S3 object is just "not applicable".
fetch-manifest:
	$(call tc,checking for a LIMS product manifest)
	@if [ -z "$(TEAMCITY_VERSION)$(FETCH_LIMS_MANIFEST)" ]; then \
		echo "not running under TeamCity and FETCH_LIMS_MANIFEST not set - skipping LIMS manifest fetch"; \
	else \
		version_pattern=$$(echo '$(LABKEY_VERSION)' | grep -oE '^[0-9]+\.[0-9]+' | sed 's/\./\\./g'); \
		manifest_list=$$(aws s3api list-objects-v2 --bucket $(LIMS_MANIFEST_BUCKET) --prefix "$(BUILD_DISTRIBUTION)/" --output json) || exit 1; \
		manifest_keys=$$(echo "$$manifest_list" | jq -r '.Contents[]?.Key // empty' | grep -E "/LabKey$${version_pattern}([^0-9]|$$)" || true); \
		manifest_count=$$(echo "$$manifest_keys" | grep -c . || true); \
		if [ "$$manifest_count" -eq 0 ]; then \
			echo "no LIMS manifest found for distribution '$(BUILD_DISTRIBUTION)' version '$(LABKEY_VERSION)' - leaving startup/manifest.properties as-is"; \
		elif [ "$$manifest_count" -gt 1 ]; then \
			echo "expected exactly one manifest under s3://$(LIMS_MANIFEST_BUCKET)/$(BUILD_DISTRIBUTION)/ for version '$(LABKEY_VERSION)', found $$manifest_count: $$manifest_keys" >&2; \
			exit 1; \
		else \
			echo "fetching $$manifest_keys"; \
			aws s3 cp "s3://$(LIMS_MANIFEST_BUCKET)/$$manifest_keys" startup/manifest.properties; \
		fi; \
	fi

build: fetch-manifest
	$(call tc,building docker container)
	docker build \
		--rm \
		--compress \
		--platform $(BUILD_ARCHITECTURE) \
		$(CACHE_FLAG) \
		-t $(BUILD_REPO_NAME):latest \
		-t $(BUILD_LOCAL_TAG) \
		--build-arg 'FROM_TAG=$(FROM_TAG)' \
		--build-arg 'DEBUG=$(DEBUG)' \
		--build-arg 'LABKEY_VERSION=$(LABKEY_VERSION)' \
		--build-arg 'LABKEY_DISTRIBUTION=$(BUILD_DISTRIBUTION)' \
		--build-arg 'LABKEY_EK=$(LABKEY_EK)' \
		--build-arg 'LOG4J_CONFIG_OVERRIDE=${LOG4J_CONFIG_OVERRIDE}' \
		.

login:
	$(call tc,logging in to ECR)
	aws ecr get-login-password \
		| docker login \
			--username AWS \
			--password-stdin \
			$(BUILD_REPO_URI)

tag:
	$(call tc,tagging docker container)
	docker tag \
		$(BUILD_LOCAL_TAG) \
		$(BUILD_REMOTE_TAG);

	if [ -n "$(TAG_LATEST)" ]; then \
		docker tag \
			$(BUILD_REPO_NAME):latest \
			$(BUILD_REMOTE_REPO):latest; \
	fi

push:
	$(call tc,pushing $(BUILD_REMOTE_TAG) docker container)
	docker push $(BUILD_REMOTE_TAG);

	if [ -n "$(PUSH_LATEST)" ]; then \
		docker push $(BUILD_REMOTE_REPO):latest; \
	fi

up:
	$(call tc,bringing up compose)
	docker compose up --abort-on-container-exit ${BUILD_DISTRIBUTION} \
			|| docker compose stop ${BUILD_DISTRIBUTION} pg-${BUILD_DISTRIBUTION}

up-allpg:
	$(call tc,bringing up compose)
	docker compose up --abort-on-container-exit allpg \
			|| docker compose stop allpg pg-allpg

up-enterprise:
	$(call tc,bringing up compose)
	docker compose up --abort-on-container-exit enterprise \
			|| docker compose stop enterprise pg-enterprise

up-lims_starter:
	$(call tc,bringing up compose)
	docker compose up --abort-on-container-exit lims_starter \
			|| docker compose stop lims_starter pg-lims_starter

down:
	$(call tc,tearing down compose)
	docker compose down -v --remove-orphans

clean:
	docker images | grep -E '$(BUILD_REPO_NAME)|<none>' \
		| awk '{print $$3}' | sort -u | $(_G)xargs -r docker image rm -f \
			&& $(_G)find mounts/logs/ -name '*.log' -type f -print0 \
				| $(_G)xargs -r -0 -t truncate -s0;

test: down
	$(call tc,running smoke tests)
	IDENT=${BUILD_DISTRIBUTION} docker compose up --detach ${BUILD_DISTRIBUTION};
	@./smoke.bash \
		&& printf "##teamcity[progressMessage '%s']\n" 'smoke test succeeded' \
		|| printf "##teamcity[buildProblem description='%s' identity='%s']\n" \
			'smoke test failed' \
			'failure'
	IDENT=${BUILD_DISTRIBUTION} docker compose down -v

pull: login
	docker pull $(BUILD_REMOTE_REPO):$(PULL_TAG)

untagged: login
	$(call tc,removing untagged images from remote repo)
	aws ecr \
		list-images \
		--query 'imageIds[?imageTag == ""].imageDigest' \
		--repository-name $(BUILD_REPO_NAME) \
		--output text \
			| $(_G)xargs \
				-d $$'\t' \
				-t \
				-I{} \
				-r \
				aws ecr \
					batch-delete-image \
					--repository-name $(BUILD_REPO_NAME) \
					--image-ids 'imageDigest={}' \
						| cat
