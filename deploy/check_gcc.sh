#!/bin/bash
# g++ 编译器安装脚本
# 如果未安装 g++，则自动安装（使用国内镜像源）

# 不使用 set -e，以便更好地处理交互和错误

echo "=========================================="
echo "g++ 编译器安装检查"
echo "=========================================="
echo ""

# 先检测系统类型（在检查 g++ 之前，因为可能需要根据系统类型安装）
if [ -f /etc/redhat-release ]; then
    # CentOS/RHEL 系统
    OS_TYPE="centos"
elif [ -f /etc/debian_version ]; then
    # Debian/Ubuntu 系统
    OS_TYPE="debian"
else
    OS_TYPE="unknown"
fi

# 检查 g++ 是否已安装
NEED_UPGRADE=0
if command -v g++ &> /dev/null; then
    echo "✓ g++ 编译器已安装: $(g++ --version | head -n 1)"

    # 检查 g++ 是否支持 C++17
    if g++ -std=c++17 -x c++ -c /dev/null -o /dev/null 2>/dev/null; then
        echo "✓ 系统的 g++ 支持 C++17"
        exit 0
    else
        echo ""
        echo "✗ 警告: 当前 g++ 不支持 C++17"
        echo ""
        echo "marisa-trie 等包需要 C++17 支持（需要 GCC 7+）"
        echo "当前 g++ 版本：$(g++ --version | head -1)"
        echo ""
        echo "将自动安装支持 C++17 的编译器..."
        echo ""
        NEED_UPGRADE=1
    fi
else
    echo "✗ 未检测到 g++ 编译器"
    echo ""
    echo "将自动安装 g++ 编译器..."
    echo ""
fi

# 显示系统类型
case "$OS_TYPE" in
    "centos")
        echo "检测到 CentOS/RHEL 系统"
        ;;
    "debian")
        echo "检测到 Debian/Ubuntu 系统"
        ;;
    *)
        echo "警告: 无法识别的系统类型，将尝试使用通用方法"
        ;;
esac

# 配置国内镜像源并安装
case "$OS_TYPE" in
    "centos")
        echo ""
        echo "配置 CentOS yum 镜像源..."

        # 备份原始 yum 配置
        if [ ! -f /etc/yum.repos.d/CentOS-Base.repo.backup ]; then
            echo "备份原始 yum 配置..."
            sudo cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup 2>/dev/null || true
        fi

        # 检测并选择可用的镜像源
        MIRROR_SELECTED=0

        # 首先检测当前系统是否已配置腾讯云镜像源
        CURRENT_MIRROR=""
        if [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
            if grep -q "mirrors.tencentyun.com" /etc/yum.repos.d/CentOS-Base.repo 2>/dev/null; then
                CURRENT_MIRROR="tencent"
                echo "检测到系统已配置腾讯云镜像源"
            fi
        fi

        # 1. 如果系统已使用腾讯云，优先使用腾讯云
        if [ "$CURRENT_MIRROR" = "tencent" ]; then
            echo "正在测试腾讯云镜像源..."
            if timeout 5 curl -I --connect-timeout 3 http://mirrors.tencentyun.com >/dev/null 2>&1; then
                echo "✓ 可以访问腾讯云镜像源"
                MIRROR_SELECTED=1
                USE_MIRROR="tencent"
            fi
        fi

        # 2. 尝试阿里云镜像
        if [ "$MIRROR_SELECTED" -eq 0 ]; then
            echo "正在测试阿里云镜像源..."
            if timeout 5 curl -I --connect-timeout 3 https://mirrors.aliyun.com >/dev/null 2>&1; then
                echo "✓ 可以访问阿里云镜像源"
                MIRROR_SELECTED=1
                USE_MIRROR="aliyun"
            # 3. 尝试清华大学镜像
            elif timeout 5 curl -I --connect-timeout 3 https://mirrors.tuna.tsinghua.edu.cn >/dev/null 2>&1; then
                echo "✓ 可以访问清华大学镜像源"
                MIRROR_SELECTED=1
                USE_MIRROR="tsinghua"
            # 4. 尝试中科大镜像
            elif timeout 5 curl -I --connect-timeout 3 https://mirrors.ustc.edu.cn >/dev/null 2>&1; then
                echo "✓ 可以访问中科大镜像源"
                MIRROR_SELECTED=1
                USE_MIRROR="ustc"
            # 5. 尝试网易镜像
            elif timeout 5 curl -I --connect-timeout 3 https://mirrors.163.com >/dev/null 2>&1; then
                echo "✓ 可以访问网易镜像源"
                MIRROR_SELECTED=1
                USE_MIRROR="163"
            else
                echo "✗ 无法访问测试的镜像源，将使用系统默认源"
                USE_MIRROR="default"
            fi
        fi

        # 根据选择的镜像源配置 yum
        if [ "$USE_MIRROR" != "default" ] && [ "$MIRROR_SELECTED" -eq 1 ]; then
            echo ""
            echo "配置 yum 使用 $USE_MIRROR 镜像源..."

            # 获取 CentOS 版本
            CENTOS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)

            case "$USE_MIRROR" in
                "tencent")
                    MIRROR_URL="http://mirrors.tencentyun.com/centos"
                    ;;
                "aliyun")
                    MIRROR_URL="https://mirrors.aliyun.com/centos"
                    ;;
                "tsinghua")
                    MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/centos"
                    ;;
                "ustc")
                    MIRROR_URL="https://mirrors.ustc.edu.cn/centos"
                    ;;
                "163")
                    MIRROR_URL="https://mirrors.163.com/centos"
                    ;;
            esac

            # 创建临时 repo 文件
            TEMP_REPO=$(mktemp)
            cat > "$TEMP_REPO" <<EOF
