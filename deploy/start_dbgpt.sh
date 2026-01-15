#!/bin/bash
# DB-GPT 启动脚本（支持后台运行和安全退出）
# 依赖已安装，仅进行环境检查和启动服务
# 用法: ./start_dbgpt.sh [start|stop|status|restart]

# 配置变量
PROJECT_DIR="/home/datagroup/projects/DB-GPT"
PID_FILE="${PROJECT_DIR}/deploy/dbgpt.pid"
LOG_FILE="${PROJECT_DIR}/deploy/dbgpt.log"
CONFIG_FILE="configs/dbgpt-proxy-tongyi.toml"

# 获取命令参数，默认为 start
ACTION="${1:-start}"

# 函数：检查服务是否运行
check_status() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "✓ DB-GPT 服务正在运行 (PID: $PID)"
            return 0
        else
            echo "✗ DB-GPT 服务未运行（PID文件存在但进程不存在）"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "✗ DB-GPT 服务未运行"
        return 1
    fi
}

# 函数：停止服务
stop_service() {
    if [ ! -f "$PID_FILE" ]; then
        echo "服务未运行，无需停止"
        return 0
    fi

    PID=$(cat "$PID_FILE")
    if ! ps -p "$PID" > /dev/null 2>&1; then
        echo "进程 $PID 不存在，清理 PID 文件"
        rm -f "$PID_FILE"
        return 0
    fi

    echo "正在停止 DB-GPT 服务 (PID: $PID)..."

    # 发送 SIGTERM 信号，优雅退出
    kill -TERM "$PID" 2>/dev/null

    # 等待进程退出（最多等待30秒）
    for i in {1..30}; do
        if ! ps -p "$PID" > /dev/null 2>&1; then
            echo "✓ 服务已安全退出"
            rm -f "$PID_FILE"
            return 0
        fi
        sleep 1
    done

    # 如果30秒后仍未退出，强制杀死
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "警告: 服务未在30秒内退出，强制终止..."
        kill -KILL "$PID" 2>/dev/null
        sleep 1
        if ! ps -p "$PID" > /dev/null 2>&1; then
            echo "✓ 服务已强制终止"
            rm -f "$PID_FILE"
            return 0
        else
            echo "✗ 无法终止服务"
            return 1
        fi
    fi
}

# 函数：启动服务
start_service() {
    # 检查服务是否已在运行
    if check_status > /dev/null 2>&1; then
        echo "服务已在运行中，请先使用 'stop' 命令停止"
        return 1
    fi

    # 激活 conda 环境
    source ~/.bashrc
    conda deactivate 2>/dev/null || true
    conda activate dbgpt

    # 启用 devtoolset-7（如果已安装）
    if [ -f /opt/rh/devtoolset-7/enable ]; then
        source /opt/rh/devtoolset-7/enable
    fi

    # 切换到项目目录
    cd "$PROJECT_DIR" || {
        echo "错误: 无法切换到项目目录 $PROJECT_DIR"
        exit 1
    }

    # 检查 .venv 环境是否存在
    VENV_PYTHON=".venv/bin/python"
    if [ ! -f "$VENV_PYTHON" ]; then
        echo "错误: .venv 环境不存在，请先运行 prepare_env_dbgpt.sh 安装依赖"
        exit 1
    fi

    echo "使用 .venv 环境: $VENV_PYTHON"
    echo ""

    # 快速检查依赖（如果缺失则安装）
    echo "检查依赖状态..."
    if ! "$VENV_PYTHON" -c "import numpy, pandas, fastapi, dbgpt, dbgpt_app" 2>/dev/null; then
        echo "检测到依赖缺失，正在同步依赖..."
        uv sync --all-packages --frozen \
            --extra "base" \
            --extra "proxy_openai" \
            --extra "rag" \
            --extra "storage_chromadb" \
            --extra "dbgpts" || {
            echo "错误: 依赖同步失败"
            exit 1
        }
    else
        echo "✓ 核心依赖已安装"
    fi

    # 检查并安装 dashscope（日志显示缺失此模块）
    # 注意：必须安装到 .venv 环境，而不是 conda 环境
    if ! "$VENV_PYTHON" -c "import dashscope" 2>/dev/null; then
        echo "检测到缺失 dashscope 模块，正在安装到 .venv 环境..."
        "$VENV_PYTHON" -m pip install dashscope || {
            echo "错误: dashscope 安装失败"
            exit 1
        }
        echo "✓ dashscope 已安装到 .venv 环境"
    else
        echo "✓ dashscope 已安装"
    fi
    echo ""

    # 设置 PYTHONPATH
    export PYTHONPATH="${PYTHONPATH:+${PYTHONPATH}:}$(pwd)/packages/dbgpt-core/src:$(pwd)/packages/dbgpt-app/src:$(pwd)/packages:$(pwd)"

    # 启动服务（后台运行）
    echo "正在启动 DB-GPT 服务（后台模式）..."
    echo "配置文件: $CONFIG_FILE"
    echo "日志文件: $LOG_FILE"
    echo "PID 文件: $PID_FILE"
    echo ""

    # 确保日志目录存在
    mkdir -p "$(dirname "$LOG_FILE")"

    # 使用 nohup 在后台启动服务
    (
        cd "$PROJECT_DIR"
        if "$VENV_PYTHON" -c "import dbgpt.cli.cli_scripts" 2>/dev/null; then
            nohup uv run dbgpt start webserver --config "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 &
        else
            echo "警告: dbgpt CLI 不可用，使用 Python 脚本方式运行..."
            nohup uv run python packages/dbgpt-app/src/dbgpt_app/dbgpt_server.py --config "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 &
        fi
        echo $! > "$PID_FILE"
    )

    # 等待一下，检查进程是否成功启动
    sleep 2
    if check_status > /dev/null 2>&1; then
        PID=$(cat "$PID_FILE")
        echo "✓ DB-GPT 服务已成功启动（后台运行）"
        echo "  PID: $PID"
        echo "  查看日志: tail -f $LOG_FILE"
        echo "  停止服务: $0 stop"
        return 0
    else
        echo "✗ 服务启动失败，请查看日志: $LOG_FILE"
        rm -f "$PID_FILE"
        return 1
    fi
}

# 主逻辑
case "$ACTION" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    status)
        check_status
        ;;
    restart)
        stop_service
        sleep 2
        start_service
        ;;
    *)
        echo "用法: $0 {start|stop|status|restart}"
        echo ""
        echo "命令说明:"
        echo "  start   - 在后台启动 DB-GPT 服务"
        echo "  stop    - 安全停止 DB-GPT 服务"
        echo "  status  - 查看服务运行状态"
        echo "  restart - 重启服务"
        exit 1
        ;;
esac
