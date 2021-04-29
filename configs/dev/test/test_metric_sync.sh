#!/bin/bash
#make || exit 1
#./devel/drop_ts_tables.sh test || exit 2

GHA2DB_PROJECT=tikv GHA2DB_SKIPPDB=1 GHA2DB_CMDDEBUG=1 GHA2DB_DEBUG=1 GHA2DB_RESETTSDB=1 GHA2DB_METRICS_YAML=test/data/test_metrics.yaml GHA2DB_TAGS_YAML=test/data/test_tags.yaml GHA2DB_COLUMNS_YAML=test/data/test_columns.yaml GHA2DB_LOCAL=1 PG_DB=tikv PG_USER=postgres gha2db_sync
