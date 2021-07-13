#!/bin/bash
cd /usr/share/grafana.ob
grafana-server -config /etc/grafana.ob/grafana.ini cfg:default.paths.data=/var/lib/grafana.ob 1>/var/log/grafana.ob.log 2>&1
