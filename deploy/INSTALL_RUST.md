# Rust 编译器安装指南

## 问题说明

`tiktoken` 包需要 Rust 编译器从源码编译。如果自动安装失败（通常是网络问题），请手动安装。

## 方法 1: 使用脚本检查rust版本并安装

```bash
# 标准安装
conda activate dbgpt
source /home/datagroup/projects/DB-GPT/deploy/check_rust.sh

# 验证安装
rustc --version
cargo --version
#
```



## 安装后配置

安装完成后，需要确保 Rust 在 PATH 中：

```bash
# 添加到 ~/.bashrc（如果还没有）
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

# 重新加载配置
source ~/.bashrc
```

## 验证安装

```bash
rustc --version
cargo --version
rustup show
```

## 故障排查

### 问题 1: 网络超时

如果下载一直卡住：
1. 检查网络连接
2. 使用国内镜像源
3. 检查是否需要配置代理

### 问题 2: 权限问题

```bash
# 确保有写入权限
ls -ld ~/.cargo ~/.rustup 2>/dev/null
# 如果没有，可能需要：
chown -R $USER:$USER ~/.cargo ~/.rustup
```

### 问题 3: 清理后重新安装

如果安装不完整：
```bash
# 卸载 Rust
rustup self uninstall

# 或手动删除
rm -rf ~/.cargo ~/.rustup

# 清理临时文件
rm -rf /tmp/tmp.*/rustup-init
```


