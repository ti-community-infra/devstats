#!/bin/bash
# 
# ONLY=1   - only process
# NOSORT=1 - skip sorting JSONs received from Grafana DB dump
if [ -z "${LIST_FN_PREFIX}" ]
then
  LIST_FN_PREFIX="./devel/all_"
fi

all=`cat "${LIST_FN_PREFIX}test_projects.txt"`
mkdir sqlite 1>/dev/null 2>/dev/null
touch sqlite/touch

if [ -z "${ONLY}" ]
then
  # Hanlde all project that specified in all_test_project.txt file.
  for proj in $all
  do
    db=$proj
    echo "Project: $proj, GrafanaDB: $db"

    rm -f sqlite/*.json 2>/dev/null
    touch sqlite/touch
    sqlitedb "./sqlite/grafana.$proj.db" || exit 2

    # Sort the keys of JSON files to reduce code changes.
    rm -f grafana/dashboards/$proj/*.json || exit 4
    if [ -z "${NOSORT}" ]
    then
      for f in sqlite/*.json
      do
        ./util_sh/sort_json.sh "${f}" || exit 5
      done
    fi

    # Copy the dashboard config file to the Grafana config folder.
    mv sqlite/*.json grafana/dashboards/$proj/ || exit 6
  done
else
  # Only handle one project.
  proj=$ONLY
  db=$proj
  echo "project: $proj, GrafanaDB: $db"

  rm -f sqlite/*.json 2>/dev/null
  touch sqlite/touch

  sqlitedb "./sqlite/grafana.$proj.db" || exit 2

  # Sort the keys of JSON files to reduce code changes.
  rm -f grafana/dashboards/$proj/*.json || exit 4
  if [ -z "${NOSORT}" ]
  then
    for f in sqlite/*.json
    do
      ./util_sh/sort_json.sh "${f}" || exit 5
    done
  fi

  # Copy the dashboard config file to the Grafana config folder.
  mv sqlite/*.json grafana/dashboards/$proj/ || exit 6
fi

echo 'OK'