[base]
name=CentOS-\$releasever - Base
baseurl=$MIRROR_URL/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-$CENTOS_VERSION
enabled=1

[updates]
name=CentOS-\$releasever - Updates
baseurl=$MIRROR_URL/\$releasever/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-$CENTOS_VERSION
enabled=1

[extras]
name=CentOS-\$releasever - Extras
baseurl=$MIRROR_URL/\$releasever/extras/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-$CENTOS_VERSION
enabled=1
EOF

            # 需要 root 权限来修改 yum 配置
            if [ "$EUID" -eq 0 ]; then
                cp "$TEMP_REPO" /etc/yum.repos.d/CentOS-Base.repo
                echo "✓ yum 镜像源配置完成"
            else
                echo "提示: 需要 root 权限来配置镜像源"
                echo "将尝试使用 sudo 配置..."
                if sudo cp "$TEMP_REPO" /etc/yum.repos.d/CentOS-Base.repo; then
                    echo "✓ yum 镜像源配置完成"
                else
                    echo "警告: 无法配置镜像源，将使用默认源"
                fi
            fi
            rm -f "$TEMP_REPO"
        else
            # 即使不配置基础仓库，也检测当前系统使用的镜像源，用于后续配置 SCL 仓库
            if [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
                if grep -q "mirrors.tencentyun.com" /etc/yum.repos.d/CentOS-Base.repo 2>/dev/null; then
                    MIRROR_URL="http://mirrors.tencentyun.com/centos"
                    echo "检测到系统使用腾讯云镜像源，SCL 仓库将使用相同镜像源"
                fi
            fi
        fi

        # 获取 CentOS 版本
        CENTOS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)

        # 根据 CentOS 版本和是否需要 C++17 支持来选择安装方式
        if [ "$NEED_UPGRADE" -eq 1 ] || [ "$CENTOS_VERSION" -eq 7 ]; then
            # CentOS 7 或需要升级到支持 C++17 的版本
            echo ""
            echo "正在安装支持 C++17 的编译器（devtoolset-7）..."
            echo "这可能需要几分钟，请耐心等待..."
            echo ""

            # 先安装 SCL 仓库（如果还没有）
            if [ "$EUID" -eq 0 ]; then
                yum install -y centos-release-scl 2>/dev/null || true
            else
                sudo yum install -y centos-release-scl 2>/dev/null || true
            fi

            # 配置 SCL 仓库使用国内镜像源
            echo "配置 SCL 仓库使用镜像源..."

            # 确定要使用的镜像 URL（优先使用已选择的，否则尝试可用的）
            SCL_MIRROR_URL=""
            if [ -n "$MIRROR_URL" ] && [ "$MIRROR_URL" != "" ]; then
                SCL_MIRROR_URL="$MIRROR_URL"
                echo "SCL 仓库将使用镜像源: $MIRROR_URL"
            else
                # 尝试使用可用的镜像源（优先腾讯云，因为系统可能已使用）
                for mirror in "http://mirrors.tencentyun.com/centos" "https://mirrors.aliyun.com/centos" "https://mirrors.tuna.tsinghua.edu.cn/centos" "https://mirrors.ustc.edu.cn/centos" "https://mirrors.163.com/centos"; do
                    if timeout 3 curl -I --connect-timeout 2 "$mirror" >/dev/null 2>&1; then
                        SCL_MIRROR_URL="$mirror"
                        echo "使用镜像源: $mirror"
                        break
                    fi
                done
            fi

            # 配置 centos-sclo-rh 仓库
            SCL_RH_REPO="/etc/yum.repos.d/CentOS-SCLo-scl-rh.repo"
            if [ -f "$SCL_RH_REPO" ]; then
                # 备份原文件
                if [ ! -f "${SCL_RH_REPO}.backup" ]; then
                    if [ "$EUID" -eq 0 ]; then
                        cp "$SCL_RH_REPO" "${SCL_RH_REPO}.backup" 2>/dev/null || true
                    else
                        sudo cp "$SCL_RH_REPO" "${SCL_RH_REPO}.backup" 2>/dev/null || true
                    fi
                fi

                # 如果找到了镜像源，配置 baseurl
                # 注意：centos-sclo-rh 的路径是 /sclo/$basearch/rh/ 而不是 /sclo/$basearch/sclo-rh/
                if [ -n "$SCL_MIRROR_URL" ] && [ "$SCL_MIRROR_URL" != "" ]; then
                    # 使用 awk 来可靠地修改配置文件
                    TEMP_SCL_RH=$(mktemp)
                    if [ "$EUID" -eq 0 ]; then
                        awk -v mirror_url="$SCL_MIRROR_URL" -v centos_ver="$CENTOS_VERSION" '
                        /\[centos-sclo-rh\]/ { in_section=1; print; next }
                        in_section && /^\[/ { in_section=0 }
                        in_section && /^mirrorlist=/ { print "#" $0; next }
                        in_section && /^#mirrorlist=/ { print; next }
                        in_section && /^baseurl=/ { print "#" $0; next }
                        in_section && /^#baseurl=/ { print; next }
                        in_section && /^name=/ {
                            print
                            print "baseurl=" mirror_url "/" centos_ver "/sclo/\\$basearch/rh/"
                            next
                        }
                        { print }
                        ' "$SCL_RH_REPO" > "$TEMP_SCL_RH" && mv "$TEMP_SCL_RH" "$SCL_RH_REPO" 2>/dev/null || {
                            rm -f "$TEMP_SCL_RH"
                            # 如果 awk 失败，使用 sed 作为备用方案
                            sed -i 's|^mirrorlist=.*|#mirrorlist=|g' "$SCL_RH_REPO" 2>/dev/null || true
                            sed -i 's|^baseurl=.*|#&|g' "$SCL_RH_REPO" 2>/dev/null || true
                            sed -i "/\[centos-sclo-rh\]/,/^\[/ { /^name=.*/a baseurl=$SCL_MIRROR_URL/$CENTOS_VERSION/sclo/\\\$basearch/rh/" "$SCL_RH_REPO" 2>/dev/null || true
                        }
                    else
                        awk -v mirror_url="$SCL_MIRROR_URL" -v centos_ver="$CENTOS_VERSION" '
                        /\[centos-sclo-rh\]/ { in_section=1; print; next }
                        in_section && /^\[/ { in_section=0 }
                        in_section && /^mirrorlist=/ { print "#" $0; next }
                        in_section && /^#mirrorlist=/ { print; next }
                        in_section && /^baseurl=/ { print "#" $0; next }
                        in_section && /^#baseurl=/ { print; next }
                        in_section && /^name=/ {
                            print
                            print "baseurl=" mirror_url "/" centos_ver "/sclo/\\$basearch/rh/"
                            next
                        }
                        { print }
                        ' "$SCL_RH_REPO" > "$TEMP_SCL_RH" && sudo mv "$TEMP_SCL_RH" "$SCL_RH_REPO" 2>/dev/null || {
                            rm -f "$TEMP_SCL_RH"
                            sudo sed -i 's|^mirrorlist=.*|#mirrorlist=|g' "$SCL_RH_REPO" 2>/dev/null || true
                            sudo sed -i 's|^baseurl=.*|#&|g' "$SCL_RH_REPO" 2>/dev/null || true
                            sudo sed -i "/\[centos-sclo-rh\]/,/^\[/ { /^name=.*/a baseurl=$SCL_MIRROR_URL/$CENTOS_VERSION/sclo/\\\$basearch/rh/" "$SCL_RH_REPO" 2>/dev/null || true
                        }
                    fi
                else
                    # 没有找到镜像源，尝试使用 vault.centos.org
                    if [ "$EUID" -eq 0 ]; then
                        sed -i 's|^mirrorlist=.*|#mirrorlist=|g' "$SCL_RH_REPO" 2>/dev/null || true
                        sed -i 's|^#baseurl=http://vault.centos.org|baseurl=http://vault.centos.org/centos/7/sclo/\\$basearch/rh/|g' "$SCL_RH_REPO" 2>/dev/null || true
                    else
                        sudo sed -i 's|^mirrorlist=.*|#mirrorlist=|g' "$SCL_RH_REPO" 2>/dev/null || true
                        sudo sed -i 's|^#baseurl=http://vault.centos.org|baseurl=http://vault.centos.org/centos/7/sclo/\\$basearch/rh/|g' "$SCL_RH_REPO" 2>/dev/null || true
                    fi
                fi
            fi

            # 配置 centos-sclo-sclo 仓库（类似处理）
            SCL_REPO="/etc/yum.repos.d/CentOS-SCLo-scl.repo"
            if [ -f "$SCL_REPO" ]; then
                if [ ! -f "${SCL_REPO}.backup" ]; then
                    if [ "$EUID" -eq 0 ]; then
                        cp "$SCL_REPO" "${SCL_REPO}.backup" 2>/dev/null || true
                    else
                        sudo cp "$SCL_REPO" "${SCL_REPO}.backup" 2>/dev/null || true
                    fi
                fi

                if [ -n "$SCL_MIRROR_URL" ] && [ "$SCL_MIRROR_URL" != "" ]; then
                    # 使用 awk 来可靠地修改配置文件
                    TEMP_SCL=$(mktemp)
                    if [ "$EUID" -eq 0 ]; then
                        awk -v mirror_url="$SCL_MIRROR_URL" -v centos_ver="$CENTOS_VERSION" '
                        /\[centos-sclo-sclo\]/ { in_section=1; print; next }
                        in_section && /^\[/ { in_section=0 }
                        in_section && /^mirrorlist=/ { print "#" $0; next }
                        in_section && /^#mirrorlist=/ { print; next }
                        in_section && /^baseurl=/ { print "#" $0; next }
                        in_section && /^#baseurl=/ { print; next }
                        in_section && /^name=/ {
                            print
                            print "baseurl=" mirror_url "/" centos_ver "/sclo/\\$basearch/sclo/"
                            next
                        }
                        { print }
                        ' "$SCL_REPO" > "$TEMP_SCL" && mv "$TEMP_SCL" "$SCL_REPO" 2>/dev/null || {
                            rm -f "$TEMP_SCL"
                            # 如果 awk 失败，使用 sed 作为备用方案
                            sed -i 's|^mirrorlist=.*|#mirrorlist=|g' "$SCL_REPO" 2>/dev/null || true
                            sed -i 's|^baseurl=.*|#&|g' "$SCL_REPO" 2>/dev/null || true
                            sed -i "/\[centos-sclo-sclo\]/,/^\[/ { /^name=.*/a baseurl=$SCL_MIRROR_URL/$CENTOS_VERSION/sclo/\\\$basearch/sclo/" "$SCL_REPO" 2>/dev/null || true
                        }
                    else
                        awk -v mirror_url="$SCL_MIRROR_URL" -v centos_ver="$CENTOS_VERSION" '
                        /\[centos-sclo-sclo\]/ { in_section=1; print; next }
                        in_section && /^\[/ { in_section=0 }
                        in_section && /^mirrorlist=/ { print "#" $0; next }
                        in_section && /^#mirrorlist=/ { print; next }
                        in_section && /^baseurl=/ { print "#" $0; next }
                        in_section && /^#baseurl=/ { print; next }
                        in_section && /^name=/ {
                            print
                            print "baseurl=" mirror_url "/" centos_ver "/sclo/\\$basearch/sclo/"
                            next
                        }
                        { print }
                        ' "$SCL_REPO" > "$TEMP_SCL" && sudo mv "$TEMP_SCL" "$SCL_REPO" 2>/dev/null || {
                            rm -f "$TEMP_SCL"
                            sudo sed -i 's|^mirrorlist=.*|#mirrorlist=|g' "$SCL_REPO" 2>/dev/null || true
                            sudo sed -i 's|^baseurl=.*|#&|g' "$SCL_REPO" 2>/dev/null || true
                            sudo sed -i "/\[centos-sclo-sclo\]/,/^\[/ { /^name=.*/a baseurl=$SCL_MIRROR_URL/$CENTOS_VERSION/sclo/\\\$basearch/sclo/" "$SCL_REPO" 2>/dev/null || true
                        }
                    fi
                else
                    # 没有找到镜像源，尝试使用 vault.centos.org
                    if [ "$EUID" -eq 0 ]; then
                        sed -i 's|^mirrorlist=.*|#mirrorlist=|g' "$SCL_REPO" 2>/dev/null || true
                        sed -i 's|^#baseurl=http://vault.centos.org|baseurl=http://vault.centos.org/centos/7/sclo/\\$basearch/sclo/|g' "$SCL_REPO" 2>/dev/null || true
                    else
                        sudo sed -i 's|^mirrorlist=.*|#mirrorlist=|g' "$SCL_REPO" 2>/dev/null || true
                        sudo sed -i 's|^#baseurl=http://vault.centos.org|baseurl=http://vault.centos.org/centos/7/sclo/\\$basearch/sclo/|g' "$SCL_REPO" 2>/dev/null || true
                    fi
                fi
            fi

            echo "✓ SCL 仓库镜像源配置完成"

            # 安装 devtoolset-7
            if [ "$EUID" -eq 0 ]; then
                yum install -y devtoolset-7-gcc-c++ devtoolset-7-gcc make
            else
                sudo yum install -y devtoolset-7-gcc-c++ devtoolset-7-gcc make
            fi

            INSTALL_RESULT=$?

            # 如果安装成功，启用 devtoolset-7
            if [ $INSTALL_RESULT -eq 0 ]; then
                echo ""
                echo "配置 devtoolset-7 环境..."
                # 创建激活脚本
                if [ "$EUID" -eq 0 ]; then
                    source /opt/rh/devtoolset-7/enable
                else
                    source /opt/rh/devtoolset-7/enable
                fi

                # 验证 devtoolset-7 的 g++ 是否可用
                if /opt/rh/devtoolset-7/root/usr/bin/g++ -std=c++17 -x c++ -c /dev/null -o /dev/null 2>/dev/null; then
                    echo "✓ devtoolset-7 安装成功且支持 C++17"
                    # 创建符号链接或添加到 PATH（可选，但可能影响系统默认 g++）
                    # 这里我们只验证，不修改系统默认路径
                fi
            fi
        elif [ "$CENTOS_VERSION" -ge 8 ]; then
            # CentOS 8+ 可以安装 gcc-toolset-9 或使用默认的较新版本
            echo ""
            echo "正在安装支持 C++17 的编译器..."
            echo "这可能需要几分钟，请耐心等待..."
            echo ""

            # 先尝试安装 gcc-toolset-9（支持 C++17）
            if [ "$EUID" -eq 0 ]; then
                yum install -y gcc-toolset-9-gcc-c++ gcc-toolset-9-gcc make 2>/dev/null || yum install -y gcc-c++ make
            else
                sudo yum install -y gcc-toolset-9-gcc-c++ gcc-toolset-9-gcc make 2>/dev/null || sudo yum install -y gcc-c++ make
            fi

            INSTALL_RESULT=$?

            # 如果安装了 gcc-toolset-9，启用它
            if [ $INSTALL_RESULT -eq 0 ] && command -v scl &> /dev/null; then
                if [ -f /opt/rh/gcc-toolset-9/enable ]; then
                    source /opt/rh/gcc-toolset-9/enable
                fi
            fi
        else
            # 其他版本，尝试安装默认的 gcc-c++
            echo ""
            echo "正在安装 gcc-c++（包含 g++ 编译器）..."
            echo "这可能需要几分钟，请耐心等待..."
            echo ""

            if [ "$EUID" -eq 0 ]; then
                yum install -y gcc-c++ make
            else
                sudo yum install -y gcc-c++ make
            fi

            INSTALL_RESULT=$?
        fi
        ;;

    "debian")
        echo ""
        echo "配置 Debian/Ubuntu apt 镜像源..."

        # 检测并选择可用的镜像源
        MIRROR_SELECTED=0

        # 1. 尝试阿里云镜像
        echo "正在测试阿里云镜像源..."
        if timeout 5 curl -I --connect-timeout 3 https://mirrors.aliyun.com >/dev/null 2>&1; then
            echo "✓ 可以访问阿里云镜像源"
            MIRROR_SELECTED=1
            USE_MIRROR="aliyun"
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
        else
            echo "✗ 无法访问测试的镜像源，将使用系统默认源"
            USE_MIRROR="default"
        fi

        # 检测 Ubuntu 还是 Debian
        if [ -f /etc/lsb-release ]; then
            . /etc/lsb-release
            DISTRO="ubuntu"
            CODENAME=$(lsb_release -cs)
        else
            DISTRO="debian"
            CODENAME=$(cat /etc/debian_version | cut -d. -f1)
            if [ "$CODENAME" = "bookworm" ] || [ "$CODENAME" = "12" ]; then
                CODENAME="bookworm"
            elif [ "$CODENAME" = "bullseye" ] || [ "$CODENAME" = "11" ]; then
                CODENAME="bullseye"
            elif [ "$CODENAME" = "buster" ] || [ "$CODENAME" = "10" ]; then
                CODENAME="buster"
            else
                CODENAME="stable"
            fi
        fi

        # 配置 apt 镜像源（如果需要）
        if [ "$USE_MIRROR" != "default" ] && [ "$MIRROR_SELECTED" -eq 1 ]; then
            echo ""
            echo "配置 apt 使用 $USE_MIRROR 镜像源..."

            case "$USE_MIRROR" in
                "aliyun")
                    if [ "$DISTRO" = "ubuntu" ]; then
                        MIRROR_URL="https://mirrors.aliyun.com/ubuntu"
                    else
                        MIRROR_URL="https://mirrors.aliyun.com/debian"
                    fi
                    ;;
                "tsinghua")
                    if [ "$DISTRO" = "ubuntu" ]; then
                        MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
                    else
                        MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/debian"
                    fi
                    ;;
                "ustc")
                    if [ "$DISTRO" = "ubuntu" ]; then
                        MIRROR_URL="https://mirrors.ustc.edu.cn/ubuntu"
                    else
                        MIRROR_URL="https://mirrors.ustc.edu.cn/debian"
                    fi
                    ;;
            esac

            # 备份原始 sources.list
            if [ ! -f /etc/apt/sources.list.backup ]; then
                if [ "$EUID" -eq 0 ]; then
                    cp /etc/apt/sources.list /etc/apt/sources.list.backup 2>/dev/null || true
                else
                    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup 2>/dev/null || true
                fi
            fi

            # 创建新的 sources.list（简化版本，实际可能需要更复杂的配置）
            echo "提示: 如需配置镜像源，请手动编辑 /etc/apt/sources.list"
            echo "镜像 URL: $MIRROR_URL"
        fi

        echo ""
        echo "正在更新软件包列表..."
        if [ "$EUID" -eq 0 ]; then
            apt-get update
        else
            sudo apt-get update
        fi

        echo ""
        echo "正在安装 g++ 编译器..."
        echo "这可能需要几分钟，请耐心等待..."
        echo ""

        # 安装 g++
        if [ "$EUID" -eq 0 ]; then
            apt-get install -y g++ make build-essential
        else
            sudo apt-get install -y g++ make build-essential
        fi

        INSTALL_RESULT=$?
        ;;

    *)
        echo ""
        echo "无法自动识别系统类型，请手动安装 g++"
        echo ""
        echo "CentOS/RHEL: sudo yum install -y gcc-c++"
        echo "Debian/Ubuntu: sudo apt-get install -y g++"
        exit 1
        ;;
