#!/usr/bin/env bash
# DB-GPT 启停一体化脚本
# 基于官方源码部署文档: https://docs.dbgpt.cn/docs/getting-started/deploy/source-code/
#
# 用法:
#   ./deploy/dbgpt.sh start              # 后台启动 (官方 --daemon 模式)
#   ./deploy/dbgpt.sh start --foreground # 前台启动 (调试用)
#   ./deploy/dbgpt.sh stop               # 停止服务
#   ./deploy/dbgpt.sh status             # 查看状态
#   ./deploy/dbgpt.sh restart            # 重启
#   ./deploy/dbgpt.sh logs               # 跟踪服务日志
#
# 注意: 本服务器资源有限，install / check 命令已禁用。
#
# 环境变量:
#   DBGPT_CONFIG      配置文件路径 (默认: configs/dbgpt-proxy-openai.toml)
#   DBGPT_UV_EXTRAS   uv sync 可选依赖组 (空格分隔)
#   DBGPT_CONV_LOG_DIR 每对话独立日志目录 (默认: deploy/)
#   DBGPT_LOG_DIR     服务日志目录 (默认: logs/)
#   DBGPT_PORT        Web 端口 (默认从配置文件读取, 回退 5670)
#   OPENAI_API_KEY    OpenAI API Key (使用 openai 配置时需要)
#   DASHSCOPE_API_KEY 通义 API Key (使用 tongyi 配置时需要)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DBGPT_CONFIG="${DBGPT_CONFIG:-configs/dbgpt-proxy-openai.toml}"
DBGPT_UV_EXTRAS="${DBGPT_UV_EXTRAS:-base proxy_openai proxy_tongyi rag storage_chromadb dbgpts}"
DBGPT_CONV_LOG_DIR="${DBGPT_CONV_LOG_DIR:-${PROJECT_DIR}/deploy}"
DBGPT_LOG_DIR="${DBGPT_LOG_DIR:-${PROJECT_DIR}/logs}"
WEBSERVER_LOG="${DBGPT_LOG_DIR}/webserver_uvicorn.log"

log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

cd_project() {
    cd "${PROJECT_DIR}" || {
        log_error "无法进入项目目录: ${PROJECT_DIR}"
        exit 1
    }
}

