#!/bin/bash
# Rust 编译器安装脚本
# 如果未安装 Rust，则自动安装

# 不使用 set -e，以便更好地处理交互和错误

echo "=========================================="
echo "Rust 编译器安装检查"
echo "=========================================="
echo ""

# 检查 Rust 是否已安装
RUST_INSTALLED=0

# 先检查是否在 PATH 中
if command -v rustc &> /dev/null; then
    RUST_INSTALLED=1
    echo "✓ Rust 编译器已安装: $(rustc --version)"
    exit 0
fi

# 检查 cargo 环境文件（可能已安装但未在 PATH 中）
if [ -f "$HOME/.cargo/env" ]; then
    echo "发现 ~/.cargo/env 文件，尝试加载..."
    source "$HOME/.cargo/env"
    if command -v rustc &> /dev/null; then
        RUST_INSTALLED=1
        echo "✓ Rust 编译器已安装: $(rustc --version)"
        exit 0
    fi
fi

# 如果已安装，直接退出
if [ $RUST_INSTALLED -eq 1 ]; then
    exit 0
fi

# 未安装，开始安装流程
echo "✗ 未检测到 Rust 编译器"
echo ""
echo "开始安装 Rust 编译器..."
echo ""

# 检查是否部分安装（需要清理）
if [ -d "$HOME/.cargo" ] || [ -d "$HOME/.rustup" ]; then
    echo "警告: 发现部分安装的 Rust 文件"
    read -p "是否清理后重新安装？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "清理旧的安装文件..."
        rm -rf "$HOME/.cargo" "$HOME/.rustup"
    fi
fi

# 检查网络连接并选择最佳安装源
echo ""
echo "检查网络连接..."

# 尝试多个源，按优先级顺序
MIRROR_SELECTED=0

# 1. 优先尝试官方源
echo "正在测试官方源 (rust-lang.org)..."
if timeout 5 curl -I --connect-timeout 3 https://static.rust-lang.org >/dev/null 2>&1; then
    echo "✓ 可以访问 Rust 官方下载服务器"
    MIRROR_SELECTED=1
    USE_MIRROR="official"
# 2. 尝试清华大学镜像
elif timeout 5 curl -I --connect-timeout 3 https://mirrors.tuna.tsinghua.edu.cn >/dev/null 2>&1; then
    echo "✓ 可以访问清华大学镜像源"
    MIRROR_SELECTED=1
    USE_MIRROR="tsinghua"
# 3. 尝试中科大镜像
elif timeout 5 curl -I --connect-timeout 3 https://mirrors.ustc.edu.cn >/dev/null 2>&1; then
    echo "✓ 可以访问中科大镜像源"
    MIRROR_SELECTED=1
    USE_MIRROR="ustc"
# 4. 尝试 rustcc 镜像（最后尝试，因为可能不稳定）
elif timeout 5 curl -I --connect-timeout 3 https://mirrors.rustcc.cn >/dev/null 2>&1; then
    echo "✓ 可以访问 RustCC 镜像源"
    MIRROR_SELECTED=1
    USE_MIRROR="rustcc"
else
    echo "✗ 无法访问所有测试的下载服务器"
    echo "  将尝试使用官方源进行安装（可能较慢）"
    USE_MIRROR="official"
fi

# 根据选择的镜像源设置环境变量和安装命令
case "$USE_MIRROR" in
    "official")
        echo ""
        echo "使用官方源安装 Rust..."
        unset RUSTUP_DIST_SERVER
        unset RUSTUP_UPDATE_ROOT
        INSTALL_URL=https://sh.rustup.rs
        INSTALL_CMD="curl --proto '=https' --tlsv1.2 -sSf $INSTALL_URL | sh -s -- --default-toolchain stable --profile minimal -y"
        ;;
    "tsinghua")
        echo ""
        echo "使用清华大学镜像源安装 Rust..."
        # 注意：清华大学镜像可能需要不同的配置，这里使用官方安装脚本但设置镜像环境变量
        # 实际下载时会使用镜像源
        export RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup
        export RUSTUP_UPDATE_ROOT=https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup
        INSTALL_URL=https://sh.rustup.rs
        INSTALL_CMD="curl --connect-timeout 10 --max-time 300 -sSf $INSTALL_URL | sh -s -- --default-toolchain stable --profile minimal -y"
        ;;
    "ustc")
        echo ""
        echo "使用中科大镜像源安装 Rust..."
        export RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static
        export RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup
        INSTALL_URL=https://sh.rustup.rs
        INSTALL_CMD="curl --connect-timeout 10 --max-time 300 -sSf $INSTALL_URL | sh -s -- --default-toolchain stable --profile minimal -y"
        ;;
    "rustcc")
        echo ""
        echo "使用 RustCC 镜像源安装 Rust..."
        export RUSTUP_DIST_SERVER=https://mirrors.rustcc.cn
        export RUSTUP_UPDATE_ROOT=https://mirrors.rustcc.cn/rustup
        INSTALL_URL=https://sh.rustup.rs
        INSTALL_CMD="curl --connect-timeout 10 --max-time 300 -sSf $INSTALL_URL | sh -s -- --default-toolchain stable --profile minimal -y"
        ;;
    *)
        echo ""
        echo "使用默认（官方源）安装 Rust..."
        INSTALL_URL=https://sh.rustup.rs
        INSTALL_CMD="curl --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 300 -sSf $INSTALL_URL | sh -s -- --default-toolchain stable --profile minimal -y"
        ;;
