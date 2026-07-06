#!/bin/bash
# DB-GPT 启动脚本
# 使用 uv sync 管理 Python 依赖（.venv 环境）
# 非 Python 包使用 conda dbgpt 环境

# 激活 conda 环境（用于非 Python 工具，如系统库）
source ~/.bashrc
conda deactivate
conda activate dbgpt

# 检查并启用 devtoolset-7（如果已安装）
# devtoolset-7 提供支持 C++17 的 GCC 7.3.1
if [ -f /opt/rh/devtoolset-7/enable ]; then
    echo "启用 devtoolset-7 编译器环境..."
    source /opt/rh/devtoolset-7/enable
    echo "✓ devtoolset-7 已启用"
fi

# 设置编译器标志
# 注意：某些包（如 pyzmq）需要 C99，而某些包（如 marisa-trie）需要 C++17
# 为了同时支持两者，我们需要分别设置 C 和 C++ 的编译标志

# 检查并设置支持 C++17 的编译器
echo "检查编译器 C++17 支持..."

# 优先检查 conda 环境中的编译器（如果存在）
CONDA_GXX=""
if [ -n "$CONDA_PREFIX" ] && [ -f "$CONDA_PREFIX/bin/g++" ]; then
    CONDA_GXX="$CONDA_PREFIX/bin/g++"
    if $CONDA_GXX -std=c++17 -x c++ -c /dev/null -o /dev/null 2>/dev/null; then
        echo "✓ 使用 conda 环境中的 g++（支持 C++17）"
        export PATH="$CONDA_PREFIX/bin:$PATH"
    else
        CONDA_GXX=""
    fi
fi

# 检查系统的 g++
if [ -z "$CONDA_GXX" ]; then
    if g++ -std=c++17 -x c++ -c /dev/null -o /dev/null 2>/dev/null; then
        echo "✓ 系统的 g++ 支持 C++17"
    else
        echo ""
        echo "✗ 错误: 无法找到支持 C++17 的编译器"
        echo ""
        echo "marisa-trie 等包需要 C++17 支持（需要 GCC 7+）"
        echo "当前 g++ 版本：$(g++ --version | head -1)"
        echo ""
        echo "解决方案："
        echo "  运行安装脚本安装支持 C++17 的编译器："
        echo "    bash $(dirname "$0")/deploy/install_compiler.sh"
        echo ""
        echo "  或手动安装："
        echo "    conda activate dbgpt"
        echo "    conda install -y -c conda-forge cxx-compiler c-compiler"
        echo ""
        exit 1
    fi
fi

# ============================================================================
# 编译器标志配置
# ============================================================================
# CFLAGS: 用于 C 代码编译
# - 支持 C99 标准（解决 pyzmq 编译问题）
# - 添加 -D_GNU_SOURCE 确保 POSIX 宏定义可用（解决 jemalloc 编译问题）
# - 注意：不在 CFLAGS 中包含 -std，避免被错误应用到 C++ 编译
export CFLAGS="-O2 -fPIC -D_GNU_SOURCE"

# CXXFLAGS: 用于 C++ 代码编译
# - 使用 C++17 标准支持现代 C++ 特性
# - 添加 -D_GLIBCXX_USE_CXX11_ABI=1 使用新的 C++ ABI（DuckDB 需要，GCC 7.3.1 默认使用旧 ABI）
export CXXFLAGS="-std=c++17 -D_GLIBCXX_USE_CXX11_ABI=1 -O2 -fPIC"

# CPPFLAGS: 预处理器标志（设置为空，避免影响编译）
export CPPFLAGS=""

# 编译器命令
export CC="gcc -std=c99"
export LDSHARED="gcc -shared -std=c99"
export LDCXXSHARED="g++ -shared -std=c++17 -D_GLIBCXX_USE_CXX11_ABI=1"
# 注意：CXX 将在下面创建包装脚本后设置，用于过滤不支持的链接器选项

# ============================================================================
# DuckDB 构建配置
# ============================================================================
# DuckDB 使用 scikit-build-core，通过环境变量传递 CMake 变量
# 问题：DuckDB 1.4.2 在链接 Python 绑定时会使用 --export-dynamic-symbol 选项
#      （包括 duckdb_adbc_init 和 PyInit__duckdb），但系统的链接器（GNU ld 2.28）
#      不支持该选项（需要 binutils 2.30+）
# 解决方案：通过 g++ 包装脚本自动过滤掉所有不支持的 --export-dynamic-symbol 选项

