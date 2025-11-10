#!/usr/bin/env bash
set -euo pipefail

# One-click starter for Redis (container), zanod, simplewallet RPC and the Node.js pool.
# 请使用 pool 用户运行：sudo -u pool -H bash scripts/start-all.sh

REPO_ROOT="/home/lh/home/pool"
ZANO_ROOT="/home/lh/home/zano"
DATA_DIR="/home/pool/zano-data"
WALLET_DIR="/home/pool/zano-wallet"
RUN_DIR="/home/pool/.pool-run"
NODE_BIN="/home/lh/.nvm/versions/node/v14.15.0/bin/node"
DOCKER_COMPOSE_FILE="/home/lh/qssl/backend/docker-compose.yml"

mkdir -p "${RUN_DIR}"

log(){
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

ensure_pid_dead(){
    local name="$1" pidfile="$2"
    if [[ -f "$pidfile" ]]; then
        local pid
        pid=$(cat "$pidfile")
        if kill -0 "$pid" >/dev/null 2>&1; then
            log "$name 已在运行 (PID $pid)，跳过。"
            return 1
        fi
        rm -f "$pidfile"
    fi
    return 0
}

start_redis(){
    log "启动 Redis 容器..."
    docker compose -f "$DOCKER_COMPOSE_FILE" up -d redis >/dev/null
}

start_zanod(){
    local pidfile="${RUN_DIR}/zanod.pid"
    if ! ensure_pid_dead "zanod" "$pidfile"; then
        return
    fi
    log "启动 zanod..."
    nohup "${ZANO_ROOT}/build/src/zanod" \
        --data-dir="${DATA_DIR}" \
        --log-dir="${DATA_DIR}/logs" \
        --rpc-bind-ip=0.0.0.0 --rpc-bind-port=11211 \
        --p2p-bind-ip=0.0.0.0 --p2p-bind-port=34444 \
        --hide-my-port \
        >> "${DATA_DIR}/zanod.stdout.log" 2>&1 &
    echo $! > "$pidfile"
}

start_wallet(){
    local pidfile="${RUN_DIR}/simplewallet.pid"
    if ! ensure_pid_dead "simplewallet RPC" "$pidfile"; then
        return
    fi
    log "启动 simplewallet RPC..."
    nohup "${ZANO_ROOT}/build/src/simplewallet" \
        --wallet-file "${WALLET_DIR}/pool_wallet" \
        --password "lh123456" \
        --daemon-address 127.0.0.1:11211 \
        --rpc-bind-ip 0.0.0.0 \
        --rpc-bind-port 39996 \
        --log-file "${WALLET_DIR}/simplewallet.log" \
        >> "${WALLET_DIR}/simplewallet.stdout.log" 2>&1 &
    echo $! > "$pidfile"
}

start_pool(){
    local pidfile="${RUN_DIR}/pool.pid"
    if ! ensure_pid_dead "Node.js pool" "$pidfile"; then
        return
    fi
    log "启动 Node.js pool..."
    cd "$REPO_ROOT"
    POOL_REDIS_HOST=127.0.0.1 \
    PATH="$(dirname "$NODE_BIN"):$PATH" \
    nohup "$NODE_BIN" init.js >> "${REPO_ROOT}/logs/pool.stdout.log" 2>&1 &
    echo $! > "$pidfile"
}

start_redis
start_zanod
start_wallet
start_pool

log "全部服务启动完毕。"