esac

echo ""
echo "正在下载并安装 Rust（这可能需要几分钟，请耐心等待）..."
if [ "$USE_MIRROR" != "official" ]; then
    echo "镜像源: $RUSTUP_DIST_SERVER"
fi
echo "安装脚本 URL: $INSTALL_URL"
echo ""

# 执行安装
if eval "$INSTALL_CMD"; then
    # 加载 Rust 环境
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"

        # 验证安装
        if command -v rustc &> /dev/null; then
            echo ""
            echo "=========================================="
            echo "✓ Rust 安装成功！"
            echo "=========================================="
            echo ""
            echo "Rust 版本: $(rustc --version)"
            echo "Cargo 版本: $(cargo --version)"
            echo ""
            echo "注意: 请确保在 ~/.bashrc 中添加以下内容，以便每次登录时自动加载 Rust 环境："
            echo ""
            echo "  if [ -f \"\$HOME/.cargo/env\" ]; then"
            echo "      source \"\$HOME/.cargo/env\""
            echo "  fi"
            echo ""

            # 检查是否已添加到 ~/.bashrc
            if ! grep -q "\.cargo/env" "$HOME/.bashrc" 2>/dev/null; then
                read -p "是否自动添加到 ~/.bashrc？(Y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    echo "" >> "$HOME/.bashrc"
                    echo "# Rust environment" >> "$HOME/.bashrc"
                    echo "if [ -f \"\$HOME/.cargo/env\" ]; then" >> "$HOME/.bashrc"
                    echo "    source \"\$HOME/.cargo/env\"" >> "$HOME/.bashrc"
                    echo "fi" >> "$HOME/.bashrc"
                    echo "✓ 已添加到 ~/.bashrc"
                fi
            fi

            exit 0
        else
            echo ""
            echo "警告: 安装完成但无法找到 rustc 命令"
            echo "请尝试运行: source ~/.cargo/env"
            exit 1
        fi
    else
        echo ""
        echo "错误: 安装完成但未找到 ~/.cargo/env 文件"
        exit 1
    fi
else
    echo ""
    echo "=========================================="
    echo "✗ Rust 安装失败"
    echo "=========================================="
    echo ""
    echo "可能的原因："
    echo "  1. 网络连接中断或不稳定"
    echo "  2. 无法访问下载服务器（DNS 解析失败或防火墙阻止）"
    echo "  3. 下载超时"
    echo "  4. 磁盘空间不足"
    echo "  5. 权限问题"
    echo ""
    echo "解决方案："
    echo ""
    echo "方案 1: 手动指定镜像源安装"
    echo "  如果当前使用的镜像源不可用，可以尝试其他源："
    echo ""
    echo "  # 使用官方源："
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain stable --profile minimal -y"
    echo ""
    echo "  # 使用清华大学镜像（如果可访问）："
    echo "  export RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup"
    echo "  curl -sSf https://sh.rustup.rs | sh -s -- --default-toolchain stable --profile minimal -y"
    echo ""
    echo "方案 2: 手动下载安装器"
    echo "  1. 下载 rustup-init（选择可访问的源）："
    echo "     curl -O https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
    echo ""
    echo "  2. 运行安装器："
    echo "     chmod +x rustup-init"
    echo "     ./rustup-init --default-toolchain stable --profile minimal -y"
    echo ""
    echo "  3. 加载环境："
    echo "     source ~/.cargo/env"
    echo ""
    echo "方案 3: 配置代理（如果需要）"
    echo "  如果网络需要通过代理访问，请配置代理环境变量："
    echo "     export http_proxy=http://your-proxy:port"
    echo "     export https_proxy=http://your-proxy:port"
    echo "  然后重新运行此脚本"
    echo ""
    echo "详细安装指南请参考: $(dirname "$0")/INSTALL_RUST.md"
    echo ""
    exit 1
fi
