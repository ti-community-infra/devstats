PROJECT=devstats
GOPATH ?= $(shell go env GOPATH)

# Ensure GOPATH is set before running build process.
ifeq "$(GOPATH)" ""
  $(error Please set the environment variable GOPATH before running `make`)
endif
FAIL_ON_STDOUT := awk '{ print } END { if (NR > 0) { exit 1 } }'

CURDIR := $(shell pwd)
path_to_add := $(addsuffix /bin,$(subst :,/bin:,$(GOPATH))):$(PWD)/tools/bin
export PATH := $(path_to_add):$(PATH)

BUILD_TIME		= `date -u '+%Y-%m-%d_%I:%M:%S%p'`
COMMIT			= `git rev-parse HEAD`
HOSTNAME		= `uname -a | sed "s/ /_/g"`
GO_VERSION		= `go version | sed "s/ /_/g"`
BINARY_PATH		= /devstats-bins/
DATA_DIR		= /etc/gha2db

GO              := GO111MODULE=on go
GOBUILD         := $(GO) build
GOTEST          := $(GO) test
GO_ENV			= CGO_ENABLED=0				#for race CGO_ENABLED=1
STRIP			= strip

#For static gcc linking
#GCC_STATIC=-ldflags '-extldflags "-static"'

# -ldflags '-s -w': create release binary - without debug info
#  -ldflags '-s': install stripped binary
GO_BUILD=go build -ldflags "-s -w -X github.com/ti-community-infra/devstats.BuildStamp=$(BUILD_TIME) -X github.com/ti-community-infra/devstats.GitHash=$(COMMIT) -X github.com/ti-community-infra/devstats.HostName=$(HOSTNAME) -X github.com/ti-community-infra/devstats.GoVersion=$(GO_VERSION)"
#GO_BUILD=go build -ldflags "-s -w -X github.com/ti-community-infra/devstats.BuildStamp=$(BUILD_TIME) -X github.com/ti-community-infra/devstats.GitHash=$(COMMIT) -X github.com/ti-community-infra/devstats.HostName=$(HOSTNAME) -X github.com/ti-community-infra/devstats.GoVersion=$(GO_VERSION)" -race

GO_INSTALL=go install -ldflags "-s -w -X github.com/ti-community-infra/devstats.BuildStamp=$(BUILD_TIME) -X github.com/ti-community-infra/devstats.GitHash=$(COMMIT) -X github.com/ti-community-infra/devstats.HostName=$(HOSTNAME) -X github.com/ti-community-infra/devstats.GoVersion=$(GO_VERSION)"

# Source code file.

PACKAGE_LIST  := go list ./... | grep -v "dbtest"
PACKAGES  := $$($(PACKAGE_LIST))
PACKAGE_DIRECTORIES := $(PACKAGE_LIST) | sed 's|github.com/ti-community-infra/$(PROJECT)/||'
FILES     := $$(find $$($(PACKAGE_DIRECTORIES)) -name "*.go")

GO_LIB_FILES=internal/pkg/lib/pg_conn.go internal/pkg/lib/error.go internal/pkg/lib/mgetc.go internal/pkg/lib/map.go internal/pkg/lib/threads.go internal/pkg/lib/gha.go internal/pkg/lib/json.go internal/pkg/lib/time.go internal/pkg/lib/context.go internal/pkg/lib/exec.go internal/pkg/lib/structure.go internal/pkg/lib/log.go internal/pkg/lib/hash.go internal/pkg/lib/unicode.go internal/pkg/lib/const.go internal/pkg/lib/string.go internal/pkg/lib/annotations.go internal/pkg/lib/env.go internal/pkg/lib/ghapi.go internal/pkg/lib/io.go internal/pkg/lib/tags.go internal/pkg/lib/yaml.go internal/pkg/lib/es_conn.go internal/pkg/lib/orm_conn.go internal/pkg/lib/ts_points.go internal/pkg/lib/convert.go internal/pkg/identifier/identifier.go internal/pkg/identifier/context.go internal/pkg/storage/model/gha.go internal/pkg/storage/model/identifier.go
GO_BIN_FILES=cmd/structure/structure.go cmd/runq/runq.go cmd/gha2db/gha2db.go cmd/calc_metric/calc_metric.go cmd/gha2db_sync/gha2db_sync.go cmd/import_affs/import_affs.go cmd/annotations/annotations.go cmd/tags/tags.go cmd/webhook/webhook.go cmd/devstats/devstats.go cmd/get_repos/get_repos.go cmd/merge_dbs/merge_dbs.go cmd/replacer/replacer.go cmd/vars/vars.go cmd/ghapi2db/ghapi2db.go cmd/columns/columns.go cmd/hide_data/hide_data.go cmd/sqlitedb/sqlitedb.go cmd/website_data/website_data.go cmd/sync_issues/sync_issues.go cmd/gha2es/gha2es.go cmd/api/api.go cmd/identifier/identifier.go cmd/sync_teams/sync_teams.go
GO_DBTEST_FILES=internal/pkg/dbtest/pg_test.go internal/pkg/dbtest/series_test.go

