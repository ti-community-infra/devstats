#!/bin/bash
# ARTWORK
# GET=1 (attempt to fetch Postgres database and Grafana database from the test server)
# AGET=1 (attempt to fetch 'All CNCF' Postgres database from the test server)
# INIT=1 (needs PG_PASS_RO, PG_PASS_TEAM, initialize from no postgres database state, creates postgres logs database and users)
# SKIPWWW=1 (skips Apache and SSL cert configuration, final result will be Grafana exposed on the server on its port (for example 3010) via HTTP)
# SKIPCERT=1 (skip certificate issue)
# SKIPVARS=1 (if set it will skip final Postgres vars regeneration)
# SKIPICONS=1 (if set it will skip updating all artworks)
# SKIPMAKE=1 (if set it will skip final make install call)
# CUSTGRAFPATH=1 (set this to use non-standard grafana instalation from ~/grafana.v5/)
# SETPASS=1 (should be set on a real first run to set main postgres password interactively, CANNOT be used without user interaction)
set -o pipefail
exec > >(tee run.log)
exec 2> >(tee errors.txt)
if [ -z "$PG_PASS" ]
then
  echo "$0: You need to set PG_PASS environment variable to run this script"
  exit 1
fi
if ( [ ! -z "$INIT" ] && ( [ -z "$PG_PASS_RO" ] || [ -z "$PG_PASS_TEAM" ] ) )
then
  echo "$0: You need to set PG_PASS_RO, PG_PASS_TEAM when using INIT"
  exit 1
fi

if [ ! -z "$CUSTGRAFPATH" ]
then
  GRAF_USRSHARE="$HOME/grafana.v5/usr.share.grafana"
  GRAF_VARLIB="$HOME/grafana.v5/var.lib.grafana"
  GRAF_ETC="$HOME/grafana.v5/etc.grafana"
fi

if [ -z "$GRAF_USRSHARE" ]
then
  GRAF_USRSHARE="/usr/share/grafana"
fi
if [ -z "$GRAF_VARLIB" ]
then
  GRAF_VARLIB="/var/lib/grafana"
fi
if [ -z "$GRAF_ETC" ]
then
  GRAF_ETC="/etc/grafana"
fi
export GRAF_USRSHARE
export GRAF_VARLIB
export GRAF_ETC

if [ ! -z "$ONLY" ]
then
  export ONLY
fi

host=`hostname`
function finish {
  sync_unlock.sh
  rm -f /tmp/deploy.wip 2>/dev/null
}
if [ -z "$TRAP" ]
then
  sync_lock.sh || exit -1
  trap finish EXIT
  export TRAP=1
  > /tmp/deploy.wip
fi

. ./devel/all_projs.sh || exit 1

if [ -z "$ONLYDB" ]
then
  host=`hostname`
  if [ $host = "teststats.cncf.io" ]
  then
    alldb=`cat ./devel/all_test_dbs.txt`
  else
    alldb=`cat ./devel/all_prod_dbs.txt`
  fi
else
  alldb=$ONLYDB
fi

LASTDB=""
for db in $alldb
do
  exists=`./devel/db.sh psql postgres -tAc "select 1 from pg_database where datname = '$db'"` || exit 100
  if [ ! "$exists" = "1" ]
  then
    LASTDB=$db
  fi
done
export LASTDB
echo "Last missing DB is $LASTDB"

if [ ! -z "$INIT" ]
then
  ./devel/init_database.sh || exit 2
fi

# OCI has no icon in cncf/artwork at all, so use "-" here
# Use GA="-" to skip GA (google analytics) code
# Use ICON="-" to skip project ICON
for proj in $all
do
  db=$proj
  if [ "$proj" = "tidb" ]; then
    # TODO: patch the tidb project icon.
    PROJ=tidb       PROJDB=tidb       PROJREPO="pingcap/tidb"          ORGNAME="PingCAP"    PORT=3001   ICON=tikv      GRAFSUFF=tidb      GA="-" ./devel/deploy_proj.sh || exit 101
  elif [ "$proj" = "tikv" ]; then
    PROJ=tikv       PROJDB=tikv       PROJREPO="tikv/tikv"             ORGNAME="TiKV"       PORT=3002   ICON=tikv      GRAFSUFF=tikv      GA="-" ./devel/deploy_proj.sh || exit 102
  elif [ "$proj" = "chaosmesh" ]; then
    PROJ=chaosmesh  PROJDB=chaosmesh  PROJREPO="chaos-mesh/chaos-mesh" ORGNAME="Chaos Mesh" PORT=3003   ICON=chaosmesh GRAFSUFF=chaosmesh GA="-" ./devel/deploy_proj.sh || exit 103
  else
    echo "Unknown project: $proj"
    exit 28
  fi
done

if [ -z "$SKIPCERT" ]
then
  export CERT=1
fi

if [ -z "$SKIPWWW" ]
then
  WWW=1 ./devel/create_www.sh || exit 37
fi
if [ -z "$SKIPVARS" ]
then
  ./devel/vars_all.sh || exit 38
fi

if [ -z "$SKIPICONS" ]
then
  ./devel/icons_all.sh || exit 47
fi
if [ -z "$SKIPMAKE" ]
then
  rm -f /tmp/deploy.wip 2>/dev/null
  make install || exit 48
fi

echo "$0: All deployments finished"
