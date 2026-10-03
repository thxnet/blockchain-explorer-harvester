#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./xlean.env
VARIANT="${1:?usage: up.sh base|lean}"
D() { docker --context "$DOCKER_CONTEXT" "$@"; }
MYSQL="$PREFIX-mysql-$VARIANT"
API="$PREFIX-api-$VARIANT"
HARV="$PREFIX-harvester-$VARIANT"
HDB="${CHAIN_SLUG}_harvester"
ADB="${CHAIN_SLUG}_explorer_api"

D network inspect "$NETWORK" >/dev/null 2>&1 || D network create --subnet "$NETWORK_SUBNET" "$NETWORK" >/dev/null
D inspect "$PREFIX-redis" >/dev/null 2>&1 || D run -d --name "$PREFIX-redis" --network "$NETWORK" "$REDIS_IMAGE" >/dev/null

if ! D inspect "$MYSQL" >/dev/null 2>&1; then
  D run -d --name "$MYSQL" --network "$NETWORK" \
    -v "$MYSQL-data:/var/lib/mysql" \
    -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
    "$MYSQL_IMAGE" $MYSQL_ARGS >/dev/null
fi
until D exec "$MYSQL" mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e 'SELECT 1' >/dev/null 2>&1; do sleep 3; done
D exec "$MYSQL" mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$HDB\`; CREATE DATABASE IF NOT EXISTS \`$ADB\`;" 2>/dev/null
echo "[$VARIANT] mysql ready: $MYSQL"

if ! D inspect "$API" >/dev/null 2>&1; then
  D run -d --name "$API" --network "$NETWORK" \
    -e DB_USERNAME=root -e DB_PASSWORD="$MYSQL_ROOT_PASSWORD" -e DB_HOST="$MYSQL" -e DB_PORT=3306 \
    -e DB_NAME="$ADB" -e DB_HARVESTER_NAME="$HDB" \
    -e DOMAIN=localhost -e SERVER_ADDR=0.0.0.0 -e SERVER_PORT=8000 -e WEBSOCKET_URI=ws://0.0.0.0:8000 \
    -e BACKEND_CORS_ORIGINS='[]' -e BROADCAST_URI="redis://$PREFIX-redis:6379" \
    -e API_SQLA_URI="mysql+pymysql://root:$MYSQL_ROOT_PASSWORD@$MYSQL:3306/$ADB?charset=utf8mb4" \
    -e CHAIN_ID=polkadot -e SENTRY_PROJECT_NAME=explorer-api-v2 -e SENTRY_SERVER_NAME=polkadapt -e SENTRY_DSN= \
    -e BLOCK_LIMIT_COUNT=500000 \
    "$API_IMAGE" >/dev/null
fi
until D exec "$MYSQL" mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='$ADB' AND ROUTINE_NAME='etl_range'" 2>/dev/null | grep -q '^1$'; do sleep 3; done
echo "[$VARIANT] explorer_api schema + etl_range ready: $API"

if [ "$VARIANT" = lean ]; then
  IMAGE="$HARVESTER_LEAN_IMAGE"
  EXTRA=(-e PRUNE_INTERMEDIATE_ENABLED=1 -e PRUNE_KEEP_BLOCKS="$PRUNE_KEEP_BLOCKS" -e PRUNE_BATCH_BLOCKS="$PRUNE_BATCH_BLOCKS")
else
  IMAGE="$HARVESTER_BASE_IMAGE"
  EXTRA=()
fi
if ! D inspect "$HARV" >/dev/null 2>&1; then
  D run -d --name "$HARV" --network "$NETWORK" \
    -e DB_CONNECTION="mysql+pymysql://root:$MYSQL_ROOT_PASSWORD@$MYSQL:3306/$HDB?charset=utf8mb4" \
    -e DB_USERNAME=root \
    -e SUBSTRATE_RPC_URL="$SUBSTRATE_RPC_URL" -e NODE_TYPE=archive -e SUBSTRATE_SS58_FORMAT="$SUBSTRATE_SS58_FORMAT" \
    -e INSTALLED_ETL_DATABASES="$ADB" -e BLOCK_START="$BLOCK_START" -e BLOCK_END="$BLOCK_END" \
    ${EXTRA[@]+"${EXTRA[@]}"} \
    --entrypoint /usr/src/start.sh "$IMAGE" >/dev/null
fi
echo "[$VARIANT] harvester started: $HARV ($IMAGE)"
