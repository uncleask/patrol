#!/bin/bash

# ============================================
# 系统巡检主脚本
# 功能：自动巡检多台服务器，生成 HTML 和 TXT 报告
# ============================================

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 配置目录
CONF_DIR="$SCRIPT_DIR/conf"

# 输出目录（改为 web/data 目录）
OUTPUT_DIR="$SCRIPT_DIR/web/data"

# 日志目录
LOGS_DIR="$SCRIPT_DIR/logs"

# 确保目录存在
mkdir -p "$OUTPUT_DIR" "$LOGS_DIR"

# 默认配置文件
SERVERS_FILE="$CONF_DIR/servers.conf"
GROUPS_FILE="$CONF_DIR/check_groups.conf"
CHECKS_FILE="$CONF_DIR/checks.conf"

# 默认并发数
PARALLEL=4

# Demo模式
DEMO_MODE=false
DEMO_DATA_FILE="$SCRIPT_DIR/web/demo_data/demo_patrol.json"

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >&2; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2; }

# 解析配置文件路径（支持相对路径和 conf 目录自动补全）
resolve_config_path() {
    local config_file="$1"
    
    # 如果是绝对路径，直接返回
    if [[ "$config_file" = /* ]]; then
        echo "$config_file"
        return
    fi
    
    # 如果文件存在于当前路径，使用当前路径
    if [ -f "$SCRIPT_DIR/$config_file" ]; then
        echo "$SCRIPT_DIR/$config_file"
        return
    fi
    
    # 如果文件存在于 conf 目录，使用 conf 目录
    if [ -f "$CONF_DIR/$config_file" ]; then
        echo "$CONF_DIR/$config_file"
        return
    fi
    
    # 默认返回原始路径（后续会报错文件不存在）
    echo "$SCRIPT_DIR/$config_file"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --servers=*)
            SERVERS_FILE=$(resolve_config_path "${1#*=}")
            ;;
        --groups=*)
            GROUPS_FILE=$(resolve_config_path "${1#*=}")
            ;;
        --checks=*)
            CHECKS_FILE=$(resolve_config_path "${1#*=}")
            ;;
        --demo)
            DEMO_MODE=true
            ;;
        *)
            log_error "Unknown parameter: $1"
            exit 1
            ;;
    esac
    shift
done

log_info "Using configuration files:"
log_info "  Servers: $SERVERS_FILE"
log_info "  Groups: $GROUPS_FILE"
log_info "  Checks: $CHECKS_FILE"

# ============ 查找 jq 工具 ============
find_jq() {
    # 1. 优先使用系统安装的 jq
    if command -v jq &>/dev/null; then
        echo "$(command -v jq)"
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
    
    # 3. 使用本地对应架构的 jq
    if [ -f "$jq_binary" ] && [ -x "$jq_binary" ]; then
        echo "$jq_binary"
        return 0
    fi
    
    # 4. 尝试通用 jq
    if [ -f "$SCRIPT_DIR/bin/jq" ] && [ -x "$SCRIPT_DIR/bin/jq" ]; then
        echo "$SCRIPT_DIR/bin/jq"
        return 0
    fi
    
    log_error "jq not found"
    return 1
}

JQ_PATH=$(find_jq)
if [ -z "$JQ_PATH" ]; then
    log_error "jq not found or failed to download"
    exit 1
fi
log_info "found jq: $JQ_PATH"

# ============ 全局变量声明 ============
declare -A SERVER_IP SERVER_PORT SERVER_USER SERVER_KEY SERVER_PASSWORD SERVER_GROUP
declare -A GROUP_CHECKS
declare -A CHECK_TYPE CHECK_COMMAND
declare -A THRESHOLDS
SERVERS=()
GROUP_NAMES=()

# ============ 解析服务器配置 ============
parse_servers() {
    [ ! -f "$SERVERS_FILE" ] && { log_error "$SERVERS_FILE not found"; return 1; }
    
    SERVERS=()
    while IFS=':' read -r alias ip port user key password group; do
        [[ -z "$alias" || "$alias" =~ ^# ]] && continue
        SERVERS+=($alias)
        SERVER_IP["$alias"]="$ip"
        SERVER_PORT["$alias"]="$port"
        SERVER_USER["$alias"]="$user"
        SERVER_KEY["$alias"]="$key"
        SERVER_PASSWORD["$alias"]="$password"
        SERVER_GROUP["$alias"]="$group"
        log_info "loaded: $alias ($ip)"
    done < "$SERVERS_FILE"
    log_info "total: ${#SERVERS[@]} servers"
}

# ============ 解析分组配置 ============
parse_groups() {
    [ ! -f "$GROUPS_FILE" ] && { log_error "$GROUPS_FILE not found"; return 1; }
    
    GROUP_NAMES=()
    while IFS=':' read -r group checks; do
        [[ -z "$group" || "$group" =~ ^# ]] && continue
        GROUP_NAMES+=("$group")
        GROUP_CHECKS["$group"]="$checks"
    done < "$GROUPS_FILE"
    log_info "loaded ${#GROUP_NAMES[@]} groups"
}

# ============ 解析检查项配置（包含阈值） ============
parse_checks() {
    [ ! -f "$CHECKS_FILE" ] && { log_error "$CHECKS_FILE not found"; return 1; }
    
    while IFS=':' read -r name type value; do
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        
        if [[ "$name" == "threshold" ]]; then
            # threshold:cpu:70,85
            local warn=$(echo "$value" | cut -d',' -f1)
            local serious=$(echo "$value" | cut -d',' -f2)
            THRESHOLDS["${type}_warn"]="$warn"
            THRESHOLDS["${type}_serious"]="$serious"
        else
            CHECK_TYPE["$name"]="$type"
            CHECK_COMMAND["$name"]="$value"
        fi
    done < "$CHECKS_FILE"
}

# ============ 生成主机配置（包含阈值、磁盘、应用） ============
generate_host_config() {
    local group="$1"
    local checks="${GROUP_CHECKS[$group]}"
    
    [ -z "$checks" ] && { log_error "group $group not found"; return 1; }
    
    local config=""
    
    # 1. 写入阈值配置（使用 $'\n' 或直接 echo）
    config+="# ============ 阈值配置 ============"$'\n'
    config+="threshold:cpu:${THRESHOLDS[cpu_warn]:-70},${THRESHOLDS[cpu_serious]:-85}"$'\n'
    config+="threshold:mem:${THRESHOLDS[mem_warn]:-70},${THRESHOLDS[mem_serious]:-85}"$'\n'
    config+=$'\n'
    
    # 2. 写入磁盘阈值
    config+="# ============ 磁盘阈值 ============"$'\n'
    IFS=',' read -ra check_list <<< "$checks"
    for check_name in "${check_list[@]}"; do
        local type="${CHECK_TYPE[$check_name]}"
        if [[ "$type" == "disk" ]]; then
            local warn="${THRESHOLDS[${check_name}_warn]:-78}"
            local serious="${THRESHOLDS[${check_name}_serious]:-90}"
            config+="threshold:${check_name}:${warn},${serious}"$'\n'
        fi
    done
    config+=$'\n'
    
    # 3. 写入磁盘命令
    config+="# ============ 磁盘命令 ============"$'\n'
    for check_name in "${check_list[@]}"; do
        local type="${CHECK_TYPE[$check_name]}"
        local cmd="${CHECK_COMMAND[$check_name]}"
        if [[ "$type" == "disk" ]]; then
            config+="${check_name}:disk:${cmd}"$'\n'
        fi
    done
    config+=$'\n'
    
    # 4. 写入应用配置
    config+="# ============ 应用配置 ============"$'\n'
    for check_name in "${check_list[@]}"; do
        local type="${CHECK_TYPE[$check_name]}"
        local cmd="${CHECK_COMMAND[$check_name]}"
        if [[ "$type" == "vhost" || "$type" == "docker" ]]; then
            config+="${check_name}:${type}:${cmd}"$'\n'
        fi
    done
    
    echo "$config"
}

# ============ 确保远程环境就绪 ============
ensure_remote_ready() {
    local ip="$1" port="$2" user="$3" key="$4" password="$5"
    
    local ssh_cmd scp_cmd
    local auth_success=false
    
    if [ -n "$key" ] && [ -f "$key" ]; then
        ssh_cmd="ssh -p $port -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i $key"
        scp_cmd="scp -P $port -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i $key"
        auth_success=true
    elif [ -n "$password" ]; then
        if command -v sshpass &>/dev/null; then
            ssh_cmd="sshpass -p $password ssh -p $port -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
            scp_cmd="sshpass -p $password scp -P $port -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
            auth_success=true
        elif command -v expect &>/dev/null; then
            # 使用 expect 进行密码认证
            local temp_expect=$(mktemp)
            cat > "$temp_expect" << 'EOF'
#!/usr/bin/expect -f
set timeout 30
set ip [lindex $argv 0]
set port [lindex $argv 1]
set user [lindex $argv 2]
set password [lindex $argv 3]
set command [lindex $argv 4]

spawn ssh -p $port $user@$ip $command
expect {
    "password:" {
        send "$password\r"
        expect eof
    }
    "Are you sure you want to continue connecting" {
        send "yes\r"
        expect "password:" {
            send "$password\r"
            expect eof
        }
    }
    eof {}
}
EOF
            chmod +x "$temp_expect"
            
            # 测试连接
            "$temp_expect" "$ip" "$port" "$user" "$password" "echo test" > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                auth_success=true
                # 对于 expect，我们需要特殊处理
                export EXPECT_SSH_SCRIPT="$temp_expect"
            fi
        fi
    fi
    
    if [ "$auth_success" != "true" ]; then
        log_error "no auth method for $ip"
        return 1
    fi
    
    # 获取远程 home 目录
    local remote_home
    if [ -n "$EXPECT_SSH_SCRIPT" ]; then
        remote_home=$($EXPECT_SSH_SCRIPT "$ip" "$port" "$user" "$password" "echo \$HOME" 2>&1 | tail -n 1)
    else
        remote_home=$($ssh_cmd "$user@$ip" "echo \$HOME" 2>/dev/null)
    fi
    
    [ -z "$remote_home" ] && { log_error "failed to get remote home for $ip"; return 1; }
    
    local patrol_home="$remote_home/patrol"
    
    # 创建目录
    if [ -n "$EXPECT_SSH_SCRIPT" ]; then
        "$EXPECT_SSH_SCRIPT" "$ip" "$port" "$user" "$password" "mkdir -p $patrol_home $patrol_home/bin" > /dev/null 2>&1
    else
        $ssh_cmd "$user@$ip" "mkdir -p $patrol_home $patrol_home/bin" 2>/dev/null
    fi
    
    # 上传 remote_collector.sh
    if [ -n "$EXPECT_SSH_SCRIPT" ]; then
        local temp_scp_expect=$(mktemp)
        cat > "$temp_scp_expect" << 'EOF'
#!/usr/bin/expect -f
set timeout 30
set ip [lindex $argv 0]
set port [lindex $argv 1]
set user [lindex $argv 2]
set password [lindex $argv 3]
set src [lindex $argv 4]
set dest [lindex $argv 5]

spawn scp -P $port $src $user@$ip:$dest
expect {
    "password:" {
        send "$password\r"
        expect eof
    }
    "Are you sure you want to continue connecting" {
        send "yes\r"
        expect "password:" {
            send "$password\r"
            expect eof
        }
    }
    eof {}
}
EOF
        chmod +x "$temp_scp_expect"
        "$temp_scp_expect" "$ip" "$port" "$user" "$password" "$SCRIPT_DIR/remote_collector.sh" "$patrol_home/remote_collector.sh" > /dev/null 2>&1
        rm -f "$temp_scp_expect"
    else
        $scp_cmd "$SCRIPT_DIR/remote_collector.sh" "$user@$ip:$patrol_home/remote_collector.sh" 2>/dev/null
    fi
    
    # 设置执行权限
    if [ -n "$EXPECT_SSH_SCRIPT" ]; then
        "$EXPECT_SSH_SCRIPT" "$ip" "$port" "$user" "$password" "chmod +x $patrol_home/remote_collector.sh" > /dev/null 2>&1
    else
        $ssh_cmd "$user@$ip" "chmod +x $patrol_home/remote_collector.sh" 2>/dev/null
    fi
    
    # 检查远程 jq
    local remote_jq=""
    if [ -n "$EXPECT_SSH_SCRIPT" ]; then
        local jq_check=$($EXPECT_SSH_SCRIPT "$ip" "$port" "$user" "$password" "command -v jq" 2>&1)
        if [ -n "$jq_check" ]; then
            remote_jq=$(echo "$jq_check" | tail -n 1)
        fi
    else
        if $ssh_cmd "$user@$ip" "command -v jq" 2>/dev/null; then
            remote_jq=$($ssh_cmd "$user@$ip" "command -v jq" 2>/dev/null)
        fi
    fi
    
    # 检查本地 jq
    if [ -z "$remote_jq" ]; then
        local remote_local_jq="$patrol_home/bin/jq"
        if [ -n "$EXPECT_SSH_SCRIPT" ]; then
            local jq_test=$($EXPECT_SSH_SCRIPT "$ip" "$port" "$user" "$password" "test -f $remote_local_jq" 2>&1)
            if [ $? -eq 0 ]; then
                remote_jq="$remote_local_jq"
            fi
        else
            if $ssh_cmd "$user@$ip" "test -f $remote_local_jq" 2>/dev/null; then
                remote_jq="$remote_local_jq"
            fi
        fi
    fi
    
    # 上传 jq
    if [ -z "$remote_jq" ]; then
        if [ -n "$EXPECT_SSH_SCRIPT" ]; then
            local temp_scp_expect=$(mktemp)
            cat > "$temp_scp_expect" << 'EOF'
#!/usr/bin/expect -f
set timeout 30
set ip [lindex $argv 0]
set port [lindex $argv 1]
set user [lindex $argv 2]
set password [lindex $argv 3]
set src [lindex $argv 4]
set dest [lindex $argv 5]

spawn scp -P $port $src $user@$ip:$dest
expect {
    "password:" {
        send "$password\r"
        expect eof
    }
    "Are you sure you want to continue connecting" {
        send "yes\r"
        expect "password:" {
            send "$password\r"
            expect eof
        }
    }
    eof {}
}
EOF
            chmod +x "$temp_scp_expect"
            "$temp_scp_expect" "$ip" "$port" "$user" "$password" "$JQ_PATH" "$patrol_home/bin/jq" > /dev/null 2>&1
            rm -f "$temp_scp_expect"
            
            "$EXPECT_SSH_SCRIPT" "$ip" "$port" "$user" "$password" "chmod +x $patrol_home/bin/jq" > /dev/null 2>&1
        else
            $ssh_cmd "$user@$ip" "mkdir -p $patrol_home/bin" 2>/dev/null
            $scp_cmd "$JQ_PATH" "$user@$ip:$patrol_home/bin/jq" 2>/dev/null
            $ssh_cmd "$user@$ip" "chmod +x $patrol_home/bin/jq" 2>/dev/null
        fi
        remote_jq="$patrol_home/bin/jq"
    fi
    
    # 清理临时文件
    if [ -n "$EXPECT_SSH_SCRIPT" ]; then
        rm -f "$EXPECT_SSH_SCRIPT"
        unset EXPECT_SSH_SCRIPT
    fi
    
    echo "$remote_jq"
}

# ============ 采集单台服务器 ============
collect_server() {
    local alias="$1" ip="$2" port="$3" user="$4" key="$5" password="$6" group="$7"
    
    log_info "collecting: $alias ($ip)"
    
    # 获取当前主机IP和用户
    local current_ip=$(hostname -I | awk '{print $1}')
    local current_user=$(whoami)
    
    if [[ "$ip" == "127.0.0.1" || ("$ip" == "$current_ip" && "$user" == "$current_user") ]]; then
        # 本地服务器，直接执行
        log_info "本地服务器，直接执行检查: $alias"
        
        local config_content=$(generate_host_config "$group")
        [ -z "$config_content" ] && { echo '{"error": true, "alias": "'"$alias"'", "ip": "'"$ip"'"}'; return 1; }
        
        local temp_config=$(mktemp)
        echo "$config_content" > "$temp_config"
        
        local result=$(bash "$SCRIPT_DIR/remote_collector.sh" "$temp_config" 2>&1)
        local json_result=$(echo "$result" | awk '/^\{/{flag=1} flag{print} /^\}/{flag=0}')
        
        rm -f "$temp_config"
        
        if echo "$json_result" | "$JQ_PATH" . >/dev/null 2>&1; then
            echo "$json_result"
        else
            echo "{\"error\": true, \"alias\": \"$alias\", \"ip\": \"$ip\"}"
        fi
        
        log_info "完成本地服务器 $alias 检查"
        return 0
    else
        # 远程服务器，使用 SSH
        local auth_success=false
        local ssh_cmd=""
        local scp_cmd=""
        
        # 1. 优先使用密钥认证
        if [[ -n "$key" && -f "$key" ]]; then
            log_info "尝试使用密钥认证连接服务器 $alias ($ip)"
            ssh_cmd="ssh -p $port -o StrictHostKeyChecking=no -i $key"
            scp_cmd="scp -p $port -o StrictHostKeyChecking=no -i $key"
            
            # 确保远程环境准备就绪
            local remote_jq=$(ensure_remote_ready "$ip" "$port" "$user" "$key" "$password")
            if [ -n "$remote_jq" ]; then
                auth_success=true
            fi
        fi
        
        # 2. 如果密钥认证失败或未配置密钥，尝试密码认证
        if [[ "$auth_success" == false && -n "$password" ]]; then
            log_info "尝试使用密码认证连接服务器 $alias ($ip)"
            
            # 检查 sshpass 是否存在
            if command -v sshpass &>/dev/null; then
                ssh_cmd="sshpass -p $password ssh -p $port -o StrictHostKeyChecking=no"
                scp_cmd="sshpass -p $password scp -p $port -o StrictHostKeyChecking=no"
                
                # 确保远程环境准备就绪
                local remote_jq=$(ensure_remote_ready "$ip" "$port" "$user" "$key" "$password")
                if [ -n "$remote_jq" ]; then
                    auth_success=true
                fi
            else
                # 检查 expect 是否存在
                if command -v expect &>/dev/null; then
                    log_info "使用 expect 进行密码认证"
                    # 使用 expect 确保远程环境准备就绪
                    local remote_jq=$(ensure_remote_ready "$ip" "$port" "$user" "$key" "$password")
                    if [ -n "$remote_jq" ]; then
                        auth_success=true
                    fi
                else
                    log_error "sshpass 和 expect 工具都未安装，无法使用密码认证"
                    return 1
                fi
            fi
        fi
        
        # 3. 认证失败处理
        if [[ "$auth_success" == false ]]; then
            log_error "无法连接到服务器 $alias ($ip)，认证失败"
            return 1
        fi
        
        # 4. 生成配置并执行检查
        local config_content=$(generate_host_config "$group")
        [ -z "$config_content" ] && { echo '{"error": true, "alias": "'"$alias"'", "ip": "'"$ip"'"}'; return 1; }
        
        local remote_home=$($ssh_cmd "$user@$ip" "echo \$HOME" 2>/dev/null)
        local patrol_home="$remote_home/patrol"
        
        # 写入配置文件
        if [ -n "$EXPECT_SSH_SCRIPT" ]; then
            # 使用 expect 写入配置文件
            local temp_config=$(mktemp)
            echo "$config_content" > "$temp_config"
            local temp_scp_expect=$(mktemp)
            cat > "$temp_scp_expect" << 'EOF'
#!/usr/bin/expect -f
set timeout 30
set ip [lindex $argv 0]
set port [lindex $argv 1]
set user [lindex $argv 2]
set password [lindex $argv 3]
set src [lindex $argv 4]
set dest [lindex $argv 5]

spawn scp -P $port $src $user@$ip:$dest
expect {
    "password:" {
        send "$password\r"
        expect eof
    }
    "Are you sure you want to continue connecting" {
        send "yes\r"
        expect "password:" {
            send "$password\r"
            expect eof
        }
    }
    eof {}
}
EOF
            chmod +x "$temp_scp_expect"
            "$temp_scp_expect" "$ip" "$port" "$user" "$password" "$temp_config" "$patrol_home/host_${ip}_patrol.conf" > /dev/null 2>&1
            rm -f "$temp_config" "$temp_scp_expect"
        else
            # 使用标准 ssh 写入配置文件
            echo "$config_content" | $ssh_cmd "$user@$ip" "cat > $patrol_home/host_${ip}_patrol.conf" 2>/dev/null
        fi
        
        # 执行远程检查
        local result
        if [ -n "$EXPECT_SSH_SCRIPT" ]; then
            # 使用 expect 执行远程检查
            result=$($EXPECT_SSH_SCRIPT "$ip" "$port" "$user" "$password" "cd $patrol_home && ./remote_collector.sh" 2>&1)
        else
            # 使用标准 ssh 执行远程检查
            result=$($ssh_cmd "$user@$ip" "cd $patrol_home && ./remote_collector.sh" 2>&1)
        fi
        
        local json_result=$(echo "$result" | awk '/^\{/{flag=1} flag{print} /^\}/{flag=0}')
        
        if echo "$json_result" | "$JQ_PATH" . >/dev/null 2>&1; then
            echo "$json_result"
        else
            echo "{\"error\": true, \"alias\": \"$alias\", \"ip\": \"$ip\"}"
        fi
        
        # 清理临时文件
        if [ -n "$EXPECT_SSH_SCRIPT" ]; then
            rm -f "$EXPECT_SSH_SCRIPT"
            unset EXPECT_SSH_SCRIPT
        fi
        
        log_info "完成服务器 $alias ($ip) 检查"
        return 0
    fi
}

# ============ 生成 HTML 报告 ============
generate_html_report() {
    local json_file="$1"
    local html_file="${json_file%.json}.html"
    local json_data=$(cat "$json_file" | "$JQ_PATH" -c '.')
    
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>系统巡检报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
        h1 { text-align: center; color: #333; }
        .server { margin: 20px 0; border: 1px solid #ddd; border-radius: 5px; overflow: hidden; }
        .server-title { background: #343a40; color: white; padding: 10px 15px; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f2f2f2; }
        .normal { color: green; }
        .warn { color: orange; }
        .serious { color: red; }
        .error { background: #f8d7da; border: 1px solid #f5c6cb; border-radius: 5px; padding: 15px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>系统巡检报告</h1>
        <div id="report-content"></div>
    </div>
    <script>
        const data = $json_data;
        const content = document.getElementById("report-content");
        
        data.forEach(server => {
            if (server.error) {
                const errorDiv = document.createElement("div");
                errorDiv.className = "error";
                errorDiv.innerHTML = "<h3>错误</h3><p>服务器: " + (server.alias || server.ip) + "</p>";
                content.appendChild(errorDiv);
                return;
            }
            
            const serverDiv = document.createElement("div");
            serverDiv.className = "server";
            serverDiv.innerHTML = \`
                <div class="server-title">\${server.hostname || server.hostip} (\${server.hostip})</div>
                <div style="padding:15px">
                    <p><strong>系统:</strong> \${server.os || "N/A"}</p>
                    <p><strong>运行时间:</strong> \${server.uptimeduration || "N/A"}</p>
                    <p><strong>CPU使用率:</strong> \${server.cpu?.usage || "N/A"}% 
                        <span class="\${server.cpu?.usestate || "normal"}">(\${server.cpu?.usestate || "normal"})</span>
                    </p>
                    <p><strong>内存使用率:</strong> \${server.memory?.usage || "N/A"}% 
                        <span class="\${server.memory?.usestate || "normal"}">(\${server.memory?.usestate || "normal"})</span>
                    </p>
                </div>
            \`;
            content.appendChild(serverDiv);
        });
    </script>
</body>
</html>
EOF
    log_info "HTML report: $html_file"
}

# ============ 生成 TXT 报告 ============
generate_txt_report() {
    local json_file="$1"
    local txt_file="${json_file%.json}.txt"
    
    cat > "$txt_file" << EOF
系统巡检报告
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
========================================
EOF
    
    "$JQ_PATH" -r '.[] | 
        "\n服务器: \(.hostname // .hostip) (\(.hostip))\n" +
        "----------------------------------------\n" +
        "系统: \(.os // "N/A")\n" +
        "运行时间: \(.uptimeduration // "N/A")\n" +
        "CPU使用率: \(.cpu.usage // "N/A")% (状态: \(.cpu.usestate // "normal"))\n" +
        "内存使用率: \(.memory.usage // "N/A")% (状态: \(.memory.usestate // "normal"))\n" +
        "\n磁盘使用:\n" +
        (if .disk then ([ .disk[] | "  \(.mounted): \(.usage)% (状态: \(.usestate // "normal"))\n" ] | join("")) else "" end) +
        "\n应用状态:\n" +
        (if .apps then ([ .apps[] | "  \(.name): \(.state)\n" ] | join("")) else "  无\n" end) +
        "\nDocker状态:\n" +
        (if .dockers then ([ .dockers[] | "  \(.name): \(.state)\n" ] | join("")) else "  无\n" end)
    ' "$json_file" >> "$txt_file"
    
    log_info "TXT report: $txt_file"
}

# ============ 主函数 ============
main() {
    log_info "========== patrol started =========="
    
    if [ "$DEMO_MODE" = true ]; then
        log_info "Running in DEMO mode"
        
        if [ ! -f "$DEMO_DATA_FILE" ]; then
            log_error "Demo data file not found: $DEMO_DATA_FILE"
            exit 1
        fi
        
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local merged_file="$OUTPUT_DIR/report_${timestamp}.json"
        
        cp "$DEMO_DATA_FILE" "$merged_file"
        log_info "Copied demo data to: $merged_file"
        
        generate_html_report "$merged_file"
        generate_txt_report "$merged_file"
        
        local reports_file="$OUTPUT_DIR/reports.json"
        if [ ! -f "$reports_file" ]; then
            echo "[]" > "$reports_file"
        fi
        
        local existing_reports=$(cat "$reports_file")
        local new_report=$("$JQ_PATH" -n --arg date "$(date '+%Y-%m-%d')" --arg time "$(date '+%H:%M:%S')" --arg file "report_${timestamp}.json" '$ARGS.named')
        local updated_reports=$(echo "$existing_reports" | "$JQ_PATH" --argjson new_report "$new_report" '. + [$new_report]')
        echo "$updated_reports" > "$reports_file"
        
        log_info "========== patrol completed (demo mode) =========="
        log_info "report: $merged_file"
        log_info "HTML: ${merged_file%.json}.html"
        log_info "TXT: ${merged_file%.json}.txt"
        log_info "Reports: $reports_file"
        return 0
    fi
    
    parse_servers
    parse_groups
    parse_checks
    
    [ ${#SERVERS[@]} -eq 0 ] && { log_error "no servers loaded"; exit 1; }
    
    local temp_dir=$(mktemp -d)
    log_info "temp dir: $temp_dir"
    
    for alias in "${SERVERS[@]}"; do
        json=$(collect_server "$alias" "${SERVER_IP[$alias]}" "${SERVER_PORT[$alias]}" "${SERVER_USER[$alias]}" "${SERVER_KEY[$alias]}" "${SERVER_PASSWORD[$alias]}" "${SERVER_GROUP[$alias]}")
        echo "$json" > "$temp_dir/${alias}.json"
    done
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local merged_file="$OUTPUT_DIR/report_${timestamp}.json"
    
    "$JQ_PATH" -s '.' "$temp_dir"/*.json > "$merged_file" 2>/dev/null || echo "[]" > "$merged_file"
    
    # 直接使用合并后的 JSON 生成报告（阈值已在远端处理）
    generate_html_report "$merged_file"
    generate_txt_report "$merged_file"
    
    # 生成 reports.json 文件，用于趋势分析
    local reports_file="$OUTPUT_DIR/reports.json"
    
    # 如果 reports.json 不存在，创建一个空数组
    if [ ! -f "$reports_file" ]; then
        echo "[]" > "$reports_file"
    fi
    
    # 读取现有的 reports.json 文件
    local existing_reports=$(cat "$reports_file")
    
    # 创建新的报告条目
    local new_report=$("$JQ_PATH" -n --arg date "$(date '+%Y-%m-%d')" --arg time "$(date '+%H:%M:%S')" --arg file "report_${timestamp}.json" '$ARGS.named')
    
    # 合并新报告到现有报告中
    local updated_reports=$(echo "$existing_reports" | "$JQ_PATH" --argjson new_report "$new_report" '. + [$new_report]')
    
    # 保存更新后的 reports.json 文件
    echo "$updated_reports" > "$reports_file"
    
    rm -rf "$temp_dir"
    
    log_info "========== patrol completed =========="
    log_info "report: $merged_file"
    log_info "HTML: ${merged_file%.json}.html"
    log_info "TXT: ${merged_file%.json}.txt"
    log_info "Reports: $reports_file"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --parallel|-p) PARALLEL="$2"; shift 2 ;;
        --help|-h) echo "Usage: $0 [--parallel N]"; exit 0 ;;
        *) shift ;;
    esac
done

main "$@"