esac

# 验证安装结果
if [ $INSTALL_RESULT -eq 0 ]; then
    echo ""
    echo "验证 g++ 版本和 C++17 支持..."

    # 检查多个可能的 g++ 路径（按优先级）
    GXX_FOUND=0
    GXX_PATH=""

    # 1. 检查 devtoolset-7 的 g++
    if [ -f /opt/rh/devtoolset-7/root/usr/bin/g++ ]; then
        if /opt/rh/devtoolset-7/root/usr/bin/g++ -std=c++17 -x c++ -c /dev/null -o /dev/null 2>/dev/null; then
            GXX_FOUND=1
            GXX_PATH="/opt/rh/devtoolset-7/root/usr/bin/g++"
            source /opt/rh/devtoolset-7/enable 2>/dev/null || true
        fi
    fi

    # 2. 检查 gcc-toolset-9 的 g++
    if [ $GXX_FOUND -eq 0 ] && [ -f /opt/rh/gcc-toolset-9/root/usr/bin/g++ ]; then
        if /opt/rh/gcc-toolset-9/root/usr/bin/g++ -std=c++17 -x c++ -c /dev/null -o /dev/null 2>/dev/null; then
            GXX_FOUND=1
            GXX_PATH="/opt/rh/gcc-toolset-9/root/usr/bin/g++"
            source /opt/rh/gcc-toolset-9/enable 2>/dev/null || true
        fi
    fi

    # 3. 检查系统默认的 g++
    if [ $GXX_FOUND -eq 0 ] && command -v g++ &> /dev/null; then
        if g++ -std=c++17 -x c++ -c /dev/null -o /dev/null 2>/dev/null; then
            GXX_FOUND=1
            GXX_PATH=$(command -v g++)
        fi
    fi

    # 验证结果
    if [ $GXX_FOUND -eq 1 ]; then
        echo ""
        echo "=========================================="
        echo "✓ g++ 安装成功！"
        echo "=========================================="
        echo ""

        # 使用找到的 g++ 显示版本信息
        if [ -n "$GXX_PATH" ]; then
            echo "g++ 路径: $GXX_PATH"
            echo "g++ 版本信息:"
            "$GXX_PATH" --version | head -n 1
        else
            echo "g++ 版本信息:"
            g++ --version | head -n 1
        fi
        echo ""
        echo "✓ 系统的 g++ 支持 C++17"
        echo ""

        # 如果是通过 devtoolset 或 gcc-toolset 安装的，给出使用提示
        if [ "$OS_TYPE" = "centos" ]; then
            CENTOS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
            if [ "$CENTOS_VERSION" -eq 7 ] && [ -f /opt/rh/devtoolset-7/enable ]; then
                echo "注意: 使用了 devtoolset-7 的 g++ (GCC 7.3.1，支持 C++17)"
                echo ""
                echo "为什么需要启用 devtoolset-7？"
                echo "  devtoolset-7 是 Software Collections (SCL) 的一部分，它不会替换系统默认的 g++"
                echo "  系统默认的 g++ 仍然是 4.8.5（不支持 C++17）"
                echo "  devtoolset-7 的 g++ 安装在: /opt/rh/devtoolset-7/root/usr/bin/g++"
                echo "  需要启用后，才会将 devtoolset-7 的路径添加到 PATH 前面"
                echo ""
                echo "要在当前 shell 中使用支持 C++17 的 g++，请运行:"
                echo "  source /opt/rh/devtoolset-7/enable"
                echo ""
                echo "要永久启用（每次登录自动生效），请在 ~/.bashrc 中添加:"
                echo "  source /opt/rh/devtoolset-7/enable"
                echo ""
                echo "验证方法:"
                echo "  source /opt/rh/devtoolset-7/enable"
                echo "  which g++  # 应该显示 /opt/rh/devtoolset-7/root/usr/bin/g++"
                echo "  g++ --version  # 应该显示 GCC 7.3.1"
            elif [ "$CENTOS_VERSION" -ge 8 ] && [ -f /opt/rh/gcc-toolset-9/enable ]; then
                echo "注意: 使用了 gcc-toolset-9 的 g++ (支持 C++17)"
                echo ""
                echo "为什么需要启用 gcc-toolset-9？"
                echo "  gcc-toolset-9 是 Software Collections (SCL) 的一部分，它不会替换系统默认的 g++"
                echo "  需要启用后，才会将 gcc-toolset-9 的路径添加到 PATH 前面"
                echo ""
                echo "要在当前 shell 中使用支持 C++17 的 g++，请运行:"
                echo "  source /opt/rh/gcc-toolset-9/enable"
                echo ""
                echo "要永久启用（每次登录自动生效），请在 ~/.bashrc 中添加:"
                echo "  source /opt/rh/gcc-toolset-9/enable"
                echo ""
                echo "验证方法:"
                echo "  source /opt/rh/gcc-toolset-9/enable"
                echo "  which g++  # 应该显示 /opt/rh/gcc-toolset-9/root/usr/bin/g++"
                echo "  g++ --version  # 应该显示 GCC 9.x"
            fi
        fi

        exit 0
    else
        echo ""
        echo "=========================================="
        echo "✗ 警告: g++ 已安装但不支持 C++17"
        echo "=========================================="
        echo ""
        echo "marisa-trie 等包需要 C++17 支持（需要 GCC 7+）"
        if command -v g++ &> /dev/null; then
            echo "当前 g++ 版本：$(g++ --version | head -1)"
        fi
        echo ""
        echo "解决方案："
        echo "  需要升级 g++ 到支持 C++17 的版本（GCC 7+）"
        echo ""
        if [ "$OS_TYPE" = "centos" ]; then
            CENTOS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
            if [ "$CENTOS_VERSION" -eq 7 ]; then
                echo "  CentOS 7 需要安装 devtoolset-7:"
                echo "    sudo yum install -y centos-release-scl"
                echo "    sudo yum install -y devtoolset-7-gcc-c++"
                echo "    source /opt/rh/devtoolset-7/enable"
            else
                echo "  CentOS/RHEL 8+:"
                echo "    sudo yum install -y gcc-toolset-9-gcc-c++"
                echo "    source /opt/rh/gcc-toolset-9/enable"
            fi
        elif [ "$OS_TYPE" = "debian" ]; then
            echo "  Debian/Ubuntu:"
            echo "    确保安装的 g++ 版本 >= 7"
            echo "    g++ --version"
        fi
        echo ""
        echo "  或使用 conda 安装："
        echo "    conda install -y -c conda-forge cxx-compiler c-compiler"
        echo ""
        exit 1
    fi
