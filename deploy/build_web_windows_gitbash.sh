#!/usr/bin/env bash
# DB-GPT 前端：Windows Git Bash 远程拉取 → 构建 → 回传 Linux
#
# 在 Windows Git Bash 中执行（需已安装 Node.js、npm、OpenSSH）:
#   cd /c/projects/gacet/dev_repo/DB-GPT
#   bash deploy/build_web_windows_gitbash.sh
#
# 环境变量（可选）:
#   REMOTE_HOST=172.17.1.58
#   REMOTE_USER=datagroup
#   REMOTE_PROJECT=/home/datagroup/projects/DB-GPT
#   LOCAL_WORK_DIR=/c/projects/gacet/dev_repo/DB-GPT
#   PROGRESS_INTERVAL_SEC=600   # 构建进度提示间隔，默认 10 分钟
#   SKIP_PACK=1                 # 跳过服务器打包，使用本地已有 dbgpt-web-src.tar.gz
#   SKIP_NPM_INSTALL=1          # 跳过 npm install（node_modules 已存在时）
#   AUTO_DEPLOY=1               # 回传后 SSH 到服务器自动 deploy（不 restart）
#
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-172.17.1.58}"
REMOTE_USER="${REMOTE_USER:-datagroup}"
REMOTE_PROJECT="${REMOTE_PROJECT:-/home/datagroup/projects/DB-GPT}"
LOCAL_WORK_DIR="${LOCAL_WORK_DIR:-/c/projects/gacet/dev_repo/DB-GPT}"
PROGRESS_INTERVAL_SEC="${PROGRESS_INTERVAL_SEC:-600}"
API_BASE_URL="${API_BASE_URL:-http://${REMOTE_HOST}:5670}"

REMOTE_DIST="${REMOTE_PROJECT}/deploy/dist"
SRC_TAR_NAME="dbgpt-web-src.tar.gz"
OUT_TAR_NAME="dbgpt-web-out.tar.gz"
LOCAL_DIST="${LOCAL_WORK_DIR}/deploy/dist"
SRC_TAR="${LOCAL_DIST}/${SRC_TAR_NAME}"
OUT_TAR="${LOCAL_DIST}/${OUT_TAR_NAME}"
BUILD_LOG="${LOCAL_WORK_DIR}/web/build-compile.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "未找到命令: $1（请在 Git Bash / PATH 中安装）"
}

format_duration() {
  local secs="$1"
  printf '%02d:%02d:%02d' $((secs / 3600)) $(((secs % 3600) / 60)) $((secs % 60))
}

# ---------- 步骤 1: 从 Linux 拉取待构建源码 ----------
step_fetch() {
  log "========== 步骤 1/3: 从服务器拉取前端源码 =========="
  log "服务器: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PROJECT}"

  require_cmd ssh
  require_cmd scp
  mkdir -p "${LOCAL_DIST}"

  if [[ "${SKIP_PACK:-0}" != "1" ]]; then
    log "在服务器上打包 web 源码..."
    ssh "${REMOTE_USER}@${REMOTE_HOST}" \
      "bash '${REMOTE_PROJECT}/deploy/build_web_remote.sh' pack"
  else
    log "SKIP_PACK=1，跳过服务器打包"
  fi

  log "下载 ${SRC_TAR_NAME} ..."
  scp "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIST}/${SRC_TAR_NAME}" "${SRC_TAR}"
  log "源码包已保存: ${SRC_TAR} ($(du -h "${SRC_TAR}" | cut -f1))"
}

