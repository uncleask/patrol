#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")
LOG_FILE="$SCRIPT_DIR/logs/install.log"

# 日志函数
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] INFO: $1" >> "$LOG_FILE"
    echo "[$timestamp] INFO: $1"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" >> "$LOG_FILE"
    echo "[$timestamp] ERROR: $1" >&2
}

# 错误处理函数
error_exit() {
    log_error "$1"
    exit 1
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# 下载 jq
download_jq() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) echo "Unsupported architecture: $arch"; exit 1 ;;
    esac
    
    local jq_url="https://github.com/jqlang/jq/releases/download/jq-1.7/jq-${os}-${arch}"
    local jq_binary="$SCRIPT_DIR/bin/jq-${os}-${arch}"
    
    log_info "Downloading jq from $jq_url"
    
    if check_command curl; then
        curl -s -o "$jq_binary" "$jq_url"
    elif check_command wget; then
        wget -q -O "$jq_binary" "$jq_url"
    else
        error_exit "wget or curl required"
    fi
    
    chmod +x "$jq_binary"
    
    # 创建符号链接
    ln -sf "$jq_binary" "$SCRIPT_DIR/bin/jq"
    
    log_info "jq installed to $jq_binary"
}

# 检查并下载 jq
install_jq() {
    # 1. 优先使用系统安装的 jq
    if check_command jq; then
        log_info "jq 命令已找到"
        return 0
    fi
    
    # 2. 检测当前系统架构
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) arch="amd64" ;;
    esac
    
    local jq_binary="$SCRIPT_DIR/bin/jq-${os}-${arch}"
    
    # 3. 检查本地对应架构的 jq
    if [ -f "$jq_binary" ] && [ -x "$jq_binary" ]; then
        log_info "本地 jq 已存在: $jq_binary"
        return 0
    fi
    
    # 4. 检查通用 jq
    if [ -f "$SCRIPT_DIR/bin/jq" ] && [ -x "$SCRIPT_DIR/bin/jq" ]; then
        log_info "本地 jq 已存在: $SCRIPT_DIR/bin/jq"
        return 0
    fi
    
    # 5. 下载 jq
    download_jq
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."
    
    local dirs=(conf logs bin web)
    for dir in "${dirs[@]}"; do
        local dir_path="$SCRIPT_DIR/$dir"
        if [ ! -d "$dir_path" ]; then
            mkdir -p "$dir_path"
            log_info "创建目录: $dir_path"
        else
            log_info "目录已存在: $dir_path"
        fi
    done
    
    # 创建 web 子目录
    local web_dirs=(web/css web/js web/data web/demo_data)
    for dir in "${web_dirs[@]}"; do
        local dir_path="$SCRIPT_DIR/$dir"
        if [ ! -d "$dir_path" ]; then
            mkdir -p "$dir_path"
            log_info "创建目录: $dir_path"
        else
            log_info "目录已存在: $dir_path"
        fi
    done
}

# 创建配置文件示例
create_config_examples() {
    log_info "创建配置文件示例..."
    
    # servers.conf.example
    local servers_conf="$SCRIPT_DIR/conf/servers.conf.example"
    if [ ! -f "$servers_conf" ]; then
        cat > "$servers_conf" <<EOF
# 服务器配置文件
# 格式：别名:IP:端口:用户名:私钥路径:密码（可选）:检查项分组（可选）
# 示例：
web01:192.168.1.10:22:root:/home/patrol/.autopriv/patrol_rsa::group_1_1
db01:192.168.1.20:22:mysqluser:/home/patrol/.autopriv/patrol_rsa:mypassword:group_1_2
EOF
        log_info "创建配置文件示例: $servers_conf"
    else
        log_info "配置文件示例已存在: $servers_conf"
    fi
    
    # checks.conf.example
    local checks_conf="$SCRIPT_DIR/conf/checks.conf.example"
    if [ ! -f "$checks_conf" ]; then
        cat > "$checks_conf" <<EOF
# 检查项配置文件
# 格式：检查项名称:类型:执行命令
# 说明：所有命令输出原始结果，由中心机解析

# ============ 系统基础信息 ============
system:system:cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '\"'
kernel:system:uname -r
architecture:system:uname -m
uptime:system:uptime

# ============ CPU 信息 ============
cpu:cpu:top -bn1 | grep 'Cpu(s)'
loadavg:system:uptime

# ============ 内存信息 ============
mem:mem:free -m
swap:swap:free -m

# ============ 磁盘信息 ============
disk:disk:df -h
disk_root:disk:df -h /
disk_home:disk:df -h /home
disk_backups:disk:df -h /backups
disk_nas:disk:df -h /mnt/nas

# ============ 详细信息检查 ============
basic_info:detail:cat /etc/os-release
cpu_detail:detail:top -bn1 | head -20
memory_detail:detail:free -m -h
disk_detail:detail:df -h
apps_info:detail:ps aux | head -30
dockers_info:detail:docker ps -a

# ============ 进程检查 ============
nginx:vhost:ps aux | grep -E "(nginx|nginx:)" | grep -v grep
mysql:vhost:ps aux | grep -E "(mysqld|mysql)" | grep -v grep
redis:vhost:ps aux | grep redis-server | grep -v grep
zookeeper:vhost:ps aux | grep -E "(zookeeper|QuorumPeerMain)" | grep -v grep
memcached:vhost:ps aux | grep memcached | grep -v grep
syslog:vhost:ps aux | grep syslogd | grep -v grep
BT_Panel:vhost:ps aux | grep BT-Panel | grep -v grep
BT_Task:vhost:ps aux | grep BT-Task | grep -v grep

# ============ Docker检查 ============
kafka:docker:docker ps --filter "name=kafka"
oracle_19c:docker:docker ps --filter "name=oracle"
opengauss:docker:docker ps --filter "name=opengauss"
cordys-crm:docker:docker ps --filter "name=cordys-crm"
EOF
        log_info "创建配置文件示例: $checks_conf"
    else
        log_info "配置文件示例已存在: $checks_conf"
    fi
    
    # check_groups.conf.example
    local check_groups_conf="$SCRIPT_DIR/conf/check_groups.conf.example"
    if [ ! -f "$check_groups_conf" ]; then
        cat > "$check_groups_conf" <<EOF
# 检查项分组配置文件
# 格式：分组名:检查项1,检查项2,...

# 192.168.1.1 主机检查项分组
group_1_1:nginx,system,kernel,uptime

# 192.168.1.2 主机检查项分组
group_1_2:mysql,redis,memcached,system,kernel,uptime

# 192.168.1.3 主机检查项分组
group_1_3:system,kernel,uptime

# 192.168.1.4 主机检查项分组
group_1_4:system,kernel,uptime

# 通用检查项分组
group_system:system,kernel,architecture,uptime
group_resource:cpu,loadavg,mem,swap,disk,disk_root,disk_home
group_apps:nginx,mysql,redis,memcached
group_docker:kafka,oracle_19c,opengauss,cordys-crm
EOF
        log_info "创建配置文件示例: $check_groups_conf"
    else
        log_info "配置文件示例已存在: $check_groups_conf"
    fi
    
    # 创建默认演示数据
    local default_out="$SCRIPT_DIR/web/demo_data/default.out"
    if [ ! -f "$default_out" ]; then
        echo "这是默认输出" > "$default_out"
        log_info "创建默认演示数据: $default_out"
    else
        log_info "默认演示数据已存在: $default_out"
    fi
}

