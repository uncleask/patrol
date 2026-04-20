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
    local remote_apps="/tmp/apps.conf"
    local remote_logs="/tmp/logs.conf"
    local remote_checks="/tmp/checks.conf"
    
    if [[ "$ip" == "127.0.0.1" ]]; then
        # 本地服务器，直接执行
        echo "INFO: 开始本地服务器检查: $alias" >> "$LOG_FILE"
        
        bash "$REMOTE_SCRIPT" "$APPS_CONF" "$LOGS_CONF" "$CHECKS_CONF" > "$result_file" 2>/dev/null
        
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
        scp -i "$key" -P "$port" "$REMOTE_SCRIPT" "$APPS_CONF" "$LOGS_CONF" "$CHECKS_CONF" "$user@$ip:/tmp/" > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}错误: 无法复制文件到服务器 $alias ($ip)${NC}"
            echo "错误: 无法复制文件到服务器 $alias ($ip)" >> "$LOG_FILE"
            return 1
        fi
        
        ssh -i "$key" -p "$port" "$user@$ip" "chmod +x /tmp/remote_collector.sh" > /dev/null 2>&1
        ssh -i "$key" -p "$port" "$user@$ip" "/tmp/remote_collector.sh /tmp/apps.conf /tmp/logs.conf /tmp/checks.conf" > "$result_file" 2>&1
        
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}错误: 无法执行远程检查在服务器 $alias ($ip)${NC}"
            echo "错误: 无法执行远程检查在服务器 $alias ($ip)" >> "$LOG_FILE"
            return 1
        fi
        
        ssh -i "$key" -p "$port" "$user@$ip" "rm -f /tmp/remote_collector.sh /tmp/apps.conf /tmp/logs.conf /tmp/checks.conf" > /dev/null 2>&1
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
    </style>
