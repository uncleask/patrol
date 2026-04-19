#!/bin/bash

# 中心机主脚本 - Patrol 系统巡检工具

# 配置文件路径
SCRIPT_DIR="$(dirname "$0")"
CONFIG_DIR="$SCRIPT_DIR/conf"
PATROL_SERVERS_CONF="$CONFIG_DIR/servers.conf"
PATROL_GROUPS_CONF="$CONFIG_DIR/check_groups.conf"
PATROL_CHECKS_CONF="$CONFIG_DIR/checks.conf"

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
    echo "  -o, --output FORMAT 输出格式 (json|html|txt)，默认 all"
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
    if [[ ! -f "$PATROL_SERVERS_CONF" ]]; then
        echo -e "${RED}错误: 服务器配置文件 $PATROL_SERVERS_CONF 不存在${NC}"
        echo "错误: 服务器配置文件 $PATROL_SERVERS_CONF 不存在" >> "$LOG_FILE"
        exit 1
    fi

    PATROL_SERVERS=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        # 解析服务器配置（格式：别名:IP:端口:用户:密钥:密码:组标签）
        IFS=":" read -r alias ip port user key password group_tags <<< "$line"
        
        # 如果指定了组，只添加该组的服务器
        if [[ -n "$GROUP" ]]; then
            if [[ " $group_tags " =~ " $GROUP " ]]; then
                PATROL_SERVERS+=("$alias $ip $port $user $key $password $group_tags")
            fi
        else
            PATROL_SERVERS+=("$alias $ip $port $user $key $password $group_tags")
        fi
    done < "$PATROL_SERVERS_CONF"

    if [[ ${#PATROL_SERVERS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}警告: 没有找到符合条件的服务器${NC}"
        echo "警告: 没有找到符合条件的服务器" >> "$LOG_FILE"
        exit 0
    fi

    echo "INFO: 读取到 ${#PATROL_SERVERS[@]} 台服务器" >> "$LOG_FILE"
}

# 读取检查组配置
read_groups() {
    echo "INFO: 开始读取检查组配置" >> "$LOG_FILE"
    if [[ ! -f "$PATROL_GROUPS_CONF" ]]; then
        echo -e "${RED}错误: 检查组配置文件 $PATROL_GROUPS_CONF 不存在${NC}"
        echo "错误: 检查组配置文件 $PATROL_GROUPS_CONF 不存在" >> "$LOG_FILE"
        exit 1
    fi
    echo "INFO: 检查组配置文件存在: $PATROL_GROUPS_CONF" >> "$LOG_FILE"

    PATROL_GROUPS=()
    echo "INFO: 开始解析检查组配置" >> "$LOG_FILE"
    
    # 使用临时文件方法，避免while循环中的变量问题
    _tmp_group_file="$TEMP_DIR/.temp_group_$$"
    awk -F: '/^[^#]/ && NF>1 {print $1 " " $2}' "$PATROL_GROUPS_CONF" > "$_tmp_group_file"
    
    # 直接通过索引读取
    i=0
    while true; do
        # 使用sed读取第i+1行
        _temp_line=$(sed -n "$((i+1))p" "$_tmp_group_file")
        if [[ -z "$_temp_line" ]]; then
            break
        fi
        PATROL_GROUPS[i]="$_temp_line"
        echo "INFO: 读取到组: $_temp_line" >> "$LOG_FILE"
        ((i++))
    done
    
    # 清理临时文件
    rm -f "$_tmp_group_file"

    echo "INFO: 读取到 ${#PATROL_GROUPS[@]} 个检查组" >> "$LOG_FILE"
    echo "INFO: 检查组配置读取完成" >> "$LOG_FILE"
}

# 读取检查项配置
read_checks() {
    if [[ ! -f "$PATROL_CHECKS_CONF" ]]; then
        echo -e "${RED}错误: 检查项配置文件 $PATROL_CHECKS_CONF 不存在${NC}"
        echo "错误: 检查项配置文件 $PATROL_CHECKS_CONF 不存在" >> "$LOG_FILE"
        exit 1
    fi

    PATROL_CHECKS=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        # 解析检查项配置（格式：名称:类型:命令 或 threshold:名称:警告,严重）
        IFS=":" read -r type name rest <<< "$line"
        if [[ "$type" == "threshold" ]]; then
            IFS="," read -r warn crit <<< "$rest"
            PATROL_CHECKS+=("$name threshold $warn $crit")
        else
            PATROL_CHECKS+=("$type $name $rest")
        fi
    done < "$PATROL_CHECKS_CONF"

    echo "INFO: 读取到 ${#PATROL_CHECKS[@]} 个检查项" >> "$LOG_FILE"
}

# 根据组标签生成主机配置文件
generate_host_config() {
    local server_info="$1"
    read -r alias ip port user key password group_tags <<< "$server_info"
    
    # 确保临时目录存在
    mkdir -p "$TEMP_DIR"
    
    local config_file="$TEMP_DIR/${alias}_config.json"
    
    # 构建配置对象
    echo "{" > "$config_file"
    echo "  \"alias\": \"$alias\"," >> "$config_file"
    echo "  \"ip\": \"$ip\"," >> "$config_file"
    echo "  \"port\": \"$port\"," >> "$config_file"
    echo "  \"user\": \"$user\"," >> "$config_file"
    echo "  \"key\": \"$key\"," >> "$config_file"
    echo "  \"password\": \"$password\"," >> "$config_file"
    echo "  \"groups\": \"$group_tags\"," >> "$config_file"
    echo "  \"checks\": [" >> "$config_file"
    
    local first=true
    # 遍历所有组
    for group_info in "${PATROL_GROUPS[@]}"; do
        read -r group checks <<< "$group_info"
        # 检查服务器是否属于该组
        if [[ " $group_tags " =~ " $group " ]]; then
            # 分割检查项
            IFS="," read -ra check_items <<< "$checks"
            for check in "${check_items[@]}"; do
                # 查找检查项配置
                for check_info in "${PATROL_CHECKS[@]}"; do
                    read -r check_type check_name check_args <<< "$check_info"
                    if [[ "$check_name" == "$check" ]]; then
                        if [[ "$first" == true ]]; then
                            first=false
                        else
                            echo "  ," >> "$config_file"
                        fi
                        echo "    {" >> "$config_file"
                        echo "      \"name\": \"$check_name\"," >> "$config_file"
                        echo "      \"type\": \"$check_type\"," >> "$config_file"
                        echo "      \"args\": \"$check_args\"" >> "$config_file"
                        echo "    }" >> "$config_file"
                        break
                    fi
                done
            done
        fi
    done
    
    echo "  ]" >> "$config_file"
    echo "}" >> "$config_file"
    
    echo "$config_file"
}

# 执行远程检查
execute_remote_check() {
    local server_info="$1"
    read -r alias ip port user key password group_tags <<< "$server_info"
    
    local config_file=$(generate_host_config "$server_info")
    local result_file="$TEMP_DIR/${alias}_result.json"
    local remote_config_file="/tmp/host_${ip}_patrol.conf"
    
    # 复制远程脚本和配置文件到目标服务器（使用指定的密钥文件）
    scp -i "$key" -P "$port" "$REMOTE_SCRIPT" "$config_file" "$user@$ip:/tmp/" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误: 无法复制文件到服务器 $alias ($ip)${NC}"
        echo "错误: 无法复制文件到服务器 $alias ($ip)" >> "$LOG_FILE"
        return 1
    fi
    
    # 重命名配置文件（使用指定的密钥文件）
    ssh -i "$key" -p "$port" "$user@$ip" "mv /tmp/$(basename "$config_file") $remote_config_file" > /dev/null 2>&1
    
    # 设置执行权限（使用指定的密钥文件）
    ssh -i "$key" -p "$port" "$user@$ip" "chmod +x /tmp/remote_collector.sh" > /dev/null 2>&1
    
    # 执行远程检查（使用指定的密钥文件）
    ssh -i "$key" -p "$port" "$user@$ip" "/tmp/remote_collector.sh $remote_config_file" > "$result_file" 2>&1
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误: 无法执行远程检查在服务器 $alias ($ip)${NC}"
        echo "错误: 无法执行远程检查在服务器 $alias ($ip)" >> "$LOG_FILE"
        return 1
    fi
    
    # 清理远程文件（使用指定的密钥文件）
    ssh -i "$key" -p "$port" "$user@$ip" "rm -f /tmp/remote_collector.sh $remote_config_file" > /dev/null 2>&1
    
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
        # 控制并发数
        while [[ $running -ge $PARALLEL ]]; do
            sleep 1
            running=$(jobs -r | wc -l)
        done
        
        # 后台执行
        execute_remote_check "$server_info" &
        running=$((running + 1))
        
        # 检查是否有任务完成
        wait -n 2>/dev/null && running=$((running - 1))
    done
    
    # 等待所有任务完成
    wait
    
    echo -e "${GREEN}所有服务器检查完成${NC}"
    echo "INFO: 所有服务器检查完成" >> "$LOG_FILE"
}

# 合并所有结果
generate_combined_json() {
    local report_file="$OUTPUT_DIR/patrol_report_$(date +%Y%m%d_%H%M%S).json"
    
    # 构建 JSON 结构
    echo "{" > "$report_file"
    echo "  \"timestamp\": \"$(date '+%Y-%m-%dT%H:%M:%S')\"," >> "$report_file"
    echo "  \"servers\": [" >> "$report_file"
    
    local first=true
    for server_info in "${PATROL_SERVERS[@]}"; do
        read -r alias ip port user key password group_tags <<< "$server_info"
        local result_file="$TEMP_DIR/${alias}_result.json"
        
        if [[ -f "$result_file" ]]; then
            if [[ "$first" == true ]]; then
                first=false
            else
                echo "  ," >> "$report_file"
            fi
            
            echo "    {" >> "$report_file"
            echo "      \"alias\": \"$alias\"," >> "$report_file"
            echo "      \"ip\": \"$ip\"," >> "$report_file"
            echo "      \"groups\": \"$group_tags\"," >> "$report_file"
            echo "      \"results\": " >> "$report_file"
            cat "$result_file" >> "$report_file"
            echo "    }" >> "$report_file"
        fi
    done
    
    echo "  ]" >> "$report_file"
    echo "}" >> "$report_file"
    
    # 保存报告文件路径到变量
    local result="$report_file"
    
    # 输出提示信息到标准错误（stderr），这样不会影响返回值
    echo -e "${GREEN}JSON 报告生成: $result${NC}" >&2
    echo "INFO: JSON 报告生成: $result" >> "$LOG_FILE"
    
    # 只返回报告文件路径（标准输出 stdout）
    echo "$result"
}

# 生成 HTML 报告
generate_html_report() {
    local json_report="$1"
    local report_file="${json_report%.json}.html"
    
    # 生成 HTML 报告
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>系统巡检报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .server { border: 1px solid #ddd; border-radius: 5px; padding: 15px; margin-bottom: 20px; }
        .server h2 { color: #0066cc; margin-top: 0; }
        .check-item { margin: 10px 0; padding: 10px; border-left: 4px solid #ccc; }
        .ok { border-left-color: #4CAF50; background-color: #f9fff9; }
        .warn { border-left-color: #ff9800; background-color: #fff9f0; }
        .crit { border-left-color: #f44336; background-color: #fff0f0; }
        .summary { margin-top: 20px; padding: 15px; background-color: #f0f8ff; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>系统巡检报告</h1>
    <div class="summary">
        <p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
        <p>巡检服务器数量: ${#PATROL_SERVERS[@]}</p>
    </div>
EOF
    
    # 使用 jq 解析 JSON 并生成 HTML
    jq -r 'foreach .servers[] as $server (null; null; 
        "<div class=\"server\">\n" +
        "  <h2>" + $server.alias + " (" + $server.ip + ")</h2>\n" +
        "  <p>所属组: " + $server.groups + "</p>\n" +
        "  <div class=\"checks\">\n" +
        foreach $server.results[] as $check (null; null; 
            "    <div class=\"check-item " +
            (if $check.status == "OK" then "ok" elif $check.status == "WARNING" then "warn" else "crit" end) +
            "\">\n" +
            "      <strong>" + $check.name + "</strong>: " + $check.value + "\n" +
            (if $check.status != "OK" then "      <em>状态: " + $check.status + "</em>\n" else "" end) +
            "    </div>\n"
        ) +
        "  </div>\n" +
        "</div>\n"
    )' "$json_report" >> "$report_file"
    
    cat >> "$report_file" << EOF
</body>
</html>
EOF
    
    echo -e "${GREEN}HTML 报告生成: $report_file${NC}"
    echo "INFO: HTML 报告生成: $report_file" >> "$LOG_FILE"
}

# 生成 TXT 报告
generate_txt_report() {
    local json_report="$1"
    local report_file="${json_report%.json}.txt"
    
    # 生成 TXT 报告
    cat > "$report_file" << EOF
==================================================
系统巡检报告
==================================================
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
巡检服务器数量: ${#PATROL_SERVERS[@]}
==================================================
EOF
    
    # 使用 jq 解析 JSON 并生成 TXT
    jq -r 'foreach .servers[] as $server (null; null; 
        "\n[服务器: " + $server.alias + " (" + $server.ip + ")]\n" +
        "所属组: " + $server.groups + "\n" +
        "--------------------------------------------------\n" +
        foreach $server.results[] as $check (null; null; 
            $check.name + ": " + $check.value + 
            (if $check.status != "OK" then " [" + $check.status + "]" else "" end) + "\n"
        ) +
        "--------------------------------------------------\n"
    )' "$json_report" >> "$report_file"
    
    echo -e "${GREEN}TXT 报告生成: $report_file${NC}"
    echo "INFO: TXT 报告生成: $report_file" >> "$LOG_FILE"
}

# 生成报告
generate_reports() {
    local json_report=$(generate_combined_json)
    
    case "$OUTPUT_FORMAT" in
        "json")
            # 只生成 JSON 报告
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

# 清理临时文件
cleanup() {
    rm -rf "$TEMP_DIR"
    echo "INFO: 清理临时文件" >> "$LOG_FILE"
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"
    echo "INFO: 参数解析完成" >> "$LOG_FILE"
    
    # 读取配置
    read_servers
    echo "INFO: 服务器配置读取完成" >> "$LOG_FILE"
    
    read_groups
    echo "INFO: 检查组配置读取完成" >> "$LOG_FILE"
    
    read_checks
    echo "INFO: 检查项配置读取完成" >> "$LOG_FILE"
    
    # 确保输出目录存在
    mkdir -p "$OUTPUT_DIR"
    echo "INFO: 输出目录准备完成" >> "$LOG_FILE"
    
    # 执行检查
    run_parallel_checks
    echo "INFO: 检查执行完成" >> "$LOG_FILE"
    
    # 生成报告
    generate_reports
    echo "INFO: 报告生成完成" >> "$LOG_FILE"
    
    # 清理
    cleanup
    echo "INFO: 清理完成" >> "$LOG_FILE"
    
    echo -e "${GREEN}巡检完成！${NC}"
    echo "INFO: 巡检完成" >> "$LOG_FILE"
}

# 执行主函数
main "$@"