# Binary file.

GO_BIN_CMDS=github.com/ti-community-infra/devstats/cmd/structure github.com/ti-community-infra/devstats/cmd/runq github.com/ti-community-infra/devstats/cmd/gha2db github.com/ti-community-infra/devstats/cmd/calc_metric github.com/ti-community-infra/devstats/cmd/gha2db_sync github.com/ti-community-infra/devstats/cmd/import_affs github.com/ti-community-infra/devstats/cmd/annotations github.com/ti-community-infra/devstats/cmd/tags github.com/ti-community-infra/devstats/cmd/webhook github.com/ti-community-infra/devstats/cmd/devstats github.com/ti-community-infra/devstats/cmd/get_repos github.com/ti-community-infra/devstats/cmd/merge_dbs github.com/ti-community-infra/devstats/cmd/replacer github.com/ti-community-infra/devstats/cmd/vars github.com/ti-community-infra/devstats/cmd/ghapi2db github.com/ti-community-infra/devstats/cmd/columns github.com/ti-community-infra/devstats/cmd/hide_data github.com/ti-community-infra/devstats/cmd/sqlitedb github.com/ti-community-infra/devstats/cmd/website_data github.com/ti-community-infra/devstats/cmd/sync_issues github.com/ti-community-infra/devstats/cmd/gha2es github.com/ti-community-infra/devstats/cmd/api github.com/ti-community-infra/devstats/cmd/identifier github.com/ti-community-infra/devstats/cmd/sync_teams
GO_DOCKER_FULL_BIN_CMDS=github.com/ti-community-infra/devstats/cmd/structure github.com/ti-community-infra/devstats/cmd/gha2db github.com/ti-community-infra/devstats/cmd/calc_metric github.com/ti-community-infra/devstats/cmd/gha2db_sync github.com/ti-community-infra/devstats/cmd/import_affs github.com/ti-community-infra/devstats/cmd/annotations github.com/ti-community-infra/devstats/cmd/tags github.com/ti-community-infra/devstats/cmd/devstats github.com/ti-community-infra/devstats/cmd/get_repos github.com/ti-community-infra/devstats/cmd/vars github.com/ti-community-infra/devstats/cmd/ghapi2db github.com/ti-community-infra/devstats/cmd/columns github.com/ti-community-infra/devstats/cmd/gha2es github.com/ti-community-infra/devstats/cmd/runq github.com/ti-community-infra/devstats/cmd/replacer github.com/ti-community-infra/devstats/cmd/hide_data github.com/ti-community-infra/devstats/cmd/merge_dbs github.com/ti-community-infra/devstats/cmd/api github.com/ti-community-infra/devstats/cmd/identifier github.com/ti-community-infra/devstats/cmd/sync_teams
GO_DOCKER_MINIMAL_BIN_CMDS=github.com/ti-community-infra/devstats/cmd/structure github.com/ti-community-infra/devstats/cmd/gha2db github.com/ti-community-infra/devstats/cmd/calc_metric github.com/ti-community-infra/devstats/cmd/gha2db_sync github.com/ti-community-infra/devstats/cmd/annotations github.com/ti-community-infra/devstats/cmd/tags github.com/ti-community-infra/devstats/cmd/devstats github.com/ti-community-infra/devstats/cmd/get_repos github.com/ti-community-infra/devstats/cmd/ghapi2db github.com/ti-community-infra/devstats/cmd/columns github.com/ti-community-infra/devstats/cmd/gha2es github.com/ti-community-infra/devstats/cmd/vars github.com/ti-community-infra/devstats/cmd/runq github.com/ti-community-infra/devstats/cmd/api

