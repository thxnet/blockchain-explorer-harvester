#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./xlean.env
VARIANT="${1:?usage: measure.sh base|lean}"
MYSQL="$PREFIX-mysql-$VARIANT"
HDB="${CHAIN_SLUG}_harvester"
ADB="${CHAIN_SLUG}_explorer_api"
q() { docker --context "$DOCKER_CONTEXT" exec "$MYSQL" mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -t -e "$1" 2>/dev/null; }
echo "== $VARIANT $(date -u +%FT%TZ)"
q "SELECT \`key\`, \`value\` FROM \`$HDB\`.harvester_status WHERE \`key\` LIKE 'PROCESS_%' OR \`key\` LIKE 'EVENT_INDEX%' ORDER BY \`key\`;"
q "SELECT (SELECT MIN(number) FROM \`$ADB\`.explorer_block) AS explorer_min, (SELECT MAX(number) FROM \`$ADB\`.explorer_block) AS explorer_max, (SELECT COUNT(*) FROM \`$ADB\`.explorer_block) AS explorer_blocks;"
q "ANALYZE TABLE \`$HDB\`.node_block_extrinsic, \`$HDB\`.codec_block_extrinsic, \`$HDB\`.codec_block_event, \`$HDB\`.codec_block_storage, \`$HDB\`.node_block_storage, \`$ADB\`.explorer_extrinsic, \`$ADB\`.explorer_event;" >/dev/null
q "SELECT table_schema AS db, table_name, table_rows AS rows_est, ROUND(data_length/1048576,1) AS data_mb, ROUND(index_length/1048576,1) AS idx_mb FROM information_schema.TABLES WHERE table_schema IN ('$HDB','$ADB') AND (data_length+index_length) > 1048576 ORDER BY (data_length+index_length) DESC;"
q "SELECT table_schema AS db, ROUND(SUM(data_length+index_length)/1048576,1) AS total_mb FROM information_schema.TABLES WHERE table_schema IN ('$HDB','$ADB') GROUP BY table_schema;"
docker --context "$DOCKER_CONTEXT" exec "$MYSQL" sh -c "du -sm /var/lib/mysql/$HDB /var/lib/mysql/$ADB; du -cm /var/lib/mysql/binlog.0* | tail -1"
