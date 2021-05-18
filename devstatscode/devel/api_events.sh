#!/bin/bash
if [ -z "$1" ]
then
  echo "$0: please specify project name as a 1st arg"
  exit 1
fi
if [ -z "$2" ]
then
  echo "$0: please specify timestamp from as a 2nd arg"
  exit 2
fi
if [ -z "$3" ]
then
  echo "$0: please specify timestamp to as a 3rd arg"
  exit 3
fi
if [ -z "$API_URL" ]
then
  export API_URL="http://127.0.0.1:8080/api/v1"
fi
if [ -z "$ORIGIN" ]
then
  export ORIGIN='https://teststats.cncf.io'
fi
project="${1}"
from="${2}"
to="${3}"
if [ -z "$DEBUG" ]
then
  curl -s -H "Origin: ${ORIGIN}" -H "Content-Type: application/json" "${API_URL}" -d"{\"api\":\"Events\",\"payload\":{\"project\":\"${project}\",\"from\":\"${from}\",\"to\":\"${to}\"}}" | jq
else
  echo curl -i -s -H "Origin: ${ORIGIN}" -H "Content-Type: application/json" "${API_URL}" -d"{\"api\":\"Events\",\"payload\":{\"project\":\"${project}\",\"from\":\"${from}\",\"to\":\"${to}\"}}"
  curl -i -s -H "Origin: ${ORIGIN}" -H "Content-Type: application/json" "${API_URL}" -d"{\"api\":\"Events\",\"payload\":{\"project\":\"${project}\",\"from\":\"${from}\",\"to\":\"${to}\"}}"
fi