else
    echo ""
    echo "=========================================="
    echo "✗ g++ 安装失败"
    echo "=========================================="
    echo ""
    echo "可能的原因："
    echo "  1. 网络连接中断或不稳定"
    echo "  2. 无法访问软件源（DNS 解析失败或防火墙阻止）"
    echo "  3. 权限不足（需要 root 或 sudo 权限）"
    echo "  4. 磁盘空间不足"
    echo "  5. 软件源配置错误"
    echo ""
    echo "解决方案："
    echo ""
    echo "方案 1: 手动安装"
    if [ "$OS_TYPE" = "centos" ]; then
        echo "  sudo yum install -y gcc-c++ make"
    elif [ "$OS_TYPE" = "debian" ]; then
        echo "  sudo apt-get update"
        echo "  sudo apt-get install -y g++ make build-essential"
    fi
    echo ""
    echo "方案 2: 检查网络连接和镜像源配置"
    echo "  确保可以访问软件源服务器"
    echo ""
    echo "方案 3: 使用系统默认源"
    echo "  如果镜像源配置有问题，可以恢复原始配置："
    if [ "$OS_TYPE" = "centos" ]; then
        echo "  sudo cp /etc/yum.repos.d/CentOS-Base.repo.backup /etc/yum.repos.d/CentOS-Base.repo"
    elif [ "$OS_TYPE" = "debian" ]; then
        echo "  sudo cp /etc/apt/sources.list.backup /etc/apt/sources.list"
        echo "  sudo apt-get update"
    fi
    echo ""
    exit 1
fi

