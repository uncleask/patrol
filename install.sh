#!/bin/bash

# 安装脚本 - Patrol 系统巡检工具

# 获取脚本所在目录
SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

echo "=== Patrol 系统巡检工具安装 ==="

# 设置脚本执行权限
echo "1. 设置脚本执行权限..."
chmod +x patrol.sh remote_check.sh

# 检查依赖工具
echo "\n2. 检查依赖工具..."
dependencies=(ssh scp jq vmstat free df ps awk)
missing_deps=()

for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        missing_deps+=("$dep")
    else
        echo "✓ $dep 已安装"
    fi
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo "\n⚠️  以下依赖工具未安装:"
    for dep in "${missing_deps[@]}"; do
        echo "  - $dep"
    done
    echo "\n请安装这些依赖工具后再运行巡检工具"
else
    echo "\n✓ 所有依赖工具已安装"
fi

# 检查 jq 工具
echo "\n3. 检查 jq 工具..."
if ! command -v jq &> /dev/null; then
    echo "⚠️  jq 工具未安装，尝试从 bin 目录复制..."
    if [[ -f "bin/jq" ]]; then
        cp bin/jq /usr/local/bin/ 2>/dev/null || echo "⚠️  无法复制 jq 到 /usr/local/bin/，请手动安装"
    else
        echo "⚠️  bin/jq 文件不存在，请手动安装 jq"
    fi
else
    echo "✓ jq 已安装"
fi

# 创建必要的目录
echo "\n4. 创建必要的目录..."
mkdir -p output logs web

# 配置文件说明
echo "\n5. 配置文件说明..."
echo "请根据实际情况修改以下配置文件:"
echo "  - conf/servers.conf    # 服务器配置"
echo "  - conf/check_groups.conf  # 检查组配置"
echo "  - conf/checks.conf     # 检查项配置"

# SSH 免密登录设置
echo "\n6. SSH 免密登录设置..."
SSH_KEY_DIR="$SCRIPT_DIR/.ssh"
SSH_KEY_FILE="$SSH_KEY_DIR/id_rsa"

# 检查是否存在 SSH 密钥对
if [[ ! -f "$SSH_KEY_FILE" ]]; then
    echo "⚠️  未找到 SSH 密钥对，正在生成..."
    mkdir -p "$SSH_KEY_DIR"
    ssh-keygen -t rsa -b 2048 -f "$SSH_KEY_FILE" -N "" > /dev/null 2>&1
    echo "✓ SSH 密钥对生成成功"
else
    echo "✓ SSH 密钥对已存在"
fi

# 显示公钥内容
echo "\n7. SSH 公钥 (用于测试设备免密登录):"
echo "--------------------------------------------------"
cat "$SSH_KEY_FILE.pub"
echo "--------------------------------------------------"
echo "\n请将以上公钥添加到测试设备的 ~/.ssh/authorized_keys 文件中"
echo "例如: ssh-copy-id -i $SSH_KEY_FILE.pub user@hostname"

# 更新 servers.conf 配置
echo "\n8. 更新 servers.conf 配置..."
if [[ -f "conf/servers.conf" ]]; then
    # 备份原始配置文件
    cp "conf/servers.conf" "conf/servers.conf.bak"
    # 更新密钥路径
    sed -i "s|::password|:$SSH_KEY_FILE:password|g" "conf/servers.conf"
    echo "✓ servers.conf 配置已更新，密钥路径: $SSH_KEY_FILE"
else
    echo "⚠️  conf/servers.conf 文件不存在，无法更新配置"
fi

echo "\n=== 安装完成 ==="
echo "使用方法: ./patrol.sh [选项]"
echo "查看帮助: ./patrol.sh --help"