resolve_config_path() {
    if [[ "${DBGPT_CONFIG}" = /* ]]; then
        echo "${DBGPT_CONFIG}"
    else
        echo "${PROJECT_DIR}/${DBGPT_CONFIG}"
    fi
}

get_web_port() {
    if [[ -n "${DBGPT_PORT:-}" ]]; then
        echo "${DBGPT_PORT}"
        return
    fi
    local config
    config="$(resolve_config_path)"
    local port=""
    if [[ -f "${config}" ]]; then
        port="$(awk -F= '/^\[service\.web\]/ {in_web=1; next} /^\[/ {in_web=0} in_web && /^[[:space:]]*port[[:space:]]*=/ {gsub(/[^0-9]/,"",$2); print $2; exit}' "${config}")"
    fi
    echo "${port:-5670}"
}

get_web_host() {
    if [[ -n "${DBGPT_HOST:-}" ]]; then
        echo "${DBGPT_HOST}"
        return
    fi
    local config
    config="$(resolve_config_path)"
    local host=""
    if [[ -f "${config}" ]]; then
        host="$(awk -F= '/^\[service\.web\]/ {in_web=1; next} /^\[/ {in_web=0} in_web && /^[[:space:]]*host[[:space:]]*=/ {gsub(/^[[:space:]]+|[[:space:]]+$|"/,"",$2); print $2; exit}' "${config}")"
    fi
    echo "${host:-0.0.0.0}"
}

get_web_url() {
    local host port
    host="$(get_web_host)"
    port="$(get_web_port)"
    case "${host}" in
        0.0.0.0|""|*:*)
            host="localhost"
            ;;
    esac
    echo "http://${host}:${port}"
}

print_web_url() {
    local url
    url="$(get_web_url)"
    echo ""
    echo "========================================"
    echo "  Web UI: ${url}"
    echo "========================================"
    echo ""
}

is_port_listening() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | grep -q ":${port} "
        return $?
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | grep -q ":${port} "
        return $?
    fi
    return 1
}

find_webserver_pids() {
    pgrep -f "dbgpt.*start webserver" 2>/dev/null || true
}

check_uv() {
    if ! command -v uv >/dev/null 2>&1; then
        log_error "未找到 uv。请按官方文档安装: curl -LsSf https://astral.sh/uv/install.sh | sh"
        return 1
    fi
    log_info "uv: $(uv --version)"
    return 0
}

check_venv() {
    if [[ ! -x "${PROJECT_DIR}/.venv/bin/python" ]]; then
        log_error ".venv 不存在。请先运行: $0 install"
        return 1
    fi
    log_info "Python: $("${PROJECT_DIR}/.venv/bin/python" --version 2>&1)"
    return 0
}

check_config_file() {
    local config
    config="$(resolve_config_path)"
    if [[ ! -f "${config}" ]]; then
        log_error "配置文件不存在: ${config}"
        return 1
    fi
    log_info "配置文件: ${config}"
    return 0
}

check_core_deps() {
    local py="${PROJECT_DIR}/.venv/bin/python"
    if ! "${py}" -c "import dbgpt, dbgpt_app, fastapi" 2>/dev/null; then
        log_error "核心依赖缺失。请运行: $0 install"
        return 1
    fi
    log_info "核心 Python 依赖正常"
    return 0
}

check_dbgpt_cli() {
    cd_project
    if run_dbgpt --help >/dev/null 2>&1; then
        log_info "dbgpt CLI 可用"
        return 0
    fi
    log_error "dbgpt CLI 不可用。请运行: $0 install"
    return 1
}

check_api_key_hint() {
    local config
    config="$(resolve_config_path)"
    if grep -q "proxy/openai\|OPENAI_API_KEY" "${config}" 2>/dev/null; then
        if [[ -z "${OPENAI_API_KEY:-}" ]]; then
            log_warn "未设置 OPENAI_API_KEY，OpenAI 模型调用可能失败"
        else
            log_info "OPENAI_API_KEY 已设置"
        fi
    fi
    if grep -q "proxy/tongyi\|DASHSCOPE_API_KEY" "${config}" 2>/dev/null; then
        if [[ -z "${DASHSCOPE_API_KEY:-}" ]]; then
            log_warn "未设置 DASHSCOPE_API_KEY，通义模型调用可能失败"
        else
            log_info "DASHSCOPE_API_KEY 已设置"
        fi
    fi
    return 0
}

check_uv_lock() {
    if [[ -f "${PROJECT_DIR}/uv.lock" ]] && uv lock --check >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

deny_install_check() {
    log_error "此服务器内存资源不足，已禁用 install / check 命令。"
    log_error "请在其他机器完成 uv sync 安装后，将 .venv 同步到本机，再使用 start / stop / status。"
    exit 1
}

run_dbgpt() {
    cd_project
    if [[ -x "${PROJECT_DIR}/.venv/bin/dbgpt" ]]; then
        "${PROJECT_DIR}/.venv/bin/dbgpt" "$@"
        return $?
    fi
    log_error "无法运行 dbgpt 命令 (.venv/bin/dbgpt 不存在)"
    return 1
}

run_start_preflight() {
    check_config_file || return 1
    if [[ ! -x "${PROJECT_DIR}/.venv/bin/dbgpt" ]]; then
        log_error ".venv/bin/dbgpt 不存在，请先在资源充足的机器上完成依赖安装"
        return 1
    fi
    check_api_key_hint || true
    if [[ -f "${SCRIPT_DIR}/check_llm_api.sh" ]]; then
        if ! bash "${SCRIPT_DIR}/check_llm_api.sh"; then
            log_warn "LLM API 自检失败，chat/chat_flow 调用可能返回 [SERVER_ERROR]"
            log_warn "修复: 在 Windows 重启 cloudflared + LLM 代理，然后:"
            log_warn "  bash deploy/set_openai_api_base.sh <新隧道URL> --restart"
        fi
    fi
    return 0
}

setup_runtime_env() {
    if [[ -f "${HOME}/.bashrc" ]]; then
        # shellcheck disable=SC1090
        # 关闭 nounset：非交互 source .bashrc 时 /etc/bashrc 可能引用未定义的 PS1
        set +e
        set +u
        set -a
        source "${HOME}/.bashrc" 2>/dev/null
        set +a
        set -u
        set -e
    fi
    export DBGPT_CONV_LOG_DIR
    export DBGPT_LOG_DIR
    mkdir -p "${DBGPT_CONV_LOG_DIR}/chat_logs" "${DBGPT_LOG_DIR}"
}

build_uv_sync_args() {
    UV_SYNC_ARGS=(sync --all-packages)
    if check_uv_lock; then
        UV_SYNC_ARGS+=(--frozen)
    else
        log_warn "uv.lock 无效或缺失，将不使用 --frozen"
    fi
    local extra
    for extra in ${DBGPT_UV_EXTRAS}; do
        UV_SYNC_ARGS+=(--extra "${extra}")
    done
}

cmd_check() {
    deny_install_check
}

cmd_install() {
    deny_install_check
}

is_running() {
    local port
    port="$(get_web_port)"
    local pids
    pids="$(find_webserver_pids)"
    if [[ -n "${pids}" ]] || is_port_listening "${port}"; then
        return 0
    fi
    return 1
}

cmd_start() {
    local foreground=0
    if [[ "${1:-}" == "--foreground" || "${1:-}" == "-f" ]]; then
        foreground=1
    fi

    run_start_preflight || exit 1
    setup_runtime_env
    cd_project

    if is_running; then
        log_warn "DB-GPT 已在运行。请先执行: $0 stop"
        cmd_status
        exit 1
    fi

    local config
    config="$(resolve_config_path)"
    local port
    port="$(get_web_port)"

    if [[ "${foreground}" -eq 1 ]]; then
        log_info "前台启动 DB-GPT (Ctrl+C 停止)..."
        log_info "配置: ${config}"
        print_web_url
        run_dbgpt start webserver --config "${config}"
        exit $?
    fi

    log_info "后台启动 DB-GPT (官方 daemon 模式)..."
    log_info "配置: ${config}"
    log_info "端口: ${port}"
    log_info "日志: ${WEBSERVER_LOG}"

    run_dbgpt start webserver --config "${config}" --daemon

    sleep 2
    if is_running; then
        log_info "DB-GPT 已启动"
        print_web_url
        cmd_status
        log_info "查看日志: $0 logs"
        log_info "停止服务: $0 stop"
    else
        log_error "启动可能失败，请查看日志: ${WEBSERVER_LOG}"
        exit 1
    fi
}

cmd_stop() {
    cd_project
    if ! is_running; then
        log_info "DB-GPT 未在运行"
        rm -f "${SCRIPT_DIR}/dbgpt.pid"
        return 0
    fi

    log_info "停止 DB-GPT 服务..."
    if run_dbgpt stop webserver 2>/dev/null; then
        :
    else
        log_warn "dbgpt stop 未找到进程，尝试按端口清理..."
        local pids
        pids="$(find_webserver_pids)"
        if [[ -n "${pids}" ]]; then
            echo "${pids}" | xargs -r kill -TERM 2>/dev/null || true
            sleep 3
            pids="$(find_webserver_pids)"
            if [[ -n "${pids}" ]]; then
                echo "${pids}" | xargs -r kill -KILL 2>/dev/null || true
            fi
        fi
    fi

    sleep 1
    rm -f "${SCRIPT_DIR}/dbgpt.pid"

    if is_running; then
        log_error "停止失败，请手动检查进程"
        cmd_status
        exit 1
    fi
    log_info "DB-GPT 已停止"
}

cmd_status() {
    local port
    port="$(get_web_port)"
    local pids
    pids="$(find_webserver_pids)"

    if [[ -n "${pids}" ]]; then
        echo "进程: 运行中 (PID: $(echo "${pids}" | tr '\n' ' '))"
    else
        echo "进程: 未检测到 webserver 进程"
    fi

    if is_port_listening "${port}"; then
        echo "端口: ${port} 正在监听"
        echo "Web UI: $(get_web_url)"
    else
        echo "端口: ${port} 未监听"
    fi

    if [[ -f "${WEBSERVER_LOG}" ]]; then
        echo "日志: ${WEBSERVER_LOG}"
    fi

    if is_running; then
        return 0
    fi
    return 1
}

cmd_restart() {
    cmd_stop || true
    sleep 2
    cmd_start
}

cmd_logs() {
    setup_runtime_env
    if [[ ! -f "${WEBSERVER_LOG}" ]]; then
        log_warn "日志文件尚不存在: ${WEBSERVER_LOG}"
        log_info "服务启动后会写入该文件"
        exit 1
    fi
    tail -f "${WEBSERVER_LOG}"
}

usage() {
    cat <<EOF
DB-GPT 启停一体化脚本

用法: $0 <command> [options]

命令:
  start [--foreground]  启动服务 (默认后台 daemon 模式)
  stop                  停止服务
  status                查看运行状态
  restart               重启服务
  logs                  跟踪 webserver 日志

  check / install       已禁用 (本服务器资源不足，请在其他机器安装依赖)

环境变量:
  DBGPT_CONFIG          配置文件 (默认: configs/dbgpt-proxy-tongyi.toml)
  DBGPT_UV_EXTRAS       uv sync extras (默认含 proxy_tongyi)
  DBGPT_CONV_LOG_DIR    对话独立日志目录
  DBGPT_LOG_DIR         服务日志目录
  DBGPT_PORT            Web 端口 (默认从配置读取)
  DBGPT_HOST            Web 绑定地址 (默认从配置读取, 0.0.0.0 显示为 localhost)
  DASHSCOPE_API_KEY     通义 API Key

官方文档:
  https://docs.dbgpt.cn/docs/getting-started/deploy/source-code/

复杂环境 (CentOS7 / DuckDB 编译等) 可先运行:
  deploy/prepare_env_dbgpt.sh
EOF
}

main() {
    local action="${1:-}"
    shift || true

    case "${action}" in
        check)    cmd_check ;;
        install|deps|sync) cmd_install ;;
        start)    cmd_start "$@" ;;
        stop)     cmd_stop ;;
        status)   cmd_status ;;
        restart)  cmd_restart ;;
        logs|log) cmd_logs ;;
        help|-h|--help|"")
            usage
            [[ -z "${action}" ]] && exit 1
            ;;
        *)
            log_error "未知命令: ${action}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
