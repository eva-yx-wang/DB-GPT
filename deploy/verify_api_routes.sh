#!/usr/bin/env bash
# 验证 DB-GPT Web UI 功能对应的 API 路由（学习计划 api-and-config 检验脚本）
set -euo pipefail

BASE="${DBGPT_BASE_URL:-http://localhost:5670}"
PASS=0
FAIL=0

check() {
    local name="$1" method="$2" path="$3" body="${4:-}"
    local code
    local url="${BASE}${path}"
    if [[ "$method" == "GET" ]]; then
        code=$(curl -s -o /dev/null -w "%{http_code}" "${url}")
    else
        local payload="{}"
        [[ -n "$body" ]] && payload="$body"
        code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${url}" \
            -H "Content-Type: application/json" -d "${payload}")
    fi
    if [[ "$code" == "200" || "$code" == "201" ]]; then
        echo "[OK]   $name ($method $path) -> $code"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name ($method $path) -> $code"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== DB-GPT API Route Verification ==="
echo "Base URL: $BASE"
echo ""

# /api/v1 应用层
check "ReAct Agent 静态页" GET "/"
check "Skills 列表" GET "/api/v1/skills/list"
check "应用列表" GET "/api/v1/app/list"
check "对话历史" GET "/api/v1/chat/dialogue/list?user_name=dbgpt"

# /api/v2 serve 层
check "模型类型" GET "/api/v2/serve/model/model-types"
check "数据源" GET "/api/v2/serve/datasources"
check "AWEL Flow" GET "/api/v2/serve/awel/flows"
check "MCP 连接器" GET "/api/v2/serve/connectors/"
check "定时任务" GET "/api/v2/serve/scheduled-tasks/"

# Knowledge 路由（dbgpt-app/knowledge/api.py，无 /api 前缀）
check "知识库空间" POST "/knowledge/space/list"

# Prompt 路由（注册前缀 /prompt）
check "Prompt 模板" POST "/prompt/query_page?page=1&page_size=5" '{"sys_code":"dbgpt"}'

echo ""
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