# CMake 参数（传递给 scikit-build-core）
export CMAKE_ARGS="-DDUCKDB_EXPLICIT_PLATFORM=linux-amd64"
export SKBUILD_CMAKE_ARGS="-DDUCKDB_EXPLICIT_PLATFORM=linux-amd64"

# CMake C++ 标志（确保 ABI 标志在配置阶段就被应用）
export CMAKE_CXX_FLAGS="-D_GLIBCXX_USE_CXX11_ABI=1"
export CMAKE_CXX_FLAGS_INIT="-D_GLIBCXX_USE_CXX11_ABI=1"

# DuckDB 平台环境变量（某些构建系统可能会读取）
export DUCKDB_EXPLICIT_PLATFORM="linux-amd64"
export DUCKDB_PLATFORM="linux-amd64"

# 并行编译数量（加快编译速度，duckdb 编译可能需要 10-30 分钟）
PARALLEL_JOBS=$(nproc 2>/dev/null || echo 4)
if [ "$PARALLEL_JOBS" -gt 8 ]; then
    PARALLEL_JOBS=8
fi
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$PARALLEL_JOBS}"

# ============================================================================
# 链接器选项过滤（解决 --export-dynamic-symbol 不支持的问题）
# ============================================================================
# 创建 g++ 包装脚本，自动过滤掉所有不支持的 --export-dynamic-symbol 选项
WRAPPER_SCRIPT="/tmp/gpp_wrapper_$$.sh"
cat > "$WRAPPER_SCRIPT" << 'WRAPPER_EOF'
#!/bin/bash
# 包装 g++ 命令，过滤掉所有包含 --export-dynamic-symbol 的链接器选项
# 系统的链接器（ld 2.28）不支持该选项，无论符号名称是什么
FILTERED_ARGS=()
for arg in "$@"; do
    # 跳过所有包含 --export-dynamic-symbol 的选项
    # 包括 -Wl,--export-dynamic-symbol=duckdb_adbc_init 和 -Wl,--export-dynamic-symbol=PyInit__duckdb
    if [[ "$arg" != *"--export-dynamic-symbol"* ]]; then
        FILTERED_ARGS+=("$arg")
    fi
done
# 使用原始 g++ 执行过滤后的参数
exec /opt/rh/devtoolset-7/root/usr/bin/g++ "${FILTERED_ARGS[@]}"
WRAPPER_EOF
chmod +x "$WRAPPER_SCRIPT"
# 通过 CXX 环境变量使用包装脚本，CMake 和构建系统会使用它来编译和链接
export CXX="$WRAPPER_SCRIPT"

# ============================================================================
# 其他构建环境变量
# ============================================================================
export LDFLAGS=""
export PKG_CONFIG_PATH=""
export PYTHONDONTWRITEBYTECODE=1
export PYTHONUNBUFFERED=1

# ============================================================================
# 切换到项目目录并显示配置信息
# ============================================================================
cd /home/datagroup/projects/DB-GPT

echo "DuckDB 构建配置："
echo "  CMAKE_ARGS: $CMAKE_ARGS"
echo "  SKBUILD_CMAKE_ARGS: $SKBUILD_CMAKE_ARGS"
echo "  CMAKE_CXX_FLAGS: $CMAKE_CXX_FLAGS"
echo "  并行编译数: $CMAKE_BUILD_PARALLEL_LEVEL"
echo "  工作目录: $(pwd)"
echo ""

# 检查 Rust 编译器（tiktoken 需要 Rust 来编译）
echo "检查 Rust 编译器..."
RUST_INSTALLED=0

# 先检查是否在 PATH 中
if command -v rustc &> /dev/null; then
    RUST_INSTALLED=1
    echo "✓ Rust 编译器已安装: $(rustc --version)"
