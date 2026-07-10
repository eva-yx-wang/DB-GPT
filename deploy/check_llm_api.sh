#!/usr/bin/env bash
# 检查 LLM API 是否可用（用于 chat_flow / chat 模式）
#
# 用法:
#   bash deploy/check_llm_api.sh
#   bash deploy/check_llm_api.sh --url https://xxx.trycloudflare.com/v1
#
set -euo pipefail

read_bashrc_var() {
  local key="$1"
  local line
  line="$(grep "^export ${key}=" "${HOME}/.bashrc" 2>/dev/null | tail -1 || true)"
  if [[ -z "${line}" ]]; then
    return 1
  fi
  # shellcheck disable=SC2086
  eval "${line#export }"
}

API_BASE="${OPENAI_API_BASE:-}"
API_KEY="${OPENAI_API_KEY:-}"
MODEL="${LLM_MODEL_NAME:-gpt-5.5}"

if [[ -f "${HOME}/.bashrc" ]]; then
  read_bashrc_var OPENAI_API_BASE || true
  API_BASE="${OPENAI_API_BASE:-${API_BASE}}"
  read_bashrc_var OPENAI_API_KEY || true
  API_KEY="${OPENAI_API_KEY:-${API_KEY}}"
  read_bashrc_var LLM_MODEL_NAME || true
  MODEL="${LLM_MODEL_NAME:-${MODEL}}"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      API_BASE="${2:-}"
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    *)
      echo "未知参数: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "${API_BASE}" ]]; then
  echo "[FAIL] OPENAI_API_BASE 未设置" >&2
  exit 1
fi

if [[ -z "${API_KEY}" ]]; then
  echo "[FAIL] OPENAI_API_KEY 未设置" >&2
  exit 1
fi

API_BASE="${API_BASE%/}"
echo "检查 LLM API: ${API_BASE}"
echo "模型: ${MODEL}"

models_tmp=$(mktemp)
models_code="000"
if curl -s -o "${models_tmp}" -w '%{http_code}' \
  --connect-timeout 10 --max-time 20 \
  "${API_BASE}/models" \
  -H "Authorization: Bearer ${API_KEY}" >"${models_tmp}.code" 2>/dev/null; then
  models_code="$(tr -d '[:space:]' <"${models_tmp}.code")"
fi
rm -f "${models_tmp}" "${models_tmp}.code"

if [[ ! "${models_code}" =~ ^[1-9][0-9]{2}$ ]]; then
  echo "[FAIL] 无法连接 ${API_BASE}（HTTP ${models_code:-无响应}，网络不通或隧道已失效）" >&2
  exit 1
fi

echo "[OK]   GET /models -> HTTP ${models_code}"

chat_body=$(curl -s -w '\n__HTTP__:%{http_code}' \
  --connect-timeout 10 --max-time 60 \
  -X POST "${API_BASE}/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":5,\"stream\":false}")

chat_http="${chat_body##*__HTTP__:}"
chat_resp="${chat_body%__HTTP__:*}"

if [[ "${chat_http}" == "200" ]] && echo "${chat_resp}" | grep -q '"choices"'; then
  echo "[OK]   POST /chat/completions -> HTTP 200"
  echo "LLM API 正常"
  exit 0
fi

echo "[FAIL] POST /chat/completions -> HTTP ${chat_http}" >&2
if echo "${chat_resp}" | grep -qi 'cloudflare\|502\|bad gateway'; then
  echo "原因: Cloudflare 隧道可达，但 origin LLM 代理返回 502（Windows 侧后端未运行或异常）" >&2
  echo "处理: 在 Windows 重启 cloudflared + LLM 代理，更新 ~/.bashrc 中 OPENAI_API_BASE 为新隧道地址后:" >&2
  echo "      bash deploy/set_openai_api_base.sh <新URL> --restart" >&2
elif [[ "${chat_http}" == "401" ]]; then
  echo "原因: API Key 无效" >&2
else
  echo "响应片段: $(echo "${chat_resp}" | tr '\n' ' ' | head -c 300)" >&2
fi
exit 1
