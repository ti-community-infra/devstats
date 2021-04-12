#!/bin/bash

#
# Notice: Please make sure you use the script in the project root directory.
#
# For example:
# ```
# DOCKER_USER=miniantdev SKIP_PUSH=1 SKIP_PATRONI=1 SKIP_TESTS=1 SKIP_PROD=1 ./deployments/images/build_images.sh

#
# SKIP_TEST=1 (skip test images)
# SKIP_PROD=1 (skip prod images)
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
  exit 1
fi

cwd="$(pwd)"

# Configuration file directory.
DEV_CONFIG_DIR="${cwd}/configs/dev"
PROD_CONFIG_DIR="${cwd}/configs/prod"

# Submodule directory.
DEVSTATS_DIR="${cwd}/devstats"
DEVSTATS_CODE_DIR="${cwd}/devstatscode"
DEVSTATS_REPORT_DIR="${cwd}/devstats-reports"

# Docker images directory.
DEPLOYMENT_DOCKER_IMAGES_DIR="${cwd}/deployments/images"
TEMP_DIR="${cwd}/deployments/images/temp"

# The path to devstats package.
DEVSTATS_TAR="${TEMP_DIR}/devstats.tar"
DEVSTATS_CODE_TAR="${TEMP_DIR}/devstatscode.tar"
DEVSTATS_GRAFANA_TAR="${TEMP_DIR}/devstats-grafana.tar"
DEVSTATS_REPORTS_TAR="${TEMP_DIR}/devstats-reports.tar"
DEVSTATS_DOCKER_IMAGES_TAR="${TEMP_DIR}/devstats-docker-images.tar"

GRAFANA_BIN_TAR="${TEMP_DIR}/grafana-bins.tar"
API_SERVER_BIN_TAR="${TEMP_DIR}/api-bins.tar"

# The path to static file package.
HTML_FILES="${TEMP_DIR}/index_*.html"
SVG_FILES="${TEMP_DIR}/*.svg"

# The path to config file package.
DEV_CONFIG_TAR="${TEMP_DIR}/devstats-config-dev.tar"
PROD_CONFIG_TAR="${TEMP_DIR}/devstats-config-prod.tar"

DEV_GRAFANA_CONFIG_TAR="${TEMP_DIR}/devstats-grafana-config-dev.tar"
PROD_GRAFANA_CONFIG_TAR="${TEMP_DIR}/devstats-grafana-config-prod.tar"

DEV_API_CONFIG_TAR="${TEMP_DIR}/devstats-api-config-dev.tar"
PROD_API_CONFIG_TAR="${TEMP_DIR}/devstats-api-config-prod.tar"


#
# Prepare Stage
#

# Ensure those directory is exist.
cd "${DEVSTATS_DIR}" || exit 2
cd "${DEVSTATS_REPORT_DIR}" || exit 39
cd "${DEVSTATS_CODE_DIR}" || exit 3

# Create a directory to temporarily store files that need to be written to the image.
mkdir -p "$TEMP_DIR"


#
# Package Stage
#

# Package the files in devstatscode repository.
cd "${DEVSTATS_CODE_DIR}" || exit 3
make replacer sqlitedb runq api || exit 4

if [ -n "$DEVSTATS_CODE_TAR" ] && [ -n "$GRAFANA_BIN_TAR" ] && [ -n "$API_SERVER_BIN_TAR" ]
then
  rm -f "$DEVSTATS_CODE_TAR" "$GRAFANA_BIN_TAR" "$API_SERVER_BIN_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_CODE_TAR" cmd vendor *.go || exit 5
tar cf "$GRAFANA_BIN_TAR" replacer sqlitedb runq || exit 6
tar cf "$API_SERVER_BIN_TAR" api || exit 44

# Package the files in devstats-report repository.
cd "$DEVSTATS_REPORT_DIR" || exit 40

if [ -n "$DEVSTATS_REPORTS_TAR" ]
then
  rm -f "$DEVSTATS_REPORTS_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_REPORTS_TAR" sh sql affs rep contributors velocity find.sh || exit 41

