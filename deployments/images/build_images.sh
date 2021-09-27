#!/bin/bash

#
# Notice: Please make sure you use the script in the project root directory.
#
# For example:
# ```
# DOCKER_USER=ti-community-infra IMAGE_TAG=v0.0.1 SKIP_PUSH=1 SKIP_PATRONI=1 SKIP_TESTS=1 SKIP_PROD=1 ./deployments/images/build_images.sh

#
# SKIP_DEV=1 (skip dev env images)
# SKIP_PROD=1 (skip prod env images)
# SKIP_PUSH=1 (skip push the images)
#

if [ -z "${DOCKER_USER}" ]
then
  echo "$0: you need to set docker user via DOCKER_USER=username"
  exit 1
fi

if [ -z "${IMAGE_TAG}" ]
then
  echo "$0: you need to set docker image tag via IMAGE_TAG=tag"
  exit 2
fi

cwd="$(pwd)"

# Project root directory.
DEVSTATS_ROOT="${cwd}"
DEVSTATS_REPORTS_DIR="${cwd}/devstats-reports"

# Docker images directory.
DEPLOYMENT_DOCKER_IMAGES_DIR="${cwd}/deployments/images"
TEMP_DIR="${cwd}/deployments/images/temp"

# Configuration file directory.
DEVSTATS_CNCF_CONFIG_DIR="${cwd}/devstats"
DEVSTATS_SHARED_CONFIG_DIR="${cwd}/configs/shared"
DEVSTATS_DEV_CONFIG_DIR="${cwd}/configs/dev"
DEVSTATS_PROD_CONFIG_DIR="${cwd}/configs/prod"

# The path to devstats packages.
DEVSTATS_CODE_TAR="${TEMP_DIR}/devstatscode.tar"
DEVSTATS_API_SERVER_BIN_TAR="${TEMP_DIR}/devstats-api-bins.tar"
GRAFANA_TOOL_BIN_TAR="${TEMP_DIR}/grafana-tool-bins.tar"

# The path to config file package.
DEVSTATS_CNCF_CONFIG_TAR="${TEMP_DIR}/devstats-config-cncf.tar"
DEVSTATS_SHARED_CONFIG_TAR="${TEMP_DIR}/devstats-config-shared.tar"
DEVSTATS_DEV_CONFIG_TAR="${TEMP_DIR}/devstats-config-dev.tar"
DEVSTATS_PROD_CONFIG_TAR="${TEMP_DIR}/devstats-config-prod.tar"

DEVSTATS_API_DEV_CONFIG_TAR="${TEMP_DIR}/devstats-api-config-dev.tar"
DEVSTATS_API_PROD_CONFIG_TAR="${TEMP_DIR}/devstats-api-config-prod.tar"


#
# Prepare Stage
#

# Ensure those directory is exist.
cd "${DEVSTATS_CNCF_CONFIG_DIR}" || exit 3
cd "${DEVSTATS_REPORTS_DIR}" || exit 4
cd "${DEPLOYMENT_DOCKER_IMAGES_DIR}" || exit 4

# Create a directory to temporarily store files that need to be written to the image.
mkdir -p "$TEMP_DIR"

#
# Package Stage
#

# Package the sourcecode and binary of devstats.
cd "${DEVSTATS_ROOT}" || exit 6
make replacer sqlitedb runq apiserver || exit 7

if [ -n "$DEVSTATS_CODE_TAR" ]
then
  rm -f "$DEVSTATS_CODE_TAR" 2>/dev/null
fi

if [ -n "$DEVSTATS_API_SERVER_BIN_TAR" ]
then
  rm -f "$DEVSTATS_API_SERVER_BIN_TAR" 2>/dev/null
fi

if [ -n "$GRAFANA_TOOL_BIN_TAR" ]
then
  rm -f "$GRAFANA_TOOL_BIN_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_CODE_TAR" cmd cron devel git internal tools/check go.mod go.sum .git .golangci.yml Makefile || exit 5
tar cf "$DEVSTATS_API_SERVER_BIN_TAR" apiserver || exit 44
tar cf "$GRAFANA_TOOL_BIN_TAR" replacer sqlitedb runq || exit 6

# Package the configs files from cncf/devstats.
cd "$DEVSTATS_CNCF_CONFIG_DIR" || exit 7

if [ -n "$DEVSTATS_CNCF_CONFIG_TAR" ]
then
  rm -f "$DEVSTATS_CNCF_CONFIG_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_CNCF_CONFIG_TAR" hide git metrics devel shared scripts cron docs jsons/.keep util_sql util_sh github_users.json companies.yaml skip_dates.yaml  || exit 8

