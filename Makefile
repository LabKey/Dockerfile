SHELL := /usr/bin/env bash

ifeq ($(strip $(findstring Darwin,$(shell uname -a 2>&1 ; ))),)
	_G :=
else
	_G := g
endif

DEBUG ?=

FROM_TAG ?= 17-jre

CACHE_FLAG ?= --no-cache

TAG_LATEST ?=
PUSH_LATEST ?=
IDENT ?= labkey

PULL_TAG ?= latest

AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity | jq -r '.Account' | grep -E '[0-9]{12}' || exit 1)
AWS_REGION ?= $(shell aws configure get region || exit 1)

LABKEY_VERSION ?= 21.5-SNAPSHOT
LABKEY_DISTRIBUTION ?= community
LABKEY_EK ?= 123abc456

# repo/image:tags must be lowercase
BUILD_VERSION ?= $(shell      echo '$(LABKEY_VERSION)'      | tr A-Z a-z)
BUILD_DISTRIBUTION := $(shell echo '$(LABKEY_DISTRIBUTION)' | tr A-Z a-z)

BUILD_REPO_URI ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
BUILD_REPO_NAME := labkey/$(BUILD_DISTRIBUTION)
BUILD_REMOTE_REPO := $(BUILD_REPO_URI)/$(BUILD_REPO_NAME)

BUILD_LOCAL_TAG ?= $(BUILD_REPO_NAME):$(BUILD_VERSION)
BUILD_REMOTE_TAG := $(BUILD_REMOTE_REPO):$(BUILD_VERSION)

ifeq (1,$(DEBUG))
  BUILD_LOCAL_TAG := $(addsuffix -debug,$(BUILD_LOCAL_TAG))
	BUILD_REMOTE_TAG := $(addsuffix -debug,$(BUILD_REMOTE_TAG))
endif

define tc
$(shell printf "%steamcity[progressMessage '%s%n']" '##' '$1' ; )
endef

.PHONY: all build tag login push up up-build down clean

.EXPORT_ALL_VARIABLES:

# default actions are: login, build, tag, then push
all: login build tag push

build:
	$(call tc,building docker container)
	docker build \
		--rm \
		--compress \
		$(CACHE_FLAG) \
		-t $(BUILD_REPO_NAME):latest \
		-t $(BUILD_LOCAL_TAG) \
		--build-arg 'FROM_TAG=$(FROM_TAG)' \
		--build-arg 'DEBUG=$(DEBUG)' \
		--build-arg 'LABKEY_VERSION=$(LABKEY_VERSION)' \
		--build-arg 'LABKEY_DISTRIBUTION=$(BUILD_DISTRIBUTION)' \
		--build-arg 'LABKEY_EK=$(LABKEY_EK)' \
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
	docker-compose up --abort-on-container-exit ${BUILD_DISTRIBUTION} \
			|| docker-compose stop ${BUILD_DISTRIBUTION} pg-${BUILD_DISTRIBUTION}

up-allpg:
	$(call tc,bringing up compose)
	docker-compose up --abort-on-container-exit allpg \
			|| docker-compose stop allpg pg-allpg

up-enterprise:
	$(call tc,bringing up compose)
	docker-compose up --abort-on-container-exit enterprise \
			|| docker-compose stop enterprise pg-enterprise

up-lims_starter:
	$(call tc,bringing up compose)
	docker-compose up --abort-on-container-exit lims_starter \
			|| docker-compose stop lims_starter pg-lims_starter

down:
	$(call tc,tearing down compose)
	docker-compose down -v --remove-orphans

clean:
	docker images | grep -E '$(BUILD_REPO_NAME)|<none>' \
		| awk '{print $$3}' | sort -u | $(_G)xargs -r docker image rm -f \
			&& $(_G)find mounts/logs/ -name '*.log' -type f -print0 \
				| $(_G)xargs -r -0 -t truncate -s0;

test: down
	$(call tc,running smoke tests)
	IDENT=${BUILD_DISTRIBUTION} docker-compose up --detach ${BUILD_DISTRIBUTION};
	@./smoke.bash \
		&& printf "##teamcity[progressMessage '%s']\n" 'smoke test succeeded' \
		|| printf "##teamcity[buildProblem description='%s' identity='%s']\n" \
			'smoke test failed' \
			'failure'
	IDENT=${BUILD_DISTRIBUTION} docker-compose down -v

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
