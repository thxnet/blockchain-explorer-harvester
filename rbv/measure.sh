#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./xlean.env
RUN_TAG="${RUN_TAG:-}"; RUN_TAG="${RUN_TAG//-/_}"
BLOCK_START="${BLOCK_START_OVERRIDE:-$BLOCK_START}"; BLOCK_END="${BLOCK_END_OVERRIDE:-$BLOCK_END}"
VARIANT="${1:?usage: measure.sh base|lean}"
MYSQL="$PREFIX-mysql-$VARIANT"
HDB="${CHAIN_SLUG}${RUN_TAG:-}_harvester"
ADB="${CHAIN_SLUG}${RUN_TAG:-}_explorer_api"
q() { docker --context "$DOCKER_CONTEXT" exec "$MYSQL" mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -t -e "$1" 2>/dev/null; }
echo "== $VARIANT $(date -u +%FT%TZ)"
q "SELECT \`key\`, \`value\` FROM \`$HDB\`.harvester_status WHERE \`key\` LIKE 'PROCESS_%' OR \`key\` LIKE 'EVENT_INDEX%' ORDER BY \`key\`;"
q "SELECT (SELECT MIN(number) FROM \`$ADB\`.explorer_block) AS explorer_min, (SELECT MAX(number) FROM \`$ADB\`.explorer_block) AS explorer_max, (SELECT COUNT(*) FROM \`$ADB\`.explorer_block) AS explorer_blocks;"
q "ANALYZE TABLE \`$HDB\`.node_block_extrinsic, \`$HDB\`.codec_block_extrinsic, \`$HDB\`.codec_block_event, \`$HDB\`.codec_block_storage, \`$HDB\`.node_block_storage, \`$ADB\`.explorer_extrinsic, \`$ADB\`.explorer_event;" >/dev/null
q "SELECT table_schema AS db, table_name, table_rows AS rows_est, ROUND(data_length/1048576,1) AS data_mb, ROUND(index_length/1048576,1) AS idx_mb FROM information_schema.TABLES WHERE table_schema IN ('$HDB','$ADB') AND (data_length+index_length) > 1048576 ORDER BY (data_length+index_length) DESC;"
q "SELECT table_schema AS db, ROUND(SUM(data_length+index_length)/1048576,1) AS total_mb FROM information_schema.TABLES WHERE table_schema IN ('$HDB','$ADB') GROUP BY table_schema;"
docker --context "$DOCKER_CONTEXT" exec "$MYSQL" sh -c "du -sm /var/lib/mysql/$HDB /var/lib/mysql/$ADB; du -cm /var/lib/mysql/binlog.0* | tail -1"
echo "== integrity"
q "SET SESSION cte_max_recursion_depth=100000000; SELECT COUNT(*) AS explorer_gaps, GROUP_CONCAT(n ORDER BY n) AS missing_blocks FROM (WITH RECURSIVE s(n) AS (SELECT $BLOCK_START UNION ALL SELECT n+1 FROM s WHERE n < (SELECT MAX(number) FROM \`$ADB\`.explorer_block)) SELECT n FROM s LEFT JOIN \`$ADB\`.explorer_block b ON b.number=s.n WHERE b.number IS NULL) g;"
q "SELECT COUNT(*) AS partial_blocks, GROUP_CONCAT(h.block_number) AS blocks FROM \`$HDB\`.node_block_header h LEFT JOIN (SELECT block_number, COUNT(*) c FROM \`$HDB\`.node_block_extrinsic GROUP BY block_number) e ON e.block_number=h.block_number WHERE e.c IS NOT NULL AND e.c <> h.count_extrinsics;"