# ---------- 步骤 2: 解压并构建（每 10 分钟输出进度） ----------
step_build() {
  log "========== 步骤 2/3: 构建前端 =========="
  require_cmd tar
  require_cmd npm
  require_cmd node

  mkdir -p "${LOCAL_WORK_DIR}"
  cd "${LOCAL_WORK_DIR}"

  log "解压源码..."
  tar -xzf "${SRC_TAR}"

  cd "${LOCAL_WORK_DIR}/web"
  if [[ ! -f package.json ]]; then
    die "解压后未找到 web/package.json"
  fi

  if [[ ! -f .env ]]; then
    log "创建 .env（API_BASE_URL=${API_BASE_URL}）"
    cp .env.template .env
    if grep -q '^API_BASE_URL=' .env 2>/dev/null; then
      sed -i "s|^API_BASE_URL=.*|API_BASE_URL=${API_BASE_URL}|" .env
    else
      echo "API_BASE_URL=${API_BASE_URL}" >> .env
    fi
  else
    log "使用已有 .env"
  fi

  if [[ "${SKIP_NPM_INSTALL:-0}" != "1" ]]; then
    log "npm install（首次或依赖变更时较慢，请耐心等待）..."
    npm install 2>&1 | tee -a "${BUILD_LOG}"
  else
    log "SKIP_NPM_INSTALL=1，跳过 npm install"
  fi

  : > "${BUILD_LOG}"
  log "开始 npm run compile，日志: ${BUILD_LOG}"
  log "每 ${PROGRESS_INTERVAL_SEC} 秒（$((PROGRESS_INTERVAL_SEC / 60)) 分钟）输出一次进度，避免误以为卡死"

  export NODE_OPTIONS="${NODE_OPTIONS:---max_old_space_size=8192}"
  local start_ts
  start_ts=$(date +%s)

  npm run compile >> "${BUILD_LOG}" 2>&1 &
  local build_pid=$!

  while kill -0 "${build_pid}" 2>/dev/null; do
    sleep "${PROGRESS_INTERVAL_SEC}"
    if ! kill -0 "${build_pid}" 2>/dev/null; then
      break
    fi
    local now elapsed
    now=$(date +%s)
    elapsed=$((now - start_ts))
    log "---------- 构建进行中 | 已运行 $(format_duration "${elapsed}") | PID ${build_pid} ----------"
    if [[ -s "${BUILD_LOG}" ]]; then
      log "最近日志:"
      tail -n 8 "${BUILD_LOG}" | sed 's/^/  | /'
    else
      log "（尚无日志输出，Next.js 可能在编译前期）"
    fi
    if command -v tasklist >/dev/null 2>&1; then
      tasklist //FI "PID eq ${build_pid}" 2>/dev/null | tail -n +3 || true
    fi
  done

  if ! wait "${build_pid}"; then
    log "构建失败，完整日志末尾:"
    tail -n 40 "${BUILD_LOG}"
    die "npm run compile 失败，退出码: $?"
  fi

  local total_elapsed
  total_elapsed=$(($(date +%s) - start_ts))
  log "构建成功，耗时 $(format_duration "${total_elapsed}")"

  if [[ ! -d out ]] || [[ -z "$(ls -A out 2>/dev/null)" ]]; then
    die "未找到 web/out 目录或目录为空"
  fi
  log "out 目录大小: $(du -sh out | cut -f1)"
}

# ---------- 步骤 3: 打包并回传 Linux ----------
step_upload() {
  log "========== 步骤 3/3: 回传构建产物到服务器 =========="
  cd "${LOCAL_WORK_DIR}/web"
  mkdir -p "${LOCAL_DIST}"

  log "打包 out -> ${OUT_TAR}"
  tar -czf "${OUT_TAR}" -C out .
  log "产物包: ${OUT_TAR} ($(du -h "${OUT_TAR}" | cut -f1))"

  log "上传到 ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIST}/"
  scp "${OUT_TAR}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIST}/${OUT_TAR_NAME}"

  if [[ "${AUTO_DEPLOY:-0}" == "1" ]]; then
    log "在服务器上部署静态文件..."
    ssh "${REMOTE_USER}@${REMOTE_HOST}" \
      "bash '${REMOTE_PROJECT}/deploy/build_web_remote.sh' deploy '${REMOTE_PROJECT}/deploy/dist/${OUT_TAR_NAME}'"
    log "部署完成。如需重启: ssh ${REMOTE_USER}@${REMOTE_HOST} 'bash ${REMOTE_PROJECT}/deploy/dbgpt.sh restart'"
  else
    log "回传完成。请在 Linux 服务器执行:"
    echo "  cd ${REMOTE_PROJECT}"
    echo "  bash deploy/build_web_remote.sh deploy deploy/dist/${OUT_TAR_NAME}"
    echo "  # 静态资源更新后一般只需浏览器 Ctrl+Shift+R 强刷，不必重启后端"
  fi
}

main() {
  log "DB-GPT 前端 Windows 远程构建"
  log "LOCAL_WORK_DIR=${LOCAL_WORK_DIR}"
  step_fetch
  step_build
  step_upload
  log "全部完成。"
}

main "$@"