BINARIES=structure gha2db calc_metric gha2db_sync import_affs annotations tags webhook devstats get_repos merge_dbs replacer vars ghapi2db columns hide_data website_data sync_issues gha2es runq api sqlitedb identifier sync_teams
DOCKER_FULL_BINARIES=structure gha2db calc_metric gha2db_sync import_affs annotations tags devstats get_repos vars ghapi2db columns gha2es api runq replacer hide_data merge_dbs sync_issues identifier sync_teams
DOCKER_MINIMAL_BINARIES=structure gha2db calc_metric gha2db_sync annotations tags devstats get_repos ghapi2db columns gha2es vars runq api

# Script file.

CRON_SCRIPTS=cron/cron_db_backup.sh cron/sysctl_config.sh cron/backup_artificial.sh
UTIL_SCRIPTS=devel/wait_for_command.sh devel/cronctl.sh devel/sync_lock.sh devel/sync_unlock.sh devel/db.sh
GIT_SCRIPTS=git/git_reset_pull.sh git/git_files.sh git/git_tags.sh git/last_tag.sh git/git_loc.sh

# Entry

.PHONY: clean test cover fmt tidy staticcheck dev check build dbtest

dev: check staticcheck test

check: fmt tidy

build: ${BINARIES}
	@echo "Build all."

# Test

test:
	$(GOTEST) $(PACKAGES)
	@>&2 echo "Great, all tests passed."

dbtest:
	${GO_TEST} ${GO_DBTEST_FILES}

# Tool chain

cover:
	rm -rf coverage.txt
	$(GOTEST) $(PACKAGES) -race -coverprofile=coverage.txt -covermode=atomic
	echo "Uploading coverage results..."
	@curl -s https://codecov.io/bash | bash

fmt:
	@echo "gofmt (simplify)"
	@gofmt -s -l -w $(FILES) 2>&1 | $(FAIL_ON_STDOUT)

tidy:
	@echo "go mod tidy"
	./tools/check/check-tidy.sh

staticcheck: tools/bin/golangci-lint
	tools/bin/golangci-lint run  $$($(PACKAGE_DIRECTORIES)) --timeout 500s

tools/bin/golangci-lint:
	curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh| sh -s -- -b ./tools/bin v1.41.1

# Build

structure: cmd/structure/structure.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o structure cmd/structure/structure.go

runq: cmd/runq/runq.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o runq cmd/runq/runq.go

api: cmd/api/api.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o api cmd/api/api.go

gha2db: cmd/gha2db/gha2db.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o gha2db cmd/gha2db/gha2db.go

gha2es: cmd/gha2es/gha2es.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o gha2es cmd/gha2es/gha2es.go

calc_metric: cmd/calc_metric/calc_metric.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o calc_metric cmd/calc_metric/calc_metric.go

import_affs: cmd/import_affs/import_affs.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o import_affs cmd/import_affs/import_affs.go

gha2db_sync: cmd/gha2db_sync/gha2db_sync.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o gha2db_sync cmd/gha2db_sync/gha2db_sync.go

devstats: cmd/devstats/devstats.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o devstats cmd/devstats/devstats.go

annotations: cmd/annotations/annotations.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o annotations cmd/annotations/annotations.go

tags: cmd/tags/tags.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o tags cmd/tags/tags.go

columns: cmd/columns/columns.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o columns cmd/columns/columns.go

webhook: cmd/webhook/webhook.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o webhook cmd/webhook/webhook.go

get_repos: cmd/get_repos/get_repos.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o get_repos cmd/get_repos/get_repos.go

merge_dbs: cmd/merge_dbs/merge_dbs.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o merge_dbs cmd/merge_dbs/merge_dbs.go

vars: cmd/vars/vars.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o vars cmd/vars/vars.go

ghapi2db: cmd/ghapi2db/ghapi2db.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o ghapi2db cmd/ghapi2db/ghapi2db.go

sync_issues: cmd/sync_issues/sync_issues.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o sync_issues cmd/sync_issues/sync_issues.go

replacer: cmd/replacer/replacer.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o replacer cmd/replacer/replacer.go

hide_data: cmd/hide_data/hide_data.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o hide_data cmd/hide_data/hide_data.go

website_data: cmd/website_data/website_data.go ${GO_LIB_FILES}
	 ${GO_ENV} ${GO_BUILD} -o website_data cmd/website_data/website_data.go

sqlitedb: cmd/sqlitedb/sqlitedb.go ${GO_LIB_FILES}
	 ${GO_BUILD} ${GCC_STATIC} -o sqlitedb cmd/sqlitedb/sqlitedb.go

