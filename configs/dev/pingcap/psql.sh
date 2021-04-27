#!/bin/bash
set -o pipefail
function finish {
    sync_unlock.sh
}
if [ -z "$TRAP" ]
then
  sync_lock.sh || exit -1
  trap finish EXIT
  export TRAP=1
fi
> errors.txt
> run.log
GHA2DB_PROJECT=pingcap PG_DB=pingcap GHA2DB_LOCAL=1 structure 2>>errors.txt | tee -a run.log || exit 1
./devel/db.sh psql pingcap -c "create extension if not exists pgcrypto" || exit 1

# Notice: the project start time here is not real.
GHA2DB_PROJECT=pingcap PG_DB=pingcap GHA2DB_LOCAL=1 gha2db 2021-01-01 0 today now "pingcap/tidb,pingcap/dm,pingcap/br,pingcap/tidb-dashboard,pingcap/parser,pingap/ticdc,pingcap/go-ycsb,pingcap/docs-cn,pingcap/docs,pingcap/tidb-binlog,pingcap/blog,pingcap/dumpling,pingcap/tidb-operator,pingcap/tispark,pingcap/docs-tidb-operator,pingcap/docs-dm,pingcap/community,pingcap/kvproto,pingcap/tiup,pingcap/website-docs,pingcap/tidb-tools,pingcap/talent-plan,pingcap/awesome-database-learning,pingcap/failpoint,pingcap/tidb-ansible,pingcap/tidb-docker-compose,pingcap/presentations,pingcap/weekly" 2>>errors.txt | tee -a run.log || exit 2
GHA2DB_PROJECT=pingcap PG_DB=pingcap GHA2DB_LOCAL=1 GHA2DB_MGETC=y GHA2DB_SKIPTABLE=1 GHA2DB_INDEX=1 structure 2>>errors.txt | tee -a run.log || exit 3
GHA2DB_PROJECT=pingcap PG_DB=pingcap ./shared/setup_repo_groups.sh 2>>errors.txt | tee -a run.log || exit 4
GHA2DB_PROJECT=pingcap PG_DB=pingcap ./shared/import_affs.sh 2>>errors.txt | tee -a run.log || exit 5
GHA2DB_PROJECT=pingcap PG_DB=pingcap ./shared/setup_scripts.sh 2>>errors.txt | tee -a run.log || exit 6
GHA2DB_PROJECT=pingcap PG_DB=pingcap ./shared/get_repos.sh 2>>errors.txt | tee -a run.log || exit 7
GHA2DB_PROJECT=pingcap PG_DB=pingcap GHA2DB_LOCAL=1 vars || exit 8
./devel/ro_user_grants.sh pingcap || exit 9
./devel/psql_user_grants.sh devstats_team pingcap || exit 10