# Package the files in devstats repository for common config.
cd "$DEVSTATS_DIR" || exit 7

if [ -n "$DEVSTATS_TAR" ] && [ -n "$DEVSTATS_GRAFANA_TAR" ] && [ -n "$HTML_FILES" ] && [ -n "$SVG_FILES" ]
then
  rm -f "$DEVSTATS_TAR" "$DEVSTATS_GRAFANA_TAR" "$HTML_FILES" "$SVG_FILES" 2>/dev/null
fi

tar cf "$DEVSTATS_TAR" hide git metrics devel shared scripts partials cron docs jsons/.keep util_sql util_sh github_users.json companies.yaml skip_dates.yaml  || exit 8
tar cf "$DEVSTATS_GRAFANA_TAR" grafana/shared || exit 9

# Copy static file to temp directory, for copying to the docker image.
cd "$DEVSTATS_DIR" || exit 7

cp apache/www/index_*.html "${TEMP_DIR}/" || exit 22
cp grafana/img/*.svg "${TEMP_DIR}/" || exit 32

# Package the files in devstats-docker-images repository.
cd "$DEPLOYMENT_DOCKER_IMAGES_DIR" || exit 10

if [ -n "$DEVSTATS_DOCKER_IMAGES_TAR" ]
then
  rm -f "$DEVSTATS_DOCKER_IMAGES_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_DOCKER_IMAGES_TAR" patches Makefile.* || exit 11

#
# Pack the configuration files of different environments into different compressed packages,
# and then decompress them when building the image for overwriting default config.
#
# TODO: Move the project psql.sh file to the projects directory
# so that we don't need to update the build_images.sh when we add a new project.
#

# Package the devstat config file for test environment.
if [ -z "$SKIP_TEST" ]
then
  # Patch the custom config file.
  cd "$DEV_CONFIG_DIR" || exit 61

  tar rf "$DEV_CONFIG_TAR" tidb tikv chaosmesh metrics partials scripts devel docs projects.yaml
  tar rf "$DEV_GRAFANA_CONFIG_TAR" grafana/img/*.svg grafana/img/*.png grafana/*/change_title_and_icons.sh grafana/dashboards/*/*.json
  tar rf "$DEV_GRAFANA_CONFIG_TAR" grafana/*/custom_sqlite.sql
  tar cf "$DEV_API_CONFIG_TAR" projects.yaml
fi

# Package the devstat config file for prod environment.
if [ -z "$SKIP_PROD" ]
then
  # Patch the custom config file.
  cd "$PROD_CONFIG_DIR" || exit 62

  tar rf "$PROD_CONFIG_TAR" tidb tikv chaosmesh metrics partials scripts devel docs projects.yaml
  tar rf "$PROD_GRAFANA_CONFIG_TAR" grafana/img/*.svg grafana/img/*.png grafana/*/change_title_and_icons.sh grafana/dashboards/*/*.json
  tar rf "$PROD_GRAFANA_CONFIG_TAR" grafana/*/custom_sqlite.sql
  tar cf "$PROD_API_CONFIG_TAR" projects.yaml
fi

#
# Build Image Stage
#

cd "${DEPLOYMENT_DOCKER_IMAGES_DIR}" || exit 11

