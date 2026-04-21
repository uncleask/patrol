#!/bin/bash

# 中心机主脚本 - Patrol 系统巡检工具 (新版本)

# 配置文件路径
SCRIPT_DIR="$(dirname "$0")"
CONFIG_DIR="$SCRIPT_DIR/conf"
SERVERS_CONF="$CONFIG_DIR/servers.conf"
GROUPS_CONF="$CONFIG_DIR/check_groups.conf"
CHECKS_CONF="$CONFIG_DIR/checks.conf"
APPS_CONF="$CONFIG_DIR/apps.conf"
LOGS_CONF="$CONFIG_DIR/logs.conf"

# 输出目录
OUTPUT_DIR="$SCRIPT_DIR/output"
REMOTE_SCRIPT="$SCRIPT_DIR/remote_collector.sh"

# 日志目录
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# 临时文件目录
TEMP_DIR="/tmp/patrol"
mkdir -p "$TEMP_DIR"

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
NC="\033[0m"

# 日志文件
LOG_FILE="$LOG_DIR/patrol_$(date +%Y%m%d).log"

# 默认并发数
PARALLEL=5

# 帮助信息
show_help() {
    echo "Patrol 系统巡检工具"
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -g, --group GROUP   仅巡检指定组的服务器"
    echo "  -o, --output FORMAT 输出格式 (json,html,txt,all)，默认 all"
    echo "  --parallel NUM      并发线程数，默认 5"
    echo "  -v, --verbose       显示详细输出"
}

# 解析命令行参数
parse_args() {
    GROUP=""
    OUTPUT_FORMAT="all"
    VERBOSE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -g|--group)
                GROUP="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 读取服务器配置
read_servers() {
    if [[ ! -f "$SERVERS_CONF" ]]; then
        echo -e "${RED}错误: 服务器配置文件 $SERVERS_CONF 不存在${NC}"
        echo "错误: 服务器配置文件 $SERVERS_CONF 不存在" >> "$LOG_FILE"
        exit 1
    fi
    
    PATROL_SERVERS=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        IFS=":" read -r alias ip port user key password group_tags <<< "$line"
        
        if [[ -n "$GROUP" ]]; then
            if [[ " $group_tags " =~ " $GROUP " ]]; then
                PATROL_SERVERS+=("$alias $ip $port $user $key $password $group_tags")
            fi
        else
            PATROL_SERVERS+=("$alias $ip $port $user $key $password $group_tags")
        fi
    done < "$SERVERS_CONF"
    
    if [[ ${#PATROL_SERVERS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}警告: 没有找到符合条件的服务器${NC}"
        echo "警告: 没有找到符合条件的服务器" >> "$LOG_FILE"
        exit 0
    fi
    
    echo "INFO: 读取到 ${#PATROL_SERVERS[@]} 台服务器" >> "$LOG_FILE"
}

# 读取检查组配置
read_groups() {
    echo "INFO: 检查组配置读取" >> "$LOG_FILE"
}

# 读取检查项配置
read_checks() {
    echo "INFO: 检查项配置读取" >> "$LOG_FILE"
}

# 执行远程检查
execute_remote_check() {
    local server_info="$1"
    read -r alias ip port user key password group_tags <<< "$server_info"
    
    local result_file="$TEMP_DIR/${alias}_result.json"
    local remote_script="/tmp/remote_collector.sh"
    local remote_checks="/tmp/checks.conf"
    
    if [[ "$ip" == "127.0.0.1" ]]; then
        # 本地服务器，直接执行
        echo "INFO: 开始本地服务器检查: $alias" >> "$LOG_FILE"
        
        bash "$REMOTE_SCRIPT" "$CHECKS_CONF" > "$result_file" 2>/dev/null
        
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}错误: 无法执行本地检查${NC}"
            echo "错误: 无法执行本地检查" >> "$LOG_FILE"
            return 1
        fi
        
        if [[ "$VERBOSE" == true ]]; then
            echo -e "${GREEN}完成: 本地服务器 $alias 检查${NC}"
        fi
        echo "INFO: 完成本地服务器 $alias 检查" >> "$LOG_FILE"
        
        return 0
    else
        # 远程服务器，使用 SSH
        scp -i "$key" -P "$port" "$REMOTE_SCRIPT" "$CHECKS_CONF" "$user@$ip:/tmp/" > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}错误: 无法复制文件到服务器 $alias ($ip)${NC}"
            echo "错误: 无法复制文件到服务器 $alias ($ip)" >> "$LOG_FILE"
            return 1
        fi
        
        ssh -i "$key" -p "$port" "$user@$ip" "chmod +x /tmp/remote_collector.sh" > /dev/null 2>&1
        ssh -i "$key" -p "$port" "$user@$ip" "/tmp/remote_collector.sh /tmp/checks.conf" > "$result_file" 2>&1
        
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}错误: 无法执行远程检查在服务器 $alias ($ip)${NC}"
            echo "错误: 无法执行远程检查在服务器 $alias ($ip)" >> "$LOG_FILE"
            return 1
        fi
        
        ssh -i "$key" -p "$port" "$user@$ip" "rm -f /tmp/remote_collector.sh /tmp/checks.conf" > /dev/null 2>&1
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${GREEN}完成: 服务器 $alias ($ip) 检查${NC}"
    fi
    echo "INFO: 完成服务器 $alias ($ip) 检查" >> "$LOG_FILE"
    
    return 0
}

