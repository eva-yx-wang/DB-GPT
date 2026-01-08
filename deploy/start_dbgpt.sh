#!/bin/bash
# DB-GPT 启动脚本（简化版）
# 依赖已安装，仅进行环境检查和启动服务

# 激活 conda 环境
source ~/.bashrc
conda deactivate 2>/dev/null || true
conda activate dbgpt

# 启用 devtoolset-7（如果已安装）
if [ -f /opt/rh/devtoolset-7/enable ]; then
    source /opt/rh/devtoolset-7/enable
fi

# 切换到项目目录
cd /home/datagroup/projects/DB-GPT

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

# 启动服务
echo "正在启动 DB-GPT 服务..."
echo "配置文件: configs/dbgpt-proxy-tongyi.toml"
echo ""

# 使用 uv run 启动服务
if "$VENV_PYTHON" -c "import dbgpt.cli.cli_scripts" 2>/dev/null; then
    uv run dbgpt start webserver --config configs/dbgpt-proxy-tongyi.toml
else
    echo "警告: dbgpt CLI 不可用，使用 Python 脚本方式运行..."
    uv run python packages/dbgpt-app/src/dbgpt_app/dbgpt_server.py --config configs/dbgpt-proxy-tongyi.toml
fi
