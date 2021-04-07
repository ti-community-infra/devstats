#!/bin/bash

if [ -z "${DOCKER_USER}" ]
then
  echo "$0: you need to set docker user via DOCKER_USER=username"
  exit 1
fi

cwd="`pwd`"
DEVSTATS_DIR="${cwd}/devstats"
DEVSTATS_CODE_DIR="${cwd}/devstatscode"
DEVSTATS_REPORT_DIR="${cwd}/devstats-reports"
DEVSTATS_DOCKER_IMAGES_DIR="${cwd}/devstats-docker-images"

DEPLOYMENT_DOCKER_IMAGES_DIR="${cwd}/deployments/images"
DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR="${cwd}/deployments/images/temp"

# Ensure those directory is exist.
cd "${DEVSTATS_DIR}" || exit 2
cd "${DEVSTATS_REPORT_DIR}" || exit 39
cd "${DEVSTATS_CODE_DIR}" || exit 3

#
# Package Stage
#
mkdir -p "$DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR"

PATH_TO_DEVSTAT_TAR="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/devstats.tar"
PATH_TO_DEVSTAT_CODE_TAR="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/devstatscode.tar"
PATH_TO_DEVSTAT_GRAFANA_TAR="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/devstats-grafana.tar"
PATH_TO_GRAFANA_BIN_TAR="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/grafana-bins.tar"
PATH_TO_API_SERVER_BIN_TAR="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/api-bins.tar"
PATH_TO_API_DEVSTAT_REPORT_TAR="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/devstats-reports.tar"
PATH_TO_HTML="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/index_*.html"
PATH_TO_SVG="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/*.svg"
PATH_TO_DEVSTAT_DOCKER_IMAGES_TAR="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/devstats-docker-images.tar"
PATH_TO_API_CONFIG_TAR="${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/api-config.tar"

# Package the files in devstatscode repository.
cd "${DEVSTATS_CODE_DIR}" || exit 3
make replacer sqlitedb runq api || exit 4
rm -f "$PATH_TO_DEVSTAT_CODE_TAR" "$PATH_TO_GRAFANA_BIN_TAR" "$PATH_TO_API_SERVER_BIN_TAR" 2>/dev/null

tar cf "$PATH_TO_DEVSTAT_CODE_TAR" cmd vendor *.go || exit 5
tar cf "$PATH_TO_GRAFANA_BIN_TAR" replacer sqlitedb runq || exit 6
tar cf "$PATH_TO_API_SERVER_BIN_TAR" api || exit 44

# Package the files in devstats-report repository.
cd "$DEVSTATS_REPORT_DIR" || exit 40
rm -f "$PATH_TO_API_DEVSTAT_REPORT_TAR" 2>/dev/null
tar cf "$PATH_TO_API_DEVSTAT_REPORT_TAR" sh sql affs rep contributors velocity find.sh || exit 41

# Package the files in devstats repository.
cd "$DEVSTATS_DIR" || exit 7
rm -f "$PATH_TO_DEVSTAT_TAR" "$PATH_TO_DEVSTAT_GRAFANA_TAR" "$PATH_TO_HTML" "$PATH_TO_SVG" 2>/dev/null

tar cf "$PATH_TO_DEVSTAT_TAR" hide git metrics cdf devel util_sql envoy all lfn shared iovisor mininet opennetworkinglab opensecuritycontroller openswitch p4lang openbmp tungstenfabric cord scripts partials docs cron zephyr linux sam azf riff fn openwhisk openfaas cii prestodb godotengine kubernetes prometheus opentracing fluentd linkerd grpc coredns containerd rkt cni jaeger notary tuf rook vitess nats opa spiffe spire cloudevents telepresence helm openmetrics harbor etcd tikv cortex buildpacks falco dragonfly virtualkubelet kubeedge brigade crio networkservicemesh openebs opentelemetry thanos flux intoto strimzi kubevirt longhorn chubaofs keda smi argo volcano cnigenie keptn kudo cloudcustodian dex litmuschaos artifacthub kuma parsec bfe crossplane contour operatorframework chaosmesh serverlessworkflow k3s backstage tremor metal3 porter openyurt openservicemesh keylime schemahero cdk8s certmanager openkruise tinkerbell pravega kyverno gitopswg piraeus k8dash athenz kubeovn curiefense distribution cncf opencontainers istio spinnaker knative tekton jenkins jenkinsx allcdf graphql graphqljs graphiql expressgraphql graphqlspec kubeflow hyperledger jsons/.keep util_sh projects.yaml companies.yaml skip_dates.yaml github_users.json || exit 8
tar cf "$PATH_TO_DEVSTAT_GRAFANA_TAR" grafana/shared grafana/img/*.svg grafana/img/*.png grafana/*/change_title_and_icons.sh grafana/*/custom_sqlite.sql grafana/dashboards/*/*.json || exit 9

