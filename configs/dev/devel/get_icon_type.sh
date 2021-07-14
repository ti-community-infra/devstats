#!/bin/bash
if [ -z "$1" ]
then
  echo "$0: requires project name parameter"
  exit 1
fi
declare -A icontypes
icontypes=(
  # Optional values: color / white
  ["tidb"]="color"
  ["tikv"]="color"
  ["chaosmesh"]="color"
  ["ob"]="color"
)
icontype=${icontypes[$1]}
if [ -z "$icontype" ]
then
  echo "$0: project $1 is not defined"
  exit 1
fi
echo $icontype
