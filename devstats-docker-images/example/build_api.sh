#!/bin/bash
DOCKER_USER=lukaszgryglicki SKIP_FULL=1 SKIP_MIN=1 SKIP_GRAFANA=1 SKIP_TESTS=1 SKIP_PATRONI=1 SKIP_STATIC=1 SKIP_REPORTS=1 ./images/build_images.sh
