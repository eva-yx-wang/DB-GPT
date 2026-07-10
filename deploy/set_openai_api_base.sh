#!/usr/bin/env bash
# 更新 ~/.bashrc 中的 OPENAI_API_BASE 并可选重启 DB-GPT
#
# 用法:
#   bash deploy/set_openai_api_base.sh https://xxx.trycloudflare.com/v1
#   bash deploy/set_openai_api_base.sh https://xxx.trycloudflare.com/v1 --restart
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASHRC="${HOME}/.bashrc"

NEW_BASE="${1:-}"
RESTART=0
if [[ "${2:-}" == "--restart" ]]; then
  RESTART=1
fi

if [[ -z "${NEW_BASE}" ]]; then
  echo "用法: $0 <OPENAI_API_BASE> [--restart]" >&2
  echo "示例: $0 https://abc.trycloudflare.com/v1 --restart" >&2
  exit 2
fi

NEW_BASE="${NEW_BASE%/}"
if [[ ! "${NEW_BASE}" =~ ^https?:// ]]; then
  echo "URL 必须以 http:// 或 https:// 开头" >&2
  exit 2
fi

if [[ ! -f "${BASHRC}" ]]; then
  echo "找不到 ${BASHRC}" >&2
  exit 1
fi

if grep -q '^export OPENAI_API_BASE=' "${BASHRC}"; then
  sed -i "s|^export OPENAI_API_BASE=.*|export OPENAI_API_BASE=\"${NEW_BASE}\"|" "${BASHRC}"
else
  echo "export OPENAI_API_BASE=\"${NEW_BASE}\"" >> "${BASHRC}"
fi

echo "已更新 ${BASHRC}:"
grep '^export OPENAI_API_BASE=' "${BASHRC}"

export OPENAI_API_BASE="${NEW_BASE}"
bash "${SCRIPT_DIR}/check_llm_api.sh" --url "${NEW_BASE}" || {
  echo "[WARN] 新 URL 自检未通过，请确认 Windows 侧 LLM 代理已启动" >&2
}

if [[ "${RESTART}" -eq 1 ]]; then
  bash "${PROJECT_DIR}/deploy/dbgpt.sh" restart
fi
