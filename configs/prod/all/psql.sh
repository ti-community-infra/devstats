#!/bin/bash
# MERGE_MODE=1 (use merge DBs mode instead of generating data via 'gha2db')
function finish {
    sync_unlock.sh
}

if [ -z "$TRAP" ]
then
  sync_lock.sh || exit -1
  trap finish EXIT
  export TRAP=1
fi

set -o pipefail
> errors.txt
> run.log

GHA2DB_PROJECT=all PG_DB=allprj GHA2DB_LOCAL=1 GHA2DB_MGETC=y structure 2>>errors.txt | tee -a run.log || exit 1
./devel/db.sh psql allprj -c "create extension if not exists pgcrypto" || exit 2
if [ -z "$MERGE_MODE" ]
then
  exclude="pingcap/pd-web,pingcap/ticdc-lib,pingcap/tidb-ansible,pingcap/tidb-helper,pingcap/tidb-lightning,pingcap/tikv-client-lib-java,pingcap/etcdv3-gateway,pingcap/tso,pingcap/mysqlrelay,pingcap/tidb-lmdb,pingcap/sqllogictest"
  args="pingcap,tikv,chaos-mesh"
  GHA2DB_EXCLUDE_REPOS=$exclude GHA2DB_PROJECT=all PG_DB=allprj GHA2DB_LOCAL=1 gha2db 2015-09-06 0 today now "$args" 2>>errors.txt | tee -a run.log || exit 3
else
  GHA2DB_INPUT_DBS="tidb,tikv,chaosmesh" GHA2DB_OUTPUT_DB="allprj" merge_dbs || exit 2
fi

GHA2DB_PROJECT=all PG_DB=allprj GHA2DB_LOCAL=1 GHA2DB_MGETC=y GHA2DB_SKIPTABLE=1 GHA2DB_INDEX=1 structure 2>>errors.txt | tee -a run.log || exit 3
GHA2DB_PROJECT=all PG_DB=allprj ./shared/setup_repo_groups.sh 2>>errors.txt | tee -a run.log || exit 4
GHA2DB_PROJECT=all PG_DB=allprj ./shared/setup_scripts.sh 2>>errors.txt | tee -a run.log || exit 5
GHA2DB_PROJECT=all PG_DB=allprj ./shared/import_affs.sh 2>>errors.txt | tee -a run.log || exit 6
GHA2DB_PROJECT=all PG_DB=allprj ./shared/get_repos.sh 2>>errors.txt | tee -a run.log || exit 7
GHA2DB_PROJECT=all PG_DB=allprj GHA2DB_LOCAL=1 GHA2DB_EXCLUDE_VARS="projects_health_partial_html" vars || exit 8

./devel/ro_user_grants.sh allprj || exit 10
./devel/psql_user_grants.sh devstats_team allprj || exit 11
