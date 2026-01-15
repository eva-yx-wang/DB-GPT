#!/bin/bash
# DB-GPT 停止脚本
# 安全停止后台运行的 DB-GPT 服务

PROJECT_DIR="/home/datagroup/projects/DB-GPT"
PID_FILE="${PROJECT_DIR}/deploy/dbgpt.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "服务未运行，无需停止"
    exit 0
fi

PID=$(cat "$PID_FILE")
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "进程 $PID 不存在，清理 PID 文件"
    rm -f "$PID_FILE"
    exit 0
fi

echo "正在停止 DB-GPT 服务 (PID: $PID)..."

# 发送 SIGTERM 信号，优雅退出
kill -TERM "$PID" 2>/dev/null

# 等待进程退出（最多等待30秒）
for i in {1..30}; do
    if ! ps -p "$PID" > /dev/null 2>&1; then
        echo "✓ 服务已安全退出"
        rm -f "$PID_FILE"
        exit 0
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
        exit 0
    else
        echo "✗ 无法终止服务，请手动检查"
        exit 1
    fi
fi
