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
GHA2DB_PROJECT=tremor PG_DB=tremor GHA2DB_LOCAL=1 structure 2>>errors.txt | tee -a run.log || exit 1
./devel/db.sh psql tremor -c "create extension if not exists pgcrypto" || exit 1
GHA2DB_PROJECT=tremor PG_DB=tremor GHA2DB_LOCAL=1 gha2db 2020-01-28 0 today now 'wayfair-tremor,tremor-rs' 2>>errors.txt | tee -a run.log || exit 2
GHA2DB_PROJECT=tremor PG_DB=tremor GHA2DB_LOCAL=1 GHA2DB_MGETC=y GHA2DB_SKIPTABLE=1 GHA2DB_INDEX=1 structure 2>>errors.txt | tee -a run.log || exit 3
GHA2DB_PROJECT=tremor PG_DB=tremor ./shared/setup_repo_groups.sh 2>>errors.txt | tee -a run.log || exit 4
GHA2DB_PROJECT=tremor PG_DB=tremor ./shared/import_affs.sh 2>>errors.txt | tee -a run.log || exit 5
GHA2DB_PROJECT=tremor PG_DB=tremor ./shared/setup_scripts.sh 2>>errors.txt | tee -a run.log || exit 6
GHA2DB_PROJECT=tremor PG_DB=tremor ./shared/get_repos.sh 2>>errors.txt | tee -a run.log || exit 7
GHA2DB_PROJECT=tremor PG_DB=tremor GHA2DB_LOCAL=1 vars || exit 8
./devel/ro_user_grants.sh tremor || exit 9
./devel/psql_user_grants.sh devstats_team tremor || exit 10