# 并发执行检查
run_parallel_checks() {
    local server_count=${#PATROL_SERVERS[@]}
    local running=0
    
    echo -e "${GREEN}开始巡检 ${server_count} 台服务器...${NC}"
    echo "INFO: 开始巡检 ${server_count} 台服务器，并发数: $PARALLEL" >> "$LOG_FILE"
    
    for server_info in "${PATROL_SERVERS[@]}"; do
        while [[ $running -ge $PARALLEL ]]; do
            sleep 1
            running=$(jobs -r | wc -l)
        done
        
        execute_remote_check "$server_info" &
        running=$((running + 1))
        
        wait -n 2>/dev/null && running=$((running - 1))
    done
    
    wait
    
    echo -e "${GREEN}所有服务器检查完成${NC}"
    echo "INFO: 所有服务器检查完成" >> "$LOG_FILE"
}

# 生成HTML报告
generate_html_report() {
    local json_report="$1"
    local html_report="${json_report%.json}.html"
    
    cat > "$html_report" <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>系统巡检报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #333; text-align: center; }
        h2 { color: #0066cc; border-bottom: 2px solid #0066cc; padding-bottom: 8px; }
        h3 { color: #444; }
        .server { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary { background: #e8f4f8; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
        .alarm { color: #ff9800; font-weight: bold; }
        .serious { color: #f44336; font-weight: bold; }
        .normal { color: #4CAF50; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        table, th, td { border: 1px solid #ddd; }
        th, td { padding: 10px; text-align: left; }
        th { background-color: #f2f2f2; }
        .section { margin: 20px 0; }
        .card { background: #fafafa; padding: 15px; border-radius: 5px; margin: 10px 0; border-left: 4px solid #0066cc; }
        .result-summary { background: #fff3cd; padding: 15px; border-radius: 5px; margin: 10px 0; border: 1px solid #ffeaa7; }
    </style>
</head>
<body>
    <h1>系统巡检报告</h1>
    <div class="summary">
        <p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
        <p>巡检服务器数量: ${#PATROL_SERVERS[@]}</p>
    </div>
EOF

    local server_count=$(jq -r '.servers | length' "$json_report" 2>/dev/null || echo 0)
    for ((i=0; i<server_count; i++)); do
        local alias=$(jq -r ".servers[$i].alias" "$json_report" 2>/dev/null || echo "N/A")
        local ip=$(jq -r ".servers[$i].ip" "$json_report" 2>/dev/null || echo "N/A")
        local group_tags=$(jq -r ".servers[$i].groups" "$json_report" 2>/dev/null || echo "N/A")
        
        # 新结构的服务器信息
        local server_info=$(jq -r ".servers[$i].results[0]" "$json_report" 2>/dev/null)
        
        if [[ -n "$server_info" ]]; then
            local time=$(echo "$server_info" | jq -r '.time' 2>/dev/null || echo "N/A")
            local hostip=$(echo "$server_info" | jq -r '.hostip' 2>/dev/null || echo "N/A")
            local hostname=$(echo "$server_info" | jq -r '.hostname' 2>/dev/null || echo "N/A")
            local os=$(echo "$server_info" | jq -r '.os' 2>/dev/null || echo "N/A")
            local uptimesince=$(echo "$server_info" | jq -r '.uptimesince' 2>/dev/null || echo "N/A")
            local uptimeduration=$(echo "$server_info" | jq -r '.uptimeduration' 2>/dev/null || echo "N/A")
            
            # CPU信息
            local cpu_usage=$(echo "$server_info" | jq -r '.cpu.usage' 2>/dev/null || echo "N/A")
            local cpu_sysusage=$(echo "$server_info" | jq -r '.cpu.sysusage' 2>/dev/null || echo "N/A")
            local cpu_idle=$(echo "$server_info" | jq -r '.cpu.idle' 2>/dev/null || echo "N/A")
            local cpu_iowait=$(echo "$server_info" | jq -r '.cpu.iowait' 2>/dev/null || echo "N/A")
            local cpu_avgload=$(echo "$server_info" | jq -r '.cpu.avgload' 2>/dev/null || echo "N/A")
            local cpu_usestate=$(echo "$server_info" | jq -r '.cpu.usestate' 2>/dev/null || echo "normal")
            
            # 内存信息
            local mem_total=$(echo "$server_info" | jq -r '.memory.total' 2>/dev/null || echo "N/A")
            local mem_used=$(echo "$server_info" | jq -r '.memory.used' 2>/dev/null || echo "N/A")
            local mem_free=$(echo "$server_info" | jq -r '.memory.free' 2>/dev/null || echo "N/A")
            local mem_available=$(echo "$server_info" | jq -r '.memory.available' 2>/dev/null || echo "N/A")
            local mem_usage=$(echo "$server_info" | jq -r '.memory.usage' 2>/dev/null || echo "N/A")
            local mem_usestate=$(echo "$server_info" | jq -r '.memory.usestate' 2>/dev/null || echo "normal")
            local swap_total=$(echo "$server_info" | jq -r '.memory.swaptotal' 2>/dev/null || echo "N/A")
            local swap_used=$(echo "$server_info" | jq -r '.memory.swapused' 2>/dev/null || echo "N/A")
            local swap_free=$(echo "$server_info" | jq -r '.memory.swapfree' 2>/dev/null || echo "N/A")
            local swap_usage=$(echo "$server_info" | jq -r '.memory.swapusage' 2>/dev/null || echo "N/A")
            local swap_usestate=$(echo "$server_info" | jq -r '.memory.swapusestate' 2>/dev/null || echo "normal")
            
            # 结果信息
            local all_count=$(echo "$server_info" | jq -r '.result.all_count' 2>/dev/null || echo "N/A")
            local normal_count=$(echo "$server_info" | jq -r '.result.normal_count' 2>/dev/null || echo "N/A")
            local warn_count=$(echo "$server_info" | jq -r '.result.warn_count' 2>/dev/null || echo "N/A")
            local serious_count=$(echo "$server_info" | jq -r '.result.serious_count' 2>/dev/null || echo "N/A")
            local description=$(echo "$server_info" | jq -r '.result.description' 2>/dev/null || echo "N/A")
            
            cat >> "$html_report" <<EOF
    <div class="server">
        <h2>服务器: $alias ($ip)</h2>
        <p>所属组: $group_tags</p>
        <p>巡检时间: $time</p>
        
        <div class="result-summary">
            <h3>巡检结果</h3>
            <p>总检查项: $all_count | 正常: $normal_count | 警告: $warn_count | 严重: $serious_count</p>
            <p>状态描述: $description</p>
        </div>
        
        <div class="section">
            <h3>系统信息</h3>
            <div class="card">
                <p>主机名: $hostname</p>
                <p>IP地址: $hostip</p>
                <p>操作系统: $os</p>
                <p>系统启动时间: $uptimesince</p>
                <p>运行时长: $uptimeduration</p>
            </div>
        </div>
        
        <div class="section">
            <h3>资源信息</h3>
            <div class="card">
                <h4>CPU信息</h4>
                <p>使用率: <span class="$cpu_usestate">$cpu_usage%</span></p>
                <p>系统使用率: $cpu_sysusage%</p>
                <p>空闲率: $cpu_idle%</p>
                <p>IO等待: $cpu_iowait%</p>
                <p>平均负载: $cpu_avgload</p>
            </div>
            
            <div class="card">
                <h4>内存信息</h4>
                <p>总内存: ${mem_total}MB</p>
                <p>已用内存: ${mem_used}MB</p>
                <p>空闲内存: ${mem_free}MB</p>
                <p>可用内存: ${mem_available}MB</p>
                <p>使用率: <span class="$mem_usestate">$mem_usage%</span></p>
                <p>交换空间: ${swap_total}MB / 已用: ${swap_used}MB / 空闲: ${swap_free}MB</p>
            </div>
            
            <h4>磁盘信息</h4>
            <table>
                <tr>
                    <th>挂载点</th>
                    <th>文件系统</th>
                    <th>总大小</th>
                    <th>已用</th>
                    <th>可用</th>
                    <th>使用率</th>
                    <th>状态</th>
                </tr>
EOF

            local disk_count=$(echo "$server_info" | jq -r '.disk | length' 2>/dev/null || echo 0)
            for ((j=0; j<disk_count; j++)); do
                local mounted=$(echo "$server_info" | jq -r ".disk[$j].mounted" 2>/dev/null || echo "N/A")
                local filesystem=$(echo "$server_info" | jq -r ".disk[$j].filesystem" 2>/dev/null || echo "N/A")
                local total=$(echo "$server_info" | jq -r ".disk[$j].total" 2>/dev/null || echo "N/A")
                local used=$(echo "$server_info" | jq -r ".disk[$j].used" 2>/dev/null || echo "N/A")
                local available=$(echo "$server_info" | jq -r ".disk[$j].available" 2>/dev/null || echo "N/A")
                local usage=$(echo "$server_info" | jq -r ".disk[$j].usage" 2>/dev/null || echo "N/A")
                local usestate=$(echo "$server_info" | jq -r ".disk[$j].usestate" 2>/dev/null || echo "normal")
                
                cat >> "$html_report" <<EOF
                <tr>
                    <td>$mounted</td>
                    <td>$filesystem</td>
                    <td>$total</td>
                    <td>$used</td>
                    <td>$available</td>
                    <td>$usage%</td>
                    <td><span class="$usestate">$usestate</span></td>
                </tr>
EOF
            done
            
            cat >> "$html_report" <<EOF
            </table>
        </div>
        
        <div class="section">
            <h3>应用状态</h3>
            <table>
                <tr>
                    <th>应用名称</th>
                    <th>类型</th>
                    <th>用户</th>
                    <th>进程ID</th>
                    <th>状态</th>
                    <th>CPU使用率</th>
                    <th>内存使用率</th>
                    <th>运行时长</th>
                </tr>
EOF

            local apps_count=$(echo "$server_info" | jq -r '.apps | length' 2>/dev/null || echo 0)
            for ((j=0; j<apps_count; j++)); do
                local app_name=$(echo "$server_info" | jq -r ".apps[$j].name" 2>/dev/null || echo "N/A")
                local app_type=$(echo "$server_info" | jq -r ".apps[$j].type" 2>/dev/null || echo "N/A")
                local app_user=$(echo "$server_info" | jq -r ".apps[$j].user" 2>/dev/null || echo "N/A")
                local app_pid=$(echo "$server_info" | jq -r ".apps[$j].pid" 2>/dev/null || echo "N/A")
                local app_state=$(echo "$server_info" | jq -r ".apps[$j].state" 2>/dev/null || echo "N/A")
                local app_cpuusage=$(echo "$server_info" | jq -r ".apps[$j].cpuusage" 2>/dev/null || echo "N/A")
                local app_memusage=$(echo "$server_info" | jq -r ".apps[$j].memusage" 2>/dev/null || echo "N/A")
                local app_runtime=$(echo "$server_info" | jq -r ".apps[$j].runtime" 2>/dev/null || echo "N/A")
                
                local status_class=""
                if [[ "$app_state" == "running" ]]; then
                    status_class="normal"
                else
                    status_class="serious"
                fi
                
                cat >> "$html_report" <<EOF
                <tr>
                    <td>$app_name</td>
                    <td>$app_type</td>
                    <td>$app_user</td>
                    <td>$app_pid</td>
                    <td><span class="$status_class">$app_state</span></td>
                    <td>${app_cpuusage}${app_cpuusage:+%}</td>
                    <td>${app_memusage}${app_memusage:+%}</td>
                    <td>$app_runtime</td>
                </tr>
EOF
            done
            
            cat >> "$html_report" <<EOF
            </table>
        </div>
        
        <div class="section">
            <h3>Docker容器状态</h3>
            <table>
                <tr>
                    <th>容器名称</th>
                    <th>容器ID</th>
                    <th>状态</th>
                    <th>详细状态</th>
                </tr>
EOF

            local dockers_count=$(echo "$server_info" | jq -r '.dockers | length' 2>/dev/null || echo 0)
            for ((j=0; j<dockers_count; j++)); do
                local docker_name=$(echo "$server_info" | jq -r ".dockers[$j].name" 2>/dev/null || echo "N/A")
                local docker_id=$(echo "$server_info" | jq -r ".dockers[$j].id" 2>/dev/null || echo "N/A")
                local docker_state=$(echo "$server_info" | jq -r ".dockers[$j].state" 2>/dev/null || echo "N/A")
                local docker_status=$(echo "$server_info" | jq -r ".dockers[$j].status" 2>/dev/null || echo "N/A")
                
                local status_class=""
                if [[ "$docker_state" == "running" ]]; then
                    status_class="normal"
                elif [[ "$docker_state" == "not_found" ]]; then
                    status_class="serious"
                else
                    status_class="alarm"
                fi
                
                cat >> "$html_report" <<EOF
                <tr>
                    <td>$docker_name</td>
                    <td>$docker_id</td>
                    <td><span class="$status_class">$docker_state</span></td>
                    <td>$docker_status</td>
                </tr>
EOF
            done
            
            cat >> "$html_report" <<EOF
            </table>
        </div>
    </div>
EOF
        fi
    done

    cat >> "$html_report" <<EOF
</body>
</html>
EOF

    echo -e "${GREEN}HTML 报告生成: $html_report${NC}"
    echo "INFO: HTML 报告生成: $html_report" >> "$LOG_FILE"
}

# 生成TXT报告
generate_txt_report() {
    local json_report="$1"
    local txt_report="${json_report%.json}.txt"
    
    cat > "$txt_report" <<EOF
==================================================
系统巡检报告
==================================================
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
巡检服务器数量: ${#PATROL_SERVERS[@]}
==================================================

EOF

    local server_count=$(jq -r '.servers | length' "$json_report" 2>/dev/null || echo 0)
    for ((i=0; i<server_count; i++)); do
        local alias=$(jq -r ".servers[$i].alias" "$json_report" 2>/dev/null || echo "N/A")
        local ip=$(jq -r ".servers[$i].ip" "$json_report" 2>/dev/null || echo "N/A")
        local group_tags=$(jq -r ".servers[$i].groups" "$json_report" 2>/dev/null || echo "N/A")
        
        # 新结构的服务器信息
        local server_info=$(jq -r ".servers[$i].results[0]" "$json_report" 2>/dev/null)
        
        if [[ -n "$server_info" ]]; then
            local time=$(echo "$server_info" | jq -r '.time' 2>/dev/null || echo "N/A")
            local hostip=$(echo "$server_info" | jq -r '.hostip' 2>/dev/null || echo "N/A")
            local hostname=$(echo "$server_info" | jq -r '.hostname' 2>/dev/null || echo "N/A")
            local os=$(echo "$server_info" | jq -r '.os' 2>/dev/null || echo "N/A")
            local uptimesince=$(echo "$server_info" | jq -r '.uptimesince' 2>/dev/null || echo "N/A")
            local uptimeduration=$(echo "$server_info" | jq -r '.uptimeduration' 2>/dev/null || echo "N/A")
            
            # CPU信息
            local cpu_usage=$(echo "$server_info" | jq -r '.cpu.usage' 2>/dev/null || echo "N/A")
            local cpu_sysusage=$(echo "$server_info" | jq -r '.cpu.sysusage' 2>/dev/null || echo "N/A")
            local cpu_idle=$(echo "$server_info" | jq -r '.cpu.idle' 2>/dev/null || echo "N/A")
            local cpu_iowait=$(echo "$server_info" | jq -r '.cpu.iowait' 2>/dev/null || echo "N/A")
            local cpu_avgload=$(echo "$server_info" | jq -r '.cpu.avgload' 2>/dev/null || echo "N/A")
            local cpu_usestate=$(echo "$server_info" | jq -r '.cpu.usestate' 2>/dev/null || echo "normal")
            
            # 内存信息
            local mem_total=$(echo "$server_info" | jq -r '.memory.total' 2>/dev/null || echo "N/A")
            local mem_used=$(echo "$server_info" | jq -r '.memory.used' 2>/dev/null || echo "N/A")
            local mem_free=$(echo "$server_info" | jq -r '.memory.free' 2>/dev/null || echo "N/A")
            local mem_available=$(echo "$server_info" | jq -r '.memory.available' 2>/dev/null || echo "N/A")
            local mem_usage=$(echo "$server_info" | jq -r '.memory.usage' 2>/dev/null || echo "N/A")
            local mem_usestate=$(echo "$server_info" | jq -r '.memory.usestate' 2>/dev/null || echo "normal")
            local swap_total=$(echo "$server_info" | jq -r '.memory.swaptotal' 2>/dev/null || echo "N/A")
            local swap_used=$(echo "$server_info" | jq -r '.memory.swapused' 2>/dev/null || echo "N/A")
            local swap_free=$(echo "$server_info" | jq -r '.memory.swapfree' 2>/dev/null || echo "N/A")
            local swap_usage=$(echo "$server_info" | jq -r '.memory.swapusage' 2>/dev/null || echo "N/A")
            local swap_usestate=$(echo "$server_info" | jq -r '.memory.swapusestate' 2>/dev/null || echo "normal")
            
            # 结果信息
            local all_count=$(echo "$server_info" | jq -r '.result.all_count' 2>/dev/null || echo "N/A")
            local normal_count=$(echo "$server_info" | jq -r '.result.normal_count' 2>/dev/null || echo "N/A")
            local warn_count=$(echo "$server_info" | jq -r '.result.warn_count' 2>/dev/null || echo "N/A")
            local serious_count=$(echo "$server_info" | jq -r '.result.serious_count' 2>/dev/null || echo "N/A")
            local description=$(echo "$server_info" | jq -r '.result.description' 2>/dev/null || echo "N/A")
            
            cat >> "$txt_report" <<EOF

[服务器: $alias ($ip)]
所属组: $group_tags
巡检时间: $time
--------------------------------------------------
系统信息:
  主机名: $hostname
  IP地址: $hostip
  操作系统: $os
  系统启动时间: $uptimesince
  运行时长: $uptimeduration

资源信息:
  CPU信息:
    使用率: $cpu_usage% [${cpu_usestate}]
    系统使用率: $cpu_sysusage%
    空闲率: $cpu_idle%
    IO等待: $cpu_iowait%
    平均负载: $cpu_avgload
  
  内存信息:
    总内存: ${mem_total}MB
    已用内存: ${mem_used}MB
    空闲内存: ${mem_free}MB
    可用内存: ${mem_available}MB
    使用率: $mem_usage% [${mem_usestate}]
    交换空间: ${swap_total}MB / 已用: ${swap_used}MB / 空闲: ${swap_free}MB

  磁盘信息:
EOF
            
            local disk_count=$(echo "$server_info" | jq -r '.disk | length' 2>/dev/null || echo 0)
            if [[ $disk_count -gt 0 ]]; then
                for ((j=0; j<disk_count; j++)); do
                    local mounted=$(echo "$server_info" | jq -r ".disk[$j].mounted" 2>/dev/null || echo "N/A")
                    local filesystem=$(echo "$server_info" | jq -r ".disk[$j].filesystem" 2>/dev/null || echo "N/A")
                    local total=$(echo "$server_info" | jq -r ".disk[$j].total" 2>/dev/null || echo "N/A")
                    local used=$(echo "$server_info" | jq -r ".disk[$j].used" 2>/dev/null || echo "N/A")
                    local available=$(echo "$server_info" | jq -r ".disk[$j].available" 2>/dev/null || echo "N/A")
                    local usage=$(echo "$server_info" | jq -r ".disk[$j].usage" 2>/dev/null || echo "N/A")
                    local usestate=$(echo "$server_info" | jq -r ".disk[$j].usestate" 2>/dev/null || echo "normal")
                    
                    cat >> "$txt_report" <<EOF
    - $mounted ($filesystem): 总大小: $total, 已用: $used, 可用: $available, 使用率: $usage% [${usestate}]
EOF
                done
            else
                cat >> "$txt_report" <<EOF
    无磁盘信息
EOF
            fi
            
            cat >> "$txt_report" <<EOF

应用状态:
EOF
            
            local apps_count=$(echo "$server_info" | jq -r '.apps | length' 2>/dev/null || echo 0)
            if [[ $apps_count -gt 0 ]]; then
                for ((j=0; j<apps_count; j++)); do
                    local app_name=$(echo "$server_info" | jq -r ".apps[$j].name" 2>/dev/null || echo "N/A")
                    local app_type=$(echo "$server_info" | jq -r ".apps[$j].type" 2>/dev/null || echo "N/A")
                    local app_user=$(echo "$server_info" | jq -r ".apps[$j].user" 2>/dev/null || echo "N/A")
                    local app_pid=$(echo "$server_info" | jq -r ".apps[$j].pid" 2>/dev/null || echo "N/A")
                    local app_state=$(echo "$server_info" | jq -r ".apps[$j].state" 2>/dev/null || echo "N/A")
                    local app_cpuusage=$(echo "$server_info" | jq -r ".apps[$j].cpuusage" 2>/dev/null || echo "N/A")
                    local app_memusage=$(echo "$server_info" | jq -r ".apps[$j].memusage" 2>/dev/null || echo "N/A")
                    local app_runtime=$(echo "$server_info" | jq -r ".apps[$j].runtime" 2>/dev/null || echo "N/A")
                    
                    cat >> "$txt_report" <<EOF
  - $app_name ($app_type): 用户: $app_user, 进程ID: $app_pid, 状态: $app_state, CPU: ${app_cpuusage}${app_cpuusage:+%}, 内存: ${app_memusage}${app_memusage:+%}, 运行时长: $app_runtime
EOF
                done
            else
                cat >> "$txt_report" <<EOF
  无应用信息
EOF
            fi
            
            cat >> "$txt_report" <<EOF

Docker容器状态:
EOF
            
            local dockers_count=$(echo "$server_info" | jq -r '.dockers | length' 2>/dev/null || echo 0)
            if [[ $dockers_count -gt 0 ]]; then
                for ((j=0; j<dockers_count; j++)); do
                    local docker_name=$(echo "$server_info" | jq -r ".dockers[$j].name" 2>/dev/null || echo "N/A")
                    local docker_id=$(echo "$server_info" | jq -r ".dockers[$j].id" 2>/dev/null || echo "N/A")
                    local docker_state=$(echo "$server_info" | jq -r ".dockers[$j].state" 2>/dev/null || echo "N/A")
                    local docker_status=$(echo "$server_info" | jq -r ".dockers[$j].status" 2>/dev/null || echo "N/A")
                    
                    cat >> "$txt_report" <<EOF
  - $docker_name: 容器ID: $docker_id, 状态: $docker_state, 详细状态: $docker_status
EOF
                done
            else
                cat >> "$txt_report" <<EOF
  无容器信息
EOF
            fi
            
            cat >> "$txt_report" <<EOF

巡检结果:
  总检查项: $all_count
  正常: $normal_count
  警告: $warn_count
  严重: $serious_count
  状态描述: $description

EOF
        fi
    done
    
    echo -e "${GREEN}TXT 报告生成: $txt_report${NC}"
    echo "INFO: TXT 报告生成: $txt_report" >> "$LOG_FILE"
}

# 生成报告
generate_reports() {
    local json_report="$OUTPUT_DIR/patrol_report_$(date +%Y%m%d_%H%M%S).json"
    
    echo "{" > "$json_report"
    echo "  \"timestamp\": \"$(date '+%Y-%m-%dT%H:%M:%S')\"," >> "$json_report"
    echo "  \"servers\": [" >> "$json_report"
    
    local first=true
    for server_info in "${PATROL_SERVERS[@]}"; do
        read -r alias ip port user key password group_tags <<< "$server_info"
        local result_file="$TEMP_DIR/${alias}_result.json"
        
        if [[ -f "$result_file" ]]; then
            if [[ "$first" == true ]]; then
                first=false
            else
                echo "  ," >> "$json_report"
            fi
            
            echo "    {" >> "$json_report"
            echo "      \"alias\": \"$alias\"," >> "$json_report"
            echo "      \"ip\": \"$ip\"," >> "$json_report"
            echo "      \"groups\": \"$group_tags\"," >> "$json_report"
            echo "      \"results\": " >> "$json_report"
            cat "$result_file" >> "$json_report"
            echo "    }" >> "$json_report"
        fi
    done
    
    echo "  ]" >> "$json_report"
    echo "}" >> "$json_report"
    
    echo -e "${GREEN}JSON 报告生成: $json_report${NC}"
    echo "INFO: JSON 报告生成: $json_report" >> "$LOG_FILE"
    
    case "$OUTPUT_FORMAT" in
        "json")
            ;;
        "html")
            generate_html_report "$json_report"
            ;;
        "txt")
            generate_txt_report "$json_report"
            ;;
        "all"|*)
            generate_html_report "$json_report"
            generate_txt_report "$json_report"
            ;;
    esac
}

# 清理历史报告文件
cleanup_old_reports() {
    # 保留最近7天的报告，删除更早的报告
    find "$OUTPUT_DIR" -name "*.json" -o -name "*.html" -o -name "*.txt" | xargs -r ls -lt | awk 'NR>7 {print $9}' | xargs -r rm -f
    echo "INFO: 清理旧报告文件" >> "$LOG_FILE"
}

# 清理临时文件
cleanup() {
    rm -rf "$TEMP_DIR"
    echo "INFO: 清理临时文件" >> "$LOG_FILE"
}

# 主函数
main() {
    parse_args "$@"
    echo "INFO: 参数解析完成" >> "$LOG_FILE"
    
    read_servers
    echo "INFO: 服务器配置读取完成" >> "$LOG_FILE"
    
    read_groups
    echo "INFO: 检查组配置读取完成" >> "$LOG_FILE"
    
    read_checks
    echo "INFO: 检查项配置读取完成" >> "$LOG_FILE"
    
    mkdir -p "$OUTPUT_DIR"
    echo "INFO: 输出目录准备完成" >> "$LOG_FILE"
    
    run_parallel_checks
    echo "INFO: 检查执行完成" >> "$LOG_FILE"
    
    generate_reports
    echo "INFO: 报告生成完成" >> "$LOG_FILE"
    
    # 清理旧报告文件
    cleanup_old_reports
    
    cleanup
    echo "INFO: 清理完成" >> "$LOG_FILE"
    
    echo -e "${GREEN}巡检完成！${NC}"
    echo "INFO: 巡检完成" >> "$LOG_FILE"
}

# 执行主函数
main "$@"
