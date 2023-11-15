#!/bin/bash

# example minimal set of environment variables to get started - see readme for additional envs you may wish to set

# embedded tomcat LabKey .jar version to build container with
export LABKEY_VERSION="23.10.0"

# minimal SMTP settings
export SMTP_HOST="localhost"
export SMTP_PASSWORD=""
export SMTP_PORT="25"
export SMTP_USER="root"
export SMTP_FROM="root@localhost"

# Setting these two envs to empty strings defaults LabKey startup to typical first user setup wizard
export LABKEY_CREATE_INITIAL_USER=""
export LABKEY_CREATE_INITIAL_USER_APIKEY=""

export LABKEY_DEFAULT_PROPERTIES_S3_URI="none"
export LABKEY_CUSTOM_PROPERTIES_S3_URI="none"
