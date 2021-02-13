SHELL := /usr/bin/env bash

DEBUG ?=

AWS_ACCOUNT_ID ?=
AWS_REGION ?=

LABKEY_VERSION ?= 21.2-SNAPSHOT
LABKEY_DISTRIBUTION ?= samplemanagement

# repo/image:tags must be lowercase
BUILD_VERSION := $(shell      echo '$(LABKEY_VERSION)'      | tr A-Z a-z)
BUILD_DISTRIBUTION := $(shell echo '$(LABKEY_DISTRIBUTION)' | tr A-Z a-z)

BUILD_REPO_URI ?= $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
BUILD_REPO_NAME := labkey/$(BUILD_DISTRIBUTION)

BUILD_LOCAL_TAG :=                    $(BUILD_REPO_NAME):$(BUILD_VERSION)
BUILD_REMOTE_TAG := $(BUILD_REPO_URI)/$(BUILD_REPO_NAME):$(BUILD_VERSION)

.PHONY: all build tag login push up up-build down clean

.EXPORT_ALL_VARIABLES:

all: login build tag push

build:
	docker build \
		--rm \
		--compress \
		-t $(BUILD_LOCAL_TAG) \
		-t $(BUILD_REPO_NAME):latest \
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
		$(BUILD_REMOTE_TAG)

push:
	docker push $(BUILD_REMOTE_TAG)

up:
	docker-compose up --abort-on-container-exit \
		|| docker-compose down -v

up-build: build
	docker-compose up \
		--abort-on-container-exit \
			|| docker-compose down -v

down:
	docker-compose down -v

clean:
	docker images | grep '$(BUILD_REPO_NAME)|<none>' \
		| awk '{print $$3}' | sort -u | xargs docker image rm -f
