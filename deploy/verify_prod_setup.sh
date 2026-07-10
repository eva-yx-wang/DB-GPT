#!/usr/bin/env bash
# 生产形态部署验证脚本（Docker Compose + MySQL）
# 用法:
#   export MYSQL_PASSWORD=your_password
#   export DASHSCOPE_API_KEY=your_key
#   ./deploy/verify_prod_setup.sh check    # 检查前置条件
#   ./deploy/verify_prod_setup.sh compose  # Docker Compose 启动（需 Docker）
#   ./deploy/verify_prod_setup.sh mysql    # 源码模式 + MySQL 配置启动
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${DBGPT_CONFIG:-configs/dbgpt-proxy-tongyi-mysql.toml}"

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

check_prereqs() {
    log "检查生产部署前置条件..."
    local ok=true

    if command -v docker >/dev/null 2>&1; then
        log "Docker: $(docker --version)"
        docker compose version 2>/dev/null && log "Docker Compose: OK" || warn "docker compose 不可用"
    else
        warn "Docker 未安装 — 可使用 mysql 子命令以源码 + 本地 MySQL 模式验证"
    fi

    [[ -n "${DASHSCOPE_API_KEY:-}" ]] && log "DASHSCOPE_API_KEY: 已设置" || warn "DASHSCOPE_API_KEY 未设置"
    [[ -f "${PROJECT_DIR}/${CONFIG}" ]] && log "生产配置: ${CONFIG}" || { warn "配置不存在: ${CONFIG}"; ok=false; }

    if [[ -n "${MYSQL_PASSWORD:-}" ]]; then
        if mysql -h"${MYSQL_HOST:-127.0.0.1}" -P"${MYSQL_PORT:-3306}" \
            -u"${MYSQL_USER:-root}" -p"${MYSQL_PASSWORD}" \
            -e "SELECT 1" >/dev/null 2>&1; then
            log "MySQL 连接: OK"
        else
            warn "MySQL 连接失败，请检查 MYSQL_HOST/PORT/USER/PASSWORD"
        fi
    else
        warn "MYSQL_PASSWORD 未设置 — Docker Compose 默认密码为 aa123456"
    fi

    $ok
}

compose_up() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "错误: 需要 Docker 才能运行 compose 子命令" >&2
        exit 1
    fi
    cd "${PROJECT_DIR}"
    log "启动 Docker Compose (MySQL + webserver)..."
    SILICONFLOW_API_KEY="${SILICONFLOW_API_KEY:-}" docker compose up -d
    log "等待服务就绪..."
    for i in $(seq 1 30); do
        if curl -sf http://localhost:5670/ >/dev/null 2>&1; then
            log "Web UI 可访问: http://localhost:5670"
            return 0
        fi
        sleep 3
    done
    warn "超时：请检查 docker logs db-gpt-webserver-1"
    return 1
}

mysql_mode() {
    cd "${PROJECT_DIR}"
    export DBGPT_CONFIG="${CONFIG}"
    export MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
    export MYSQL_PORT="${MYSQL_PORT:-3306}"
    export MYSQL_DATABASE="${MYSQL_DATABASE:-dbgpt}"
    export MYSQL_USER="${MYSQL_USER:-root}"

    if [[ -z "${MYSQL_PASSWORD:-}" ]]; then
        echo "错误: 请设置 MYSQL_PASSWORD" >&2
        exit 1
    fi

    # 初始化 schema（若数据库不存在）
    if ! mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
        -e "USE ${MYSQL_DATABASE}" 2>/dev/null; then
        log "创建数据库 ${MYSQL_DATABASE} 并导入 schema..."
        mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
            -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE} DEFAULT CHARSET utf8mb4;"
        mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
            "${MYSQL_DATABASE}" < "${PROJECT_DIR}/assets/schema/dbgpt.sql"
    fi

    log "以 MySQL 配置启动 DB-GPT..."
    ./deploy/dbgpt.sh stop 2>/dev/null || true
    DBGPT_CONFIG="${CONFIG}" ./deploy/dbgpt.sh start
    sleep 15
    curl -sf http://localhost:5670/ >/dev/null && log "生产形态验证成功: http://localhost:5670" \
        || warn "服务未响应，请查看 logs/webserver_uvicorn.log"
}

case "${1:-check}" in
    check)   check_prereqs ;;
    compose) compose_up ;;
    mysql)   mysql_mode ;;
    *)       echo "用法: $0 {check|compose|mysql}"; exit 1 ;;
esac
