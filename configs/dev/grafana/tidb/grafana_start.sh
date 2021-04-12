#!/bin/bash
cd /usr/share/grafana.tidb
grafana-server -config /etc/grafana.tidb/grafana.ini cfg:default.paths.data=/var/lib/grafana.tidb 1>/var/log/grafana.tidb.log 2>&1
