#!/bin/bash

# 远程执行脚本 - Patrol 系统巡检工具

# 检查是否提供了配置文件
if [[ $# -ne 1 ]]; then
    echo "错误: 需要提供配置文件路径"
    exit 1
fi

CONFIG_FILE="$1"

# 检查配置文件是否存在
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 读取配置文件
CONFIG=$(cat "$CONFIG_FILE")

# 解析检查项
CHECKS=$(echo "$CONFIG" | jq -r '.checks[]')

# 检查状态
check_status() {
    local value="$1"
    local warn="$2"
    local crit="$3"
    
    # 使用 awk 进行数值比较
    if awk "BEGIN {exit !($value >= $crit)}"; then
        echo "CRITICAL"
    elif awk "BEGIN {exit !($value >= $warn)}"; then
        echo "WARNING"
    else
        echo "OK"
    fi
}

# 执行检查
execute_checks() {
    local results=()
    local first=true
    
    echo "["
    
    # 遍历检查项
    echo "$CHECKS" | while IFS= read -r check; do
        local name=$(echo "$check" | jq -r '.name')
        local type=$(echo "$check" | jq -r '.type')
        local args=$(echo "$check" | jq -r '.args')
        
        local value="N/A"
        local status="OK"
        
        case "$type" in
            "cpu_usage")
                value=$(100 - $(vmstat 1 2 | tail -n 1 | awk '{print $15}') 2>/dev/null || echo "N/A")
                ;;
            "memory_usage")
                value=$(free -m | awk '/Mem:/ {print $3/$2*100}' 2>/dev/null || echo "N/A")
                ;;
            "disk_usage")
                value=$(df -h | awk '/\/dev\/[^\s]+\s+\/\s+/ {print $5}' | sed 's/%//' 2>/dev/null || echo "N/A")
                ;;
            "process_count")
                value=$(ps aux | wc -l 2>/dev/null || echo "N/A")
                ;;
            "docker_containers")
                value=$(docker ps -q | wc -l 2>/dev/null || echo "N/A")
                ;;
            "docker_status")
                value=$(docker info 2>/dev/null | grep 'Docker Engine' | wc -l 2>/dev/null || echo "N/A")
                ;;
            "threshold")
                # 执行自定义命令
                value=$(eval "$args" 2>/dev/null || echo "N/A")
                # 解析阈值
                IFS=" " read -r warn crit <<< "$args"
                if [[ "$value" != "N/A" ]]; then
                    status=$(check_status "$value" "$warn" "$crit")
                fi
                ;;
            *)
                # 执行自定义命令
                value=$(eval "$args" 2>/dev/null || echo "N/A")
                ;;
        esac
        
        # 处理空值
        if [[ -z "$value" ]]; then
            value="N/A"
        fi
        
        # 格式化输出
        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi
        
        # 输出 JSON 格式
        printf "  {\"name\": \"%s\", \"value\": \"%s\", \"status\": \"%s\"}" "$name" "$value" "$status"
    done
    
    echo "
]"
}

# 主函数
main() {
    execute_checks
}

# 执行主函数
main
