#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./xlean.env
RUN_TAG="${RUN_TAG:-}"; RUN_TAG="${RUN_TAG//-/_}"
BLOCK_START="${BLOCK_START_OVERRIDE:-$BLOCK_START}"; BLOCK_END="${BLOCK_END_OVERRIDE:-$BLOCK_END}"
COMPARE_EXCLUDE_BLOCKS="${COMPARE_EXCLUDE_OVERRIDE:-${COMPARE_EXCLUDE_BLOCKS:-}}"
ADB="${CHAIN_SLUG}${RUN_TAG:-}_explorer_api"
HDB="${CHAIN_SLUG}${RUN_TAG:-}_harvester"
TABLES="explorer_block explorer_extrinsic explorer_event explorer_log"
q() { docker --context "$DOCKER_CONTEXT" exec "$PREFIX-mysql-$1" mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "$2" 2>/dev/null; }
fingerprint() {
  local variant="$1" db="$2" table="$3" cols
  cols=$(q "$variant" "SET SESSION group_concat_max_len=1048576; SELECT GROUP_CONCAT(CONCAT('COALESCE(CAST(\`',column_name,'\` AS CHAR),''<null>'')') ORDER BY ordinal_position SEPARATOR ',') FROM information_schema.COLUMNS WHERE table_schema='$db' AND table_name='$table'")
  q "$variant" "SELECT COUNT(*), BIT_XOR(CAST(CONV(LEFT(MD5(CONCAT_WS('#',$cols)),16),16,10) AS UNSIGNED)) FROM \`$db\`.\`$table\` WHERE $4"
}
upto=$(q base "SELECT LEAST(COALESCE((SELECT MAX(number) FROM \`$ADB\`.explorer_block),0),$BLOCK_END)")
upto_lean=$(q lean "SELECT COALESCE((SELECT MAX(number) FROM \`$ADB\`.explorer_block),0)")
upto=$(( upto < upto_lean ? upto : upto_lean ))
[ "$upto" -ge "$BLOCK_START" ] || { echo "no explorer data in window yet (upto=$upto)"; exit 2; }
echo "== compare explorer_* for #$BLOCK_START..#$upto excluding [${COMPARE_EXCLUDE_BLOCKS:-}]"
fail=0
for t in $TABLES; do
  col=block_number; [ "$t" = explorer_block ] && col=number
  w="$col BETWEEN $BLOCK_START AND $upto AND $col NOT IN (${COMPARE_EXCLUDE_BLOCKS:-0})"
  b=$(fingerprint base "$ADB" "$t" "$w")
  l=$(fingerprint lean "$ADB" "$t" "$w")
  s=SAME; [ "$b" = "$l" ] || { s=DIFF; fail=1; }
  printf '%-20s %-4s base=[%s] lean=[%s]\n' "$t" "$s" "$b" "$l"
done
b=$(fingerprint base "$HDB" codec_event_index_account "block_number BETWEEN $BLOCK_START AND $upto")
l=$(fingerprint lean "$HDB" codec_event_index_account "block_number BETWEEN $BLOCK_START AND $upto")
s=SAME; [ "$b" = "$l" ] || { s=DIFF; fail=1; }
printf '%-20s %-4s base=[%s] lean=[%s]\n' event_index_account "$s" "$b" "$l"
echo "== lml tx-counter SQL"
for sql in \
  "SELECT COUNT(*) FROM explorer_event WHERE event_module='Nfts' AND event_name='Issued' AND block_number<=$upto" \
  "SELECT COUNT(*) FROM explorer_event WHERE event_module='Balances' AND event_name='Transfer' AND block_number<=$upto" \
  "SELECT COUNT(*) FROM explorer_event WHERE event_name='Transferred' AND block_number<=$upto"; do
  b=$(q base "USE \`$ADB\`; $sql"); l=$(q lean "USE \`$ADB\`; $sql")
  s=SAME; [ "$b" = "$l" ] || { s=DIFF; fail=1; }
  printf '%-4s base=%s lean=%s  %s\n' "$s" "$b" "$l" "$sql"
done
exit $fail
