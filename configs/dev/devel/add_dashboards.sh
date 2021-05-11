#!/bin/bash
if [ -z "$FROM_PROJ" ]
then
  echo "$0: you need to set FROM_PROJ=projname $*"
  exit 2
fi

# TODO: Configure the mapping of project name through file
getFullname() 
{
  fullname="$1"

  if [ "$1" = "pingcap" ]
  then
    fullname="PingCAP"
  fi
  if [ "$1" = "tikv" ]
  then
    fullname="TiKV"
  fi
  if [ "$1" = "chaosmesh" ]
  then
    fullname="ChaosMesh"
  fi

  echo $fullname
}

from_proj=${FROM_PROJ}
from_fullname=`getFullname ${from_proj}`

for to_proj in `cat ./devel/all_test_projects.txt`
do
  if [ $from_proj = $to_proj ]
  then
    continue
  fi
  to_fullname=`getFullname ${to_proj}`

  echo "Copy dashboard config file from project $from_fullname to project $to_fullname"
  cp ./grafana/dashboards/${from_proj}/*.json "grafana/dashboards/${to_proj}/"

  FROM="${from_proj}" TO="${to_proj}" FILES="./grafana/dashboards/${to_proj}/*.json" MODE=ss0 ./devel/mass_replace.sh
  FROM="${from_fullname}" TO="${to_fullname}" FILES="./grafana/dashboards/${to_proj}/*.json" MODE=ss0 ./devel/mass_replace.sh
done