if [ -z "$SKIP_FULL" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker build -f Dockerfile.full.test -t "${DOCKER_USER}/devstats-test:${IMAGE_TAG}" . || exit 12
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.full.prod -t "${DOCKER_USER}/devstats-prod:${IMAGE_TAG}" . || exit 33
  fi
fi

if [ -z "$SKIP_MIN" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker build -f Dockerfile.minimal.test -t "${DOCKER_USER}/devstats-minimal-test:${IMAGE_TAG}" . || exit 13
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.minimal.prod -t "${DOCKER_USER}/devstats-minimal-prod:${IMAGE_TAG}" . || exit 35
  fi
fi

if [ -z "$SKIP_GRAFANA" ]
then
  docker build -f Dockerfile.grafana -t "${DOCKER_USER}/devstats-grafana:${IMAGE_TAG}" . || exit 14
fi

if [ -z "$SKIP_TESTS" ]
then
  docker build -f Dockerfile.tests -t "${DOCKER_USER}/devstats-tests:${IMAGE_TAG}" . || exit 15
fi

if [ -z "$SKIP_PATRONI" ]
then
  #docker build -f Dockerfile.patroni -t "${DOCKER_USER}/devstats-patroni:${IMAGE_TAG}" . || exit 16
  docker build -f Dockerfile.patroni -t "${DOCKER_USER}/devstats-patroni-new:${IMAGE_TAG}" . || exit 16
  docker build -f Dockerfile.patroni.13 -t "${DOCKER_USER}/devstats-patroni-13:${IMAGE_TAG}" . || exit 16
fi

if [ -z "$SKIP_STATIC" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker build -f Dockerfile.static.test -t "${DOCKER_USER}/devstats-static-test:${IMAGE_TAG}" . || exit 24
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.static.prod -t "${DOCKER_USER}/devstats-static-prod:${IMAGE_TAG}" . || exit 23
  fi
  docker build -f Dockerfile.static.default -t "${DOCKER_USER}/devstats-static-default:${IMAGE_TAG}" . || exit 27
  docker build -f Dockerfile.static.backups -t "${DOCKER_USER}/backups-page:${IMAGE_TAG}" . || exit 42
fi

if [ -z "$SKIP_REPORTS" ]
then
  docker build -f Dockerfile.reports -t "${DOCKER_USER}/devstats-reports:${IMAGE_TAG}" . || exit 37
fi

if [ -z "$SKIP_API" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker build -f Dockerfile.api.test -t "${DOCKER_USER}/devstats-api-test:${IMAGE_TAG}" . || exit 48
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
if [ ! -z "$SKIP_PUSH" ]
then
  exit 0
fi

# Build docker image for full sync.
if [ -z "$SKIP_FULL" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker push "${DOCKER_USER}/devstats-test:${IMAGE_TAG}" || exit 17
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-prod:${IMAGE_TAG}" || exit 34
  fi
fi

# Build docker image for minimal sync.
if [ -z "$SKIP_MIN" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker push "${DOCKER_USER}/devstats-minimal-test:${IMAGE_TAG}" || exit 18
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

# Build docker image for tests.
if [ -z "$SKIP_TESTS" ]
then
  docker push "${DOCKER_USER}/devstats-tests:${IMAGE_TAG}" || exit 20
fi

# Build docker image for patroni database.
if [ -z "$SKIP_PATRONI" ]
then
  #docker push "${DOCKER_USER}/devstats-patroni" || exit 21
  docker push "${DOCKER_USER}/devstats-patroni-new:${IMAGE_TAG}" || exit 21
  docker push "${DOCKER_USER}/devstats-patroni-13:${IMAGE_TAG}" || exit 21
fi

# Build docker image for static files.
if [ -z "$SKIP_STATIC" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker push "${DOCKER_USER}/devstats-static-test:${IMAGE_TAG}" || exit 28
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-static-prod:${IMAGE_TAG}" || exit 24
  fi
  docker push "${DOCKER_USER}/devstats-static-default:${IMAGE_TAG}" || exit 31
  docker push "${DOCKER_USER}/backups-page:${IMAGE_TAG}" || exit 43
fi

if [ -z "$SKIP_REPORTS" ]
then
  docker push "${DOCKER_USER}/devstats-reports:${IMAGE_TAG}" || exit 38
fi

# Build docker image for API server.
if [ -z "$SKIP_API" ]
then
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-api-prod:${IMAGE_TAG}" || exit 47
  fi
  if [ -z "$SKIP_TEST" ]
  then
    docker push "${DOCKER_USER}/devstats-api-test:${IMAGE_TAG}" || exit 49
  fi
fi

echo 'OK'