# 检查 cargo 环境文件（可能已安装但未在 PATH 中）
elif [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
    if command -v rustc &> /dev/null; then
        RUST_INSTALLED=1
        echo "✓ Rust 编译器已安装: $(rustc --version)"
    fi
fi

# 如果未安装，提示用户运行安装脚本
if [ $RUST_INSTALLED -eq 0 ]; then
    echo ""
    echo "✗ 未检测到 Rust 编译器,请先安装 Rust："
    echo ""
    echo "  运行安装脚本："
    echo "    bash $(dirname "$0")/deploy/check_rust.sh"
    echo ""
    echo "  或查看安装指南："
    echo "    cat $(dirname "$0")/deploy/INSTALL_RUST.md"
    echo ""
    echo "安装完成后，请重新运行此脚本。"
    echo ""
    exit 1
fi
echo ""

# 使用 uv sync 创建和管理 .venv 环境，安装所有依赖
# 依赖版本定义在 pyproject.toml 中
echo "使用 uv sync 同步依赖到 .venv 环境..."
echo "依赖版本定义在 pyproject.toml 中"
echo ""

# 清理可能存在的无效构建缓存（特别是 duckdb 的失败构建）
# uv 会缓存构建结果，如果之前的构建失败，可能会重用失败的缓存
# CMake 也会缓存构建配置，失败的构建可能影响后续构建
echo "清理可能存在的无效构建缓存..."

# 清理 /tmp 下超过 1 小时的临时构建目录（可能是之前失败的构建）
# 这些目录通常由 scikit-build-core 或 CMake 创建
TMP_CLEANED=$(find /tmp -maxdepth 1 -type d -name "tmp*" -mmin +60 2>/dev/null | wc -l)
if [ "$TMP_CLEANED" -gt 0 ]; then
    find /tmp -maxdepth 1 -type d -name "tmp*" -mmin +60 -exec rm -rf {} + 2>/dev/null || true
    echo "  清理了 $TMP_CLEANED 个旧的临时构建目录"
fi

# 清理 uv 构建缓存中的 duckdb 相关缓存（如果存在）
# 注意：uv 的构建缓存通常会自动管理，但失败的构建可能需要手动清理
if [ -d "$HOME/.cache/uv/builds-v0" ]; then
    # 清理超过 1 小时的 duckdb 构建缓存
    DUCKDB_CLEANED=$(find "$HOME/.cache/uv/builds-v0" -type d -name "*duckdb*" -mmin +60 2>/dev/null | wc -l)
    if [ "$DUCKDB_CLEANED" -gt 0 ]; then
        find "$HOME/.cache/uv/builds-v0" -type d -name "*duckdb*" -mmin +60 -exec rm -rf {} + 2>/dev/null || true
        echo "  清理了 $DUCKDB_CLEANED 个旧的 duckdb 构建缓存"
    fi
fi

# 如果设置了环境变量 FORCE_CLEAN_BUILD，强制清理所有构建缓存
if [ "${FORCE_CLEAN_BUILD:-0}" = "1" ]; then
    echo "  强制清理模式：清理所有构建缓存..."
    # 清理所有临时构建目录
    find /tmp -maxdepth 1 -type d -name "tmp*" -exec rm -rf {} + 2>/dev/null || true
    # 清理 uv 构建缓存（谨慎操作）
    if [ -d "$HOME/.cache/uv/builds-v0" ]; then
        find "$HOME/.cache/uv/builds-v0" -type d -name "*duckdb*" -exec rm -rf {} + 2>/dev/null || true
    fi
    echo "  ✓ 强制清理完成"
fi

echo "✓ 构建缓存清理完成"
echo ""

# 使用 uv sync 安装所有包的依赖及可选依赖组
# --all-packages: 同步所有工作空间包
# --frozen: 使用锁定的依赖版本（如果存在 uv.lock）
# --extra: 安装指定的可选依赖组
# 注意：对于 duckdb，已通过环境变量传递 CMake 配置
# 环境变量 CMAKE_ARGS 和 SKBUILD_CMAKE_ARGS 会被 scikit-build-core 读取
# 不需要使用 --config-settings，因为那会应用到所有包，导致其他包（如 rapidfuzz）报错
echo "开始安装依赖包..."
echo "注意：duckdb 编译时间较长（可能需要 10-30 分钟），请耐心等待..."
echo "如果进程看起来卡住，请检查 CPU 和内存使用情况（duckdb 编译会占用大量资源）"
echo ""

# 使用 timeout 命令确保进程不会真正卡死（可选，默认 2 小时超时）
# 如果系统没有 timeout 命令，则直接执行
if command -v timeout &> /dev/null; then
    TIMEOUT_CMD="timeout 7200"  # 2 小时超时
else
    TIMEOUT_CMD=""
fi

# 设置 pipefail 以确保管道中任何命令失败都会导致整个命令失败
set -o pipefail 2>/dev/null || true

# 执行 uv sync，同时保存日志到文件
# 注意：duckdb 编译时间较长，这是正常的
if ! $TIMEOUT_CMD uv sync --all-packages --frozen \
    --extra "base" \
    --extra "proxy_openai" \
    --extra "rag" \
    --extra "storage_chromadb" \
    --extra "dbgpts" 2>&1 | tee /tmp/uv_sync.log; then
    echo ""
    echo "错误: uv sync 失败，无法安装依赖"
    echo ""
    echo "常见问题及解决方案："
    echo "1. 如果错误信息包含 'can't find Rust compiler' 或 'tiktoken'："
    echo "   - 请确保已安装 Rust 编译器"
    echo "   - 安装命令: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo "   - 然后运行: source ~/.cargo/env"
    echo ""
    echo "2. 如果错误信息包含 'rapidfuzz' 和 'Unrecognized options in config-settings'："
    echo "   - 这通常是因为使用了 --config-settings duckdb.cmake.define 参数"
    echo "   - 该参数会被应用到所有包，但 rapidfuzz 不支持此格式"
    echo "   - 解决方案：duckdb 的配置已通过环境变量传递，不需要 --config-settings"
    echo "   - 请检查脚本中是否意外添加了 --config-settings 参数"
    echo ""
    echo "3. 如果进程卡在 'Building duckdb' 步骤："
    echo "   - duckdb 编译时间较长（10-30 分钟），这是正常的"
    echo "   - 请检查 CPU 和内存使用情况：top 或 htop"
    echo "   - 如果确实卡死，可以尝试："
    echo "     * 清理构建缓存：export FORCE_CLEAN_BUILD=1 && bash $0"
    echo "     * 检查日志：tail -f /tmp/uv_sync.log"
    echo "     * 增加并行编译：export CMAKE_BUILD_PARALLEL_LEVEL=4"
    echo ""
    echo "4. 如果没有 uv.lock 文件，可以尝试移除 --frozen 标志："
    echo "   - 修改脚本，将 '--frozen' 改为 '--no-frozen'"
    echo ""
    echo "5. 如果是网络问题，请检查 PyPI 镜像源配置"
    echo ""
    exit 1
fi

# 检查 .venv 是否创建成功
VENV_PYTHON=".venv/bin/python"
if [ ! -f "$VENV_PYTHON" ]; then
    echo "错误: .venv 环境未创建成功"
    exit 1
fi

echo "依赖安装完成，使用 .venv 环境: $VENV_PYTHON"
echo ""

# 验证关键依赖是否安装成功
echo "验证关键依赖..."
if ! "$VENV_PYTHON" -c "import numpy; import pandas; import fastapi; import dbgpt; import dbgpt_app" 2>/dev/null; then
    echo "错误: 关键依赖验证失败"
    exit 1
fi
echo "关键依赖验证通过"
echo ""

# 设置 PYTHONPATH，确保能找到工作空间包
# dbgpt 模块在 packages/dbgpt-core/src 目录下
# dbgpt_app 模块在 packages/dbgpt-app/src 目录下
export PYTHONPATH="${PYTHONPATH:+${PYTHONPATH}:}$(pwd)/packages/dbgpt-core/src:$(pwd)/packages/dbgpt-app/src:$(pwd)/packages:$(pwd)"

# 启动服务
echo "正在启动 DB-GPT 服务..."
echo "Python 环境: $VENV_PYTHON"
echo "编译器标志: CFLAGS=$CFLAGS, CXXFLAGS=$CXXFLAGS"
echo "配置文件: configs/dbgpt-proxy-tongyi.toml"
echo "PYTHONPATH: $PYTHONPATH"
echo ""

# 使用 uv run 启动服务（自动使用项目的虚拟环境和正确的 PYTHONPATH）
# 优先尝试使用 dbgpt 命令（官方推荐方式）
if "$VENV_PYTHON" -c "import dbgpt.cli.cli_scripts" 2>/dev/null; then
    # 使用官方推荐的 uv run dbgpt 命令
    uv run dbgpt start webserver --config configs/dbgpt-proxy-tongyi.toml
else
    # 如果 dbgpt 命令不可用，使用官方推荐的备用方式：直接运行 Python 脚本
    echo "警告: dbgpt CLI 不可用，使用 Python 脚本方式运行..."
    uv run python packages/dbgpt-app/src/dbgpt_app/dbgpt_server.py --config configs/dbgpt-proxy-tongyi.toml
fi
