#!/usr/bin/env bash
set -euo pipefail

# 停止 zanod、simplewallet 和 Node.js pool。Redis 容器继续保持运行。

RUN_DIR="/home/pool/.pool-run"

log(){
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

stop_pid(){
    local name="$1" pidfile="$2"
    if [[ ! -f "$pidfile" ]]; then
        log "$name 未发现 PID 文件，可能未运行。"
        return
    fi
    local pid
    pid=$(cat "$pidfile")
    if kill -0 "$pid" >/dev/null 2>&1; then
        log "停止 $name (PID $pid)..."
        kill "$pid" >/dev/null 2>&1 || true
        for i in {1..20}; do
            if kill -0 "$pid" >/dev/null 2>&1; then
                sleep 0.5
            else
                break
            end
        done
        if kill -0 "$pid" >/dev/null 2>&1; then
            log "$name 未在 10 秒内结束，执行强制杀进程"
            kill -9 "$pid" >/dev/null 2>&1 || true
        fi
    else
        log "$name 不在运行。"
    fi
    rm -f "$pidfile"
}

stop_pid "Node.js pool" "${RUN_DIR}/pool.pid"
stop_pid "simplewallet RPC" "${RUN_DIR}/simplewallet.pid"
stop_pid "zanod" "${RUN_DIR}/zanod.pid"

log "停止完成。如需同时停止 Redis，请运行：docker compose -f /home/lh/qssl/backend/docker-compose.yml stop redis"
