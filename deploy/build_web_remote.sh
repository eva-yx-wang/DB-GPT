#!/bin/bash
# 打包 web 源码供 Windows 远程构建，或接收 Windows 构建产物并部署到 static/web
#
# 用法:
#   bash deploy/build_web_remote.sh pack          # 在 Linux 服务器打包
#   bash deploy/build_web_remote.sh deploy <tar>  # 部署 Windows 回传的 out 包
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WEB_DIR="${PROJECT_ROOT}/web"
STATIC_DIR="${PROJECT_ROOT}/packages/dbgpt-app/src/dbgpt_app/static/web"
PACK_DIR="${PROJECT_ROOT}/deploy/dist"
WEB_SRC_TAR="${PACK_DIR}/dbgpt-web-src.tar.gz"
WEB_OUT_TAR="${PACK_DIR}/dbgpt-web-out.tar.gz"

pack_web_src() {
  mkdir -p "${PACK_DIR}"
  echo "打包 web 源码 -> ${WEB_SRC_TAR}"
  tar czf "${WEB_SRC_TAR}" \
    --exclude='node_modules' \
    --exclude='.next' \
    --exclude='out' \
    --exclude='.env' \
    -C "${PROJECT_ROOT}" \
    web
  ls -lh "${WEB_SRC_TAR}"
  echo
  echo "=== 下一步: 在 Windows (10.39.91.40) 执行 ==="
  echo
  cat <<'EOF'
# 1) 从 Linux 服务器拉取源码包 (在 Windows PowerShell 中)
mkdir C:\projects\gacet\dev_repo\DB-GPT -Force
scp datagroup@<LINUX_IP>:/home/datagroup/projects/DB-GPT/deploy/dist/dbgpt-web-src.tar.gz C:\projects\gacet\dev_repo\DB-GPT\

# 2) 解压并构建
cd C:\projects\gacet\dev_repo\DB-GPT
tar -xzf dbgpt-web-src.tar.gz
cd web
copy .env.template .env
# 编辑 .env: API_BASE_URL=http://<LINUX_IP>:5670
npm install
npm run compile

# 3) 打包 out 并回传 Linux
cd C:\projects\gacet\dev_repo\DB-GPT\web
tar -czf ..\deploy\dist\dbgpt-web-out.tar.gz -C out .
scp ..\deploy\dist\dbgpt-web-out.tar.gz datagroup@<LINUX_IP>:/home/datagroup/projects/DB-GPT/deploy/dist/

# 4) 在 Linux 服务器部署
bash deploy/build_web_remote.sh deploy deploy/dist/dbgpt-web-out.tar.gz
bash deploy/dbgpt.sh restart
EOF
}

deploy_web_out() {
  local tar_file="${1:-${WEB_OUT_TAR}}"
  if [[ ! -f "${tar_file}" ]]; then
    echo "找不到构建产物: ${tar_file}" >&2
    exit 1
  fi
  echo "部署 ${tar_file} -> ${STATIC_DIR}"
  rm -rf "${STATIC_DIR}"
  mkdir -p "${STATIC_DIR}"
  tar xzf "${tar_file}" -C "${STATIC_DIR}"
  echo "部署完成，文件数: $(find "${STATIC_DIR}" -type f | wc -l)"
  echo "请执行: bash deploy/dbgpt.sh restart"
}

case "${1:-pack}" in
  pack)
    pack_web_src
    ;;
  deploy)
    deploy_web_out "${2:-${WEB_OUT_TAR}}"
    ;;
  *)
    echo "用法: $0 {pack|deploy [tar_file]}" >&2
    exit 1
    ;;
esac