</head>
<body>
    <h1>系统巡检报告</h1>
    <div class="summary">
        <p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
        <p>巡检服务器数量: ${#PATROL_SERVERS[@]}</p>
    </div>
EOF

    local server_index=0
    for server_info in "${PATROL_SERVERS[@]}"; do
        read -r alias ip port user key password group_tags <<< "$server_info"
        local result_file="$TEMP_DIR/${alias}_result.json"
        
        if [[ -f "$result_file" ]]; then
            cat >> "$html_report" <<EOF
    <div class="server">
        <h2>服务器: $alias ($ip)</h2>
        <p>所属组: $group_tags</p>
        
        <div class="section">
            <h3>系统信息</h3>
            <div class="card">
                <p>操作系统版本: $(jq -r '.system_info.os_version' "$result_file" 2>/dev/null || echo "N/A")</p>
                <p>内核版本: $(jq -r '.system_info.kernel_version' "$result_file" 2>/dev/null || echo "N/A")</p>
                <p>运行时长: $(jq -r '.system_info.uptime' "$result_file" 2>/dev/null || echo "N/A")</p>
                <p>CPU架构: $(jq -r '.system_info.cpu_arch' "$result_file" 2>/dev/null || echo "N/A")</p>
            </div>
        </div>
        
        <div class="section">
            <h3>资源信息</h3>
            <div class="card">
                <p>CPU使用率: <span class="$(jq -r '.resource_info.cpu.alarm_status' "$result_file" 2>/dev/null || echo "normal")">$(jq -r '.resource_info.cpu.usage' "$result_file" 2>/dev/null || echo "N/A")%</span></p>
                <p>内存使用率: <span class="$(jq -r '.resource_info.memory.alarm_status' "$result_file" 2>/dev/null || echo "normal")">$(jq -r '.resource_info.memory.usage_percent' "$result_file" 2>/dev/null || echo "N/A")%</span></p>
            </div>
            
            <h4>磁盘信息</h4>
            <table>
                <tr>
                    <th>文件系统</th>
                    <th>大小</th>
                    <th>已用</th>
                    <th>可用</th>
                    <th>使用率</th>
                    <th>挂载点</th>
                </tr>
EOF

            local disk_count=$(jq -r '.resource_info.disks | length' "$result_file" 2>/dev/null || echo 0)
            for ((i=0; i<disk_count; i++)); do
                local fs=$(jq -r ".resource_info.disks[$i].filesystem" "$result_file" 2>/dev/null || echo "N/A")
                local size=$(jq -r ".resource_info.disks[$i].size" "$result_file" 2>/dev/null || echo "N/A")
                local used=$(jq -r ".resource_info.disks[$i].used" "$result_file" 2>/dev/null || echo "N/A")
                local avail=$(jq -r ".resource_info.disks[$i].available" "$result_file" 2>/dev/null || echo "N/A")
                local use_pct=$(jq -r ".resource_info.disks[$i].use_percent" "$result_file" 2>/dev/null || echo "N/A")
                local mount=$(jq -r ".resource_info.disks[$i].mount_point" "$result_file" 2>/dev/null || echo "N/A")
                local alarm=$(jq -r ".resource_info.disks[$i].alarm_status" "$result_file" 2>/dev/null || echo "normal")
                
                cat >> "$html_report" <<EOF
                <tr>
                    <td>$fs</td>
                    <td>$size</td>
                    <td>$used</td>
                    <td>$avail</td>
                    <td><span class="$alarm">$use_pct%</span></td>
                    <td>$mount</td>
                </tr>
EOF
            done
            
            cat >> "$html_report" <<EOF
            </table>
        </div>
        
        <div class="section">
            <h3>应用信息 - 进程</h3>
            <table>
                <tr>
                    <th>进程名</th>
                    <th>服务名</th>
                    <th>运行状态</th>
                    <th>PID</th>
                    <th>CPU使用率</th>
                    <th>内存使用率</th>
                </tr>
EOF

            local proc_count=$(jq -r '.app_info.processes | length' "$result_file" 2>/dev/null || echo 0)
            for ((i=0; i<proc_count; i++)); do
                local proc_name=$(jq -r ".app_info.processes[$i].process_name" "$result_file" 2>/dev/null || echo "N/A")
                local service_name=$(jq -r ".app_info.processes[$i].service_name" "$result_file" 2>/dev/null || echo "N/A")
                local running=$(jq -r ".app_info.processes[$i].running" "$result_file" 2>/dev/null || echo "false")
                local pid=$(jq -r ".app_info.processes[$i].pid" "$result_file" 2>/dev/null || echo "N/A")
                local cpu_usage=$(jq -r ".app_info.processes[$i].cpu_usage" "$result_file" 2>/dev/null || echo "N/A")
                local cpu_alarm=$(jq -r ".app_info.processes[$i].cpu_alarm_status" "$result_file" 2>/dev/null || echo "normal")
                local mem_usage=$(jq -r ".app_info.processes[$i].memory_usage" "$result_file" 2>/dev/null || echo "N/A")
                local mem_alarm=$(jq -r ".app_info.processes[$i].memory_alarm_status" "$result_file" 2>/dev/null || echo "normal")
                
                local status_text=""
                if [[ "$running" == "true" ]]; then
                    status_text="运行中"
                else
                    status_text="<span class=\"serious\">未运行</span>"
                fi
                
                cat >> "$html_report" <<EOF
                <tr>
                    <td>$proc_name</td>
                    <td>$service_name</td>
                    <td>$status_text</td>
                    <td>$pid</td>
                    <td><span class="$cpu_alarm">$cpu_usage%</span></td>
                    <td><span class="$mem_alarm">$mem_usage%</span></td>
                </tr>
EOF
            done
            
            cat >> "$html_report" <<EOF
            </table>
        </div>
        
        <div class="section">
            <h3>应用信息 - 容器</h3>
            <table>
                <tr>
                    <th>容器名</th>
                    <th>服务名</th>
                    <th>运行状态</th>
                    <th>CPU使用率</th>
                    <th>内存使用率</th>
                </tr>
EOF

            local docker_count=$(jq -r '.app_info.docker_containers | length' "$result_file" 2>/dev/null || echo 0)
            for ((i=0; i<docker_count; i++)); do
                local container_name=$(jq -r ".app_info.docker_containers[$i].container_name" "$result_file" 2>/dev/null || echo "N/A")
                local service_name=$(jq -r ".app_info.docker_containers[$i].service_name" "$result_file" 2>/dev/null || echo "N/A")
                local state=$(jq -r ".app_info.docker_containers[$i].state" "$result_file" 2>/dev/null || echo "unknown")
                local cpu_usage=$(jq -r ".app_info.docker_containers[$i].cpu_usage" "$result_file" 2>/dev/null || echo "N/A")
                local cpu_alarm=$(jq -r ".app_info.docker_containers[$i].cpu_alarm_status" "$result_file" 2>/dev/null || echo "normal")
                local mem_usage=$(jq -r ".app_info.docker_containers[$i].memory_usage" "$result_file" 2>/dev/null || echo "N/A")
                local mem_alarm=$(jq -r ".app_info.docker_containers[$i].memory_alarm_status" "$result_file" 2>/dev/null || echo "normal")
                
                local status_text=""
                if [[ "$state" == "running" ]]; then
                    status_text="运行中"
                else
                    status_text="<span class=\"serious\">$state</span>"
                fi
                
                cat >> "$html_report" <<EOF
                <tr>
                    <td>$container_name</td>
                    <td>$service_name</td>
                    <td>$status_text</td>
                    <td><span class="$cpu_alarm">$cpu_usage%</span></td>
                    <td><span class="$mem_alarm">$mem_usage%</span></td>
                </tr>
EOF
            done
            
            cat >> "$html_report" <<EOF
            </table>
        </div>
    </div>
EOF
        fi
        ((server_index++))
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

    for server_info in "${PATROL_SERVERS[@]}"; do
        read -r alias ip port user key password group_tags <<< "$server_info"
        local result_file="$TEMP_DIR/${alias}_result.json"
        
        if [[ -f "$result_file" ]]; then
            cat >> "$txt_report" <<EOF

[服务器: $alias ($ip)]
所属组: $group_tags
--------------------------------------------------
系统信息:
  操作系统: $(jq -r '.system_info.os_version' "$result_file" 2>/dev/null || echo "N/A")
  内核版本: $(jq -r '.system_info.kernel_version' "$result_file" 2>/dev/null || echo "N/A")
  运行时长: $(jq -r '.system_info.uptime' "$result_file" 2>/dev/null || echo "N/A")
  CPU架构:  $(jq -r '.system_info.cpu_arch' "$result_file" 2>/dev/null || echo "N/A")

资源信息:
  CPU使用率:  $(jq -r '.resource_info.cpu.usage' "$result_file" 2>/dev/null || echo "N/A")% [$(jq -r '.resource_info.cpu.alarm_status' "$result_file" 2>/dev/null || echo "normal")]
  内存使用率: $(jq -r '.resource_info.memory.usage_percent' "$result_file" 2>/dev/null || echo "N/A")% [$(jq -r '.resource_info.memory.alarm_status' "$result_file" 2>/dev/null || echo "normal")]

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
