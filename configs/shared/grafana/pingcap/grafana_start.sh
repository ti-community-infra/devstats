#!/bin/bash
cd /usr/share/grafana.pingcap
grafana-server -config /etc/grafana.pingcap/grafana.ini cfg:default.paths.data=/var/lib/grafana.pingcap 1>/var/log/grafana.pingcap.log 2>&1