#
# Pack the configuration files of different environments into different compressed packages,
# and then decompress them when building the image for overwriting default config.
#
# TODO: Move the project psql.sh file to the projects directory
# so that we don't need to update the build_images.sh when we add a new project.
#

# Package the shared config file.
# Notice: This file will override the config files from cncf/devstats repository.
cd "$DEVSTATS_SHARED_CONFIG_DIR" || exit 62

if [ -n "$DEVSTATS_SHARED_CONFIG_TAR" ]
then
  rm -f "$DEVSTATS_SHARED_CONFIG_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_SHARED_CONFIG_TAR" ./*

# Package the devstats config file for dev environment.
# Notice: This file will override the config files from shared directory and cncf/devstats repository.
if [ -z "$SKIP_DEV" ]
then
  cd "$DEVSTATS_DEV_CONFIG_DIR" || exit 61

  if [ -n "$DEVSTATS_DEV_CONFIG_TAR" ]
  then
    rm -f "$DEVSTATS_DEV_CONFIG_TAR" 2>/dev/null
  fi

  tar cf "$DEVSTATS_DEV_CONFIG_TAR" all tidb tikv chaosmesh ob metrics scripts devel docs projects.yaml
  tar cf "$DEVSTATS_API_DEV_CONFIG_TAR" projects.yaml
fi

# Package the devstats config file for prod environment.
# Notice: This file will override the config files from shared directory and cncf/devstats repository.
if [ -z "$SKIP_PROD" ]
then
  cd "$DEVSTATS_PROD_CONFIG_DIR" || exit 62

  tar cf "$DEVSTATS_PROD_CONFIG_TAR" all tidb tikv chaosmesh ob metrics scripts devel docs projects.yaml
  tar cf "$DEVSTATS_API_PROD_CONFIG_TAR" projects.yaml
fi

#
# Build Image Stage
#

cd "${DEPLOYMENT_DOCKER_IMAGES_DIR}" || exit 11

if [ -z "$SKIP_FULL" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker build -f Dockerfile.full.dev -t "${DOCKER_USER}/devstats-dev:${IMAGE_TAG}" . || exit 12
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.full.prod -t "${DOCKER_USER}/devstats-prod:${IMAGE_TAG}" . || exit 33
  fi
fi

if [ -z "$SKIP_MIN" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker build -f Dockerfile.minimal.dev -t "${DOCKER_USER}/devstats-minimal-dev:${IMAGE_TAG}" . || exit 13
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.minimal.prod -t "${DOCKER_USER}/devstats-minimal-prod:${IMAGE_TAG}" . || exit 35
  fi
fi

if [ -z "$SKIP_GRAFANA" ]
then
  docker build -f Dockerfile.grafana -t "${DOCKER_USER}/devstats-grafana:${IMAGE_TAG}" . || exit 36
fi

if [ -z "$SKIP_API" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker build -f Dockerfile.api.dev -t "${DOCKER_USER}/devstats-api-dev:${IMAGE_TAG}" . || exit 48
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.api.prod -t "${DOCKER_USER}/devstats-api-prod:${IMAGE_TAG}" . || exit 46
  fi
fi


#
# Clean Stage
#

# Clean the temp file for build.
if [ -n "$TEMP_DIR" ]
then
  rm -rf "$TEMP_DIR"
fi

#
# Push Stage
#

# Don't push the images, just build.
if [ -n "$SKIP_PUSH" ]
then
  exit 0
fi

# Build docker image for full sync.
if [ -z "$SKIP_FULL" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker push "${DOCKER_USER}/devstats-dev:${IMAGE_TAG}" || exit 17
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-prod:${IMAGE_TAG}" || exit 34
  fi
fi

# Build docker image for minimal sync.
if [ -z "$SKIP_MIN" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker push "${DOCKER_USER}/devstats-minimal-dev:${IMAGE_TAG}" || exit 18
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-minimal-prod:${IMAGE_TAG}" || exit 36
  fi
fi

# Build docker image for grafana.
if [ -z "$SKIP_GRAFANA" ]
then
  docker push "${DOCKER_USER}/devstats-grafana:${IMAGE_TAG}" || exit 19
fi

# Build docker image for API server.
if [ -z "$SKIP_API" ]
then
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-api-prod:${IMAGE_TAG}" || exit 47
  fi
  if [ -z "$SKIP_DEV" ]
  then
    docker push "${DOCKER_USER}/devstats-api-dev:${IMAGE_TAG}" || exit 49
  fi
fi

echo 'OK'