cp apache/www/index_*.html "${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/" || exit 22
cp grafana/img/*.svg "${DEPLOYMENT_DOCKER_IMAGES_TEMP_DIR}/" || exit 32

# Package the files in devstats-docker-images repository.
cd "$DEVSTATS_DOCKER_IMAGES_DIR" || exit 10
rm -f "$PATH_TO_DEVSTAT_DOCKER_IMAGES_TAR" "$PATH_TO_API_CONFIG_TAR" 2>/dev/null

tar cf "$PATH_TO_DEVSTAT_DOCKER_IMAGES_TAR" k8s example gql devstats-helm patches images/Makefile.* || exit 11
tar cf "$PATH_TO_API_CONFIG_TAR" devstats-helm/projects.yaml || exit 45

#
# Build Image Stage
#

cd "${DEPLOYMENT_DOCKER_IMAGES_DIR}" || exit 11

if [ -z "$SKIP_FULL" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker build -f Dockerfile.full.test -t "${DOCKER_USER}/devstats-test" . || exit 12
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.full.prod -t "${DOCKER_USER}/devstats-prod" . || exit 33
  fi
fi

if [ -z "$SKIP_MIN" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker build -f Dockerfile.minimal.test -t "${DOCKER_USER}/devstats-minimal-test" . || exit 13
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.minimal.prod -t "${DOCKER_USER}/devstats-minimal-prod" . || exit 35
  fi
fi

if [ -z "$SKIP_GRAFANA" ]
then
  docker build -f Dockerfile.grafana -t "${DOCKER_USER}/devstats-grafana" . || exit 14
fi

if [ -z "$SKIP_TESTS" ]
then
  docker build -f Dockerfile.tests -t "${DOCKER_USER}/devstats-tests" . || exit 15
fi

if [ -z "$SKIP_PATRONI" ]
then
  #docker build -f Dockerfile.patroni -t "${DOCKER_USER}/devstats-patroni" . || exit 16
  docker build -f Dockerfile.patroni -t "${DOCKER_USER}/devstats-patroni-new" . || exit 16
  docker build -f Dockerfile.patroni.13 -t "${DOCKER_USER}/devstats-patroni-13" . || exit 16
fi

if [ -z "$SKIP_STATIC" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker build -f Dockerfile.static.test -t "${DOCKER_USER}/devstats-static-test" . || exit 24
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.static.prod -t "${DOCKER_USER}/devstats-static-prod" . || exit 23
  fi
  docker build -f Dockerfile.static.cdf -t "${DOCKER_USER}/devstats-static-cdf" . || exit 25
  docker build -f Dockerfile.static.graphql -t "${DOCKER_USER}/devstats-static-graphql" . || exit 26
  docker build -f Dockerfile.static.default -t "${DOCKER_USER}/devstats-static-default" . || exit 27
  docker build -f Dockerfile.static.backups -t "${DOCKER_USER}/backups-page" . || exit 42
fi

if [ -z "$SKIP_REPORTS" ]
then
  docker build -f Dockerfile.reports -t "${DOCKER_USER}/devstats-reports" . || exit 37
fi

if [ -z "$SKIP_API" ]
then
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.api -t "${DOCKER_USER}/devstats-api-prod" . || exit 46
  fi
  if [ -z "$SKIP_TEST" ]
  then
    docker build -f Dockerfile.api -t "${DOCKER_USER}/devstats-api-test" . || exit 48
  fi
fi

#
# Clean Stage
#

# Clean the temp file for build.
# TODO: Delete the temp directory directly.
rm -f devstats.tar devstatscode.tar devstats-grafana.tar devstats-docker-images.tar grafana-bins.tar api-bins.tar api-config.tar devstats-reports.tar index_*.html *.svg

#
# Publish Stage
#

# Don't push the images, just build.
if [ ! -z "$SKIP_PUSH" ]
then
  exit 0
fi

# Build docker image for full sync program.
if [ -z "$SKIP_FULL" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker push "${DOCKER_USER}/devstats-test" || exit 17
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-prod" || exit 34
  fi
fi

# Build docker image for minimal sync program.
if [ -z "$SKIP_MIN" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker push "${DOCKER_USER}/devstats-minimal-test" || exit 18
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-minimal-prod" || exit 36
  fi
fi

# Build docker image for grafana.
if [ -z "$SKIP_GRAFANA" ]
then
  docker push "${DOCKER_USER}/devstats-grafana" || exit 19
fi

# Build docker image for tests.
if [ -z "$SKIP_TESTS" ]
then
  docker push "${DOCKER_USER}/devstats-tests" || exit 20
fi

# Build docker image for patroni database.
if [ -z "$SKIP_PATRONI" ]
then
  #docker push "${DOCKER_USER}/devstats-patroni" || exit 21
  docker push "${DOCKER_USER}/devstats-patroni-new" || exit 21
  docker push "${DOCKER_USER}/devstats-patroni-13" || exit 21
fi

# Build docker image for static files.
if [ -z "$SKIP_STATIC" ]
then
  if [ -z "$SKIP_TEST" ]
  then
    docker push "${DOCKER_USER}/devstats-static-test" || exit 28
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-static-prod" || exit 24
  fi
  docker push "${DOCKER_USER}/devstats-static-cdf" || exit 29
  docker push "${DOCKER_USER}/devstats-static-graphql" || exit 30
  docker push "${DOCKER_USER}/devstats-static-default" || exit 31
  docker push "${DOCKER_USER}/backups-page" || exit 43
fi

if [ -z "$SKIP_REPORTS" ]
then
  docker push "${DOCKER_USER}/devstats-reports" || exit 38
fi

# Build docker image for API server.
if [ -z "$SKIP_API" ]
then
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-api-prod" || exit 47
  fi
  if [ -z "$SKIP_TEST" ]
  then
    docker push "${DOCKER_USER}/devstats-api-test" || exit 49
  fi
fi

echo 'OK'