# 创建全局软链接
create_symlink() {
    if [ "$EUID" -eq 0 ]; then
        log_info "创建全局软链接..."
        local symlink_path="/usr/local/bin/patrol"
        local target_path="$SCRIPT_DIR/patrol.sh"
        
        if [ -L "$symlink_path" ]; then
            rm -f "$symlink_path"
        fi
        
        ln -s "$target_path" "$symlink_path"
        log_info "创建软链接: $symlink_path -> $target_path"
    else
        log_info "非 root 用户，跳过创建全局软链接"
    fi
}

# 打印 SSH 密钥生成指引
print_ssh_guide() {
    # 创建默认的密钥存储目录
    local key_dir="$HOME/patrol/.autopriv"
    if [ ! -d "$key_dir" ]; then
        mkdir -p "$key_dir"
        log_info "创建密钥存储目录: $key_dir"
    fi
    
    log_info "SSH 密钥生成指引："
    echo ""
    echo "========================================"
    echo "SSH 密钥生成指引"
    echo "========================================"
    echo "1. 生成 SSH 密钥对："
    echo "   ssh-keygen -t rsa -b 2048 -f $key_dir/patrol_rsa"
    echo ""
    echo "2. 推送公钥到目标服务器："
    echo "   ssh-copy-id -i $key_dir/patrol_rsa.pub user@server"
    echo ""
    echo "3. 在 servers.conf 中配置私钥路径："
    echo "   alias:ip:port:user:$key_dir/patrol_rsa:"
    echo "========================================"
    echo ""
}

# 主函数
main() {
    echo "开始安装 Patrol 系统巡检工具..."
    
    # 检查必要命令
    log_info "检查必要命令..."
    
    if ! check_command ssh; then
        error_exit "未找到 ssh 命令，请安装 OpenSSH"
    fi
    log_info "ssh 命令已找到"
    
    # 检查 sshpass（可选）
    if check_command sshpass; then
        log_info "sshpass 命令已找到"
    else
        log_info "未找到 sshpass 命令，将使用密钥认证"
    fi
    
    # 检查或安装 jq
    if check_command jq; then
        log_info "jq 命令已找到"
    else
        install_jq
    fi
    
    # 创建目录结构
    create_directories
    
    # 创建密钥存储目录
    local key_dir="$HOME/patrol/.autopriv"
    if [ ! -d "$key_dir" ]; then
        mkdir -p "$key_dir"
        log_info "创建密钥存储目录: $key_dir"
    else
        log_info "密钥存储目录已存在: $key_dir"
    fi
    
    # 创建配置文件示例
    create_config_examples
    
    # 创建全局软链接
    create_symlink
    
    # 打印 SSH 密钥生成指引
    print_ssh_guide
    
    log_info "安装完成！"
    echo ""
    echo "========================================"
    echo "Patrol 系统巡检工具安装完成"
    echo "========================================"
    echo "使用方法："
    echo "1. 生成 SSH 密钥对："
    echo "   ssh-keygen -t rsa -b 2048 -f $key_dir/patrol_rsa"
    echo ""
    echo "2. 推送公钥到目标服务器："
    echo "   ssh-copy-id -i $key_dir/patrol_rsa.pub user@server"
    echo ""
    echo "3. 复制配置文件示例并修改："
    echo "   cp conf/servers.conf.example conf/servers.conf"
    echo "   cp conf/checks.conf.example conf/checks.conf"
    echo "   cp conf/check_groups.conf.example conf/check_groups.conf"
    echo ""
    echo "4. 运行巡检："
    echo "   ./patrol.sh"
    echo ""
    echo "5. 运行演示模式："
    echo "   ./patrol.sh --demo"
    echo ""
    echo "6. 运行 Web 服务："
    echo "   cd web && python -m http.server 8000"
    echo "========================================"
}

# 运行主函数
main
