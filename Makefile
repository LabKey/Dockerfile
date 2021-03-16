SHELL := /usr/bin/env bash

ifeq ($(strip $(findstring Darwin,$(shell uname -a 2>&1 ; ))),)
	_G :=
else
	_G := g
endif

DEBUG ?=

CACHE_FLAG ?= --no-cache

TAG_LATEST ?=
PUSH_LATEST ?=

PULL_TAG ?= latest

AWS_ACCOUNT_ID ?=
AWS_REGION ?=

LABKEY_VERSION ?= 21.4-SNAPSHOT
LABKEY_DISTRIBUTION ?= community

# repo/image:tags must be lowercase
BUILD_VERSION := $(shell      echo '$(LABKEY_VERSION)'      | tr A-Z a-z)
BUILD_DISTRIBUTION := $(shell echo '$(LABKEY_DISTRIBUTION)' | tr A-Z a-z)

BUILD_REPO_URI ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
BUILD_REPO_NAME := labkey/$(BUILD_DISTRIBUTION)
BUILD_REMOTE_REPO := $(BUILD_REPO_URI)/$(BUILD_REPO_NAME)

BUILD_LOCAL_TAG := $(BUILD_REPO_NAME):$(BUILD_VERSION)
BUILD_REMOTE_TAG := $(BUILD_REMOTE_REPO):$(BUILD_VERSION)

.PHONY: all build tag login push up up-build down clean

.EXPORT_ALL_VARIABLES:

# default actions are: login, build, tag, then push
all: login build tag push

build:
	docker build \
		--rm \
		--compress \
		$(CACHE_FLAG) \
		-t $(BUILD_LOCAL_TAG) \
		--build-arg 'DEBUG=$(DEBUG)' \
		--build-arg 'LABKEY_VERSION=$(LABKEY_VERSION)' \
		--build-arg 'LABKEY_DISTRIBUTION=$(BUILD_DISTRIBUTION)' \
		.

login:
	aws --region $(AWS_REGION) ecr get-login-password \
		| docker login \
			--username AWS \
			--password-stdin \
			$(BUILD_REPO_URI)

tag:
	docker tag \
		$(BUILD_LOCAL_TAG) \
		$(BUILD_REMOTE_TAG);

	if [ -n "$(TAG_LATEST)" ]; then \
		docker tag \
			$(BUILD_LOCAL_TAG) \
			$(BUILD_REPO_NAME):latest; \
		\
		docker tag \
			$(BUILD_REPO_NAME):latest \
			$(BUILD_REMOTE_REPO):latest; \
	fi

push:
	docker push $(BUILD_REMOTE_TAG);

	if [ -n "$(PUSH_LATEST)" ]; then \
		docker push $(BUILD_REMOTE_REPO):latest; \
	fi

up:
	docker-compose up \
		--abort-on-container-exit \
			|| docker-compose down -v

down:
	docker-compose down -v --remove-orphans

clean:
	docker images | grep -E '$(BUILD_REPO_NAME)|<none>' \
		| awk '{print $$3}' | sort -u | $(_G)xargs -r docker image rm -f \
			&& $(_G)find mounts/logs/ -name '*.log' -type f -print0 \
				| $(_G)xargs -r -0 -t truncate -s0;

test: down
	docker-compose up --detach;
	@./smoke.bash \
		&& printf "##teamcity[progressMessage '%s']\n" 'smoke test succeeded' \
		|| printf "##teamcity[buildProblem description='%s' identity='%s']\n" \
			'smoke test failed' \
			'failure'
	docker-compose down -v

pull: login
	docker pull $(BUILD_REMOTE_REPO):$(PULL_TAG)