identifier: cmd/identifier/identifier.go ${GO_LIB_FILES}
	${GO_ENV} ${GO_BUILD} ${GCC_STATIC} -o identifier cmd/identifier/identifier.go

sync_teams: cmd/sync_teams/sync_teams.go ${GO_LIB_FILES}
	${GO_ENV} ${GO_BUILD} ${GCC_STATIC} -o sync_teams cmd/sync_teams/sync_teams.go

# Install

util_scripts:
	cp -v ${UTIL_SCRIPTS} ${GOPATH}/bin

# Full install to image.
copy_full_data: util_scripts
	mkdir -p ${DATA_DIR} 2>/dev/null || echo "..."
	chmod 777 ${DATA_DIR} 2>/dev/null || echo "..."
ifneq "$(DATA_DIR)" ""
	rm -rf ${DATA_DIR}/* || exit 3
endif
	cp -R metrics/ ${DATA_DIR}/metrics/ || exit 4
	cp -R util_sql/ ${DATA_DIR}/util_sql/ || exit 5
	cp -R util_sh/ ${DATA_DIR}/util_sh/ || exit 6
	cp -R docs/ ${DATA_DIR}/docs/ || exit 7
	cp -R jsons/ ${DATA_DIR}/jsons/ || exit 8
	chmod 777 ${DATA_DIR}/jsons/ || exit 8
	cp -R scripts/ ${DATA_DIR}/scripts/ || exit 9
	cp devel/*.txt ${DATA_DIR}/ || exit 11
	cp github_users.json projects.yaml companies.yaml skip_dates.yaml ${DATA_DIR}/ || exit 12

docker_full_install: ${DOCKER_FULL_BINARIES} copy_full_data
	${GO_INSTALL} ${GO_DOCKER_FULL_BIN_CMDS}
	cp -v ${CRON_SCRIPTS} ${GOPATH}/bin || exit 11
	cp -v ${GIT_SCRIPTS} ${GOPATH}/bin || exit 12
	cd ${GOPATH}/bin || exit 13
	mkdir ${BINARY_PATH} || exit 14
	cp -v ${DOCKER_FULL_BINARIES} ${BINARY_PATH} || exit 15
	cp -v ${CRON_SCRIPTS} ${BINARY_PATH} || exit 16
	cp -v ${GIT_SCRIPTS} ${BINARY_PATH} || exit 17
	cp -v ${UTIL_SCRIPTS} ${BINARY_PATH} || exit 18

# Minimal install to image.
copy_minimal_data: util_scripts
	mkdir -p ${DATA_DIR} 2>/dev/null || echo "..."
	chmod 777 ${DATA_DIR} 2>/dev/null || echo "..."
ifneq "$(DATA_DIR)" ""
	rm -rf ${DATA_DIR}/* || exit 3
endif
	cp -R metrics/ ${DATA_DIR}/metrics/ || exit 4
	cp -R util_sql/ ${DATA_DIR}/util_sql/ || exit 5
	cp -R util_sh/ ${DATA_DIR}/util_sh/ || exit 6
	cp -R docs/ ${DATA_DIR}/docs/ || exit 7
	cp -R jsons/ ${DATA_DIR}/jsons/ || exit 8
	chmod 777 ${DATA_DIR}/jsons/ || exit 8
	cp -R scripts/ ${DATA_DIR}/scripts/ || exit 9
	cp devel/*.txt ${DATA_DIR}/ || exit 11
	cp projects.yaml skip_dates.yaml ${DATA_DIR}/ || exit 12

docker_minimal_install: ${DOCKER_MINIMAL_BINARIES} copy_minimal_data
	${GO_INSTALL} ${GO_DOCKER_MINIMAL_BIN_CMDS}
	cp -v ${GIT_SCRIPTS} ${GOPATH}/bin || exit 15
	cd ${GOPATH}/bin || exit 16
	mkdir ${BINARY_PATH} || exit 17
	cp -v ${DOCKER_MINIMAL_BINARIES} ${BINARY_PATH} || exit 18
	cp -v ${GIT_SCRIPTS} ${BINARY_PATH} || exit 19

links: util_scripts clean
	./util_sh/make_binary_links.sh ${BINARIES} || exit 1

# Clean

strip: ${BINARIES}
	${STRIP} ${BINARIES}

clean:
	$(GO) clean -i ./...
	rm -f ${BINARIES}
