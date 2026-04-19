#!/bin/bash

# 远程执行脚本 - Patrol 系统巡检工具

# 检查是否提供了配置文件
if [[ $# -eq 1 ]]; then
    CONFIG_FILE="$1"
elif [[ -f "/tmp/host_${HOST_IP}_patrol.conf" ]]; then
    CONFIG_FILE="/tmp/host_${HOST_IP}_patrol.conf"
elif [[ -f "./host_${HOST_IP}_patrol.conf" ]]; then
    CONFIG_FILE="./host_${HOST_IP}_patrol.conf"
else
    # 尝试获取主机 IP
    HOST_IP=$(hostname -I | awk '{print $1}')
    if [[ -f "/tmp/host_${HOST_IP}_patrol.conf" ]]; then
        CONFIG_FILE="/tmp/host_${HOST_IP}_patrol.conf"
    elif [[ -f "./host_${HOST_IP}_patrol.conf" ]]; then
        CONFIG_FILE="./host_${HOST_IP}_patrol.conf"
    else
        echo "错误: 找不到配置文件"
        exit 1
    fi
fi

# 检查配置文件是否存在
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 读取配置文件
CONFIG=$(cat "$CONFIG_FILE")

# 解析检查项
CHECKS=$(echo "$CONFIG" | jq -r '.checks[]')

# 解析阈值配置
THRESHOLDS=()
while IFS= read -r line || [[ -n "$line" ]]; do
    # 跳过空行和注释
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    
    # 解析阈值配置（格式：threshold:名称:警告,严重）
    if [[ "$line" =~ ^threshold: ]]; then
        IFS=":" read -r type name rest <<< "$line"
        IFS="," read -r warn crit <<< "$rest"
        THRESHOLDS+=("$name $warn $crit")
    fi
    
done < "/tmp/$(basename "$CONFIG_FILE")"

# 检查状态
check_status() {
    local name="$1"
    local value="$2"
    
    # 查找阈值
    for threshold in "${THRESHOLDS[@]}"; do
        read -r threshold_name warn crit <<< "$threshold"
        if [[ "$threshold_name" == "$name" ]]; then
            # 使用 awk 进行数值比较
            if awk "BEGIN {exit !($value >= $crit)}"; then
                echo "serious"
            elif awk "BEGIN {exit !($value >= $warn)}"; then
                echo "warn"
            else
                echo "normal"
            fi
            return
        fi
    done
    
    # 默认状态
    echo "normal"
}

# 采集 CPU 信息
collect_cpu() {
    # 使用 top -bn1 采集 CPU 信息，用 awk 计算使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
    echo "$cpu_usage"
}

# 采集内存信息
collect_memory() {
    # 使用 free -m 采集内存信息，用 awk 计算使用率
    local memory_usage=$(free -m | awk '/Mem:/ {print $3/$2*100}')
    echo "$memory_usage"
}

# 采集磁盘信息
collect_disk() {
    # 执行 df -h 命令
    local disk_info=$(df -h | grep '^/dev/')
    echo "$disk_info"
}

# 采集进程信息
collect_process() {
    # 执行 ps 命令
    local process_info=$(ps aux | head -20)
    echo "$process_info"
}

# 采集 Docker 信息
collect_docker() {
    # 执行 docker 命令
    local docker_info=""
    if command -v docker &> /dev/null; then
        docker_info=$(docker ps -a)
    else
        docker_info="Docker not installed"
    fi
    echo "$docker_info"
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
        local status="normal"
        
        case "$name" in
            "cpu_usage")
                value=$(collect_cpu)
                status=$(check_status "$name" "$value")
                ;;
            "memory_usage")
                value=$(collect_memory)
                status=$(check_status "$name" "$value")
                ;;
            "disk_usage")
                value=$(collect_disk)
                status=$(check_status "$name" "$value")
                ;;
            "process_count")
                value=$(ps aux | wc -l)
                status=$(check_status "$name" "$value")
                ;;
            "docker_containers")
                value=$(docker ps -q | wc -l 2>/dev/null || echo "N/A")
                status=$(check_status "$name" "$value")
                ;;
            "docker_status")
                value=$(docker info 2>/dev/null | grep 'Docker Engine' | wc -l 2>/dev/null || echo "N/A")
                status=$(check_status "$name" "$value")
                ;;
            *)
                # 执行自定义命令
                value=$(eval "$args" 2>/dev/null || echo "N/A")
                status=$(check_status "$name" "$value")
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
    
    # 添加默认检查项（如果配置中没有）
    local default_checks=(
        "cpu_usage"
        "memory_usage"
        "disk_usage"
        "process_count"
        "docker_containers"
        "docker_status"
    )
    
    for check_name in "${default_checks[@]}"; do
        # 检查是否已经存在
        local exists=false
        echo "$CHECKS" | while IFS= read -r check; do
            local name=$(echo "$check" | jq -r '.name')
            if [[ "$name" == "$check_name" ]]; then
                exists=true
                break
            fi
        done
        
        if [[ "$exists" == false ]]; then
            echo ","
            local value="N/A"
            local status="normal"
            
            case "$check_name" in
                "cpu_usage")
                    value=$(collect_cpu)
                    status=$(check_status "$check_name" "$value")
                    ;;
                "memory_usage")
                    value=$(collect_memory)
                    status=$(check_status "$check_name" "$value")
                    ;;
                "disk_usage")
                    value=$(collect_disk)
                    status=$(check_status "$check_name" "$value")
                    ;;
                "process_count")
                    value=$(ps aux | wc -l)
                    status=$(check_status "$check_name" "$value")
                    ;;
                "docker_containers")
                    value=$(docker ps -q | wc -l 2>/dev/null || echo "N/A")
                    status=$(check_status "$check_name" "$value")
                    ;;
                "docker_status")
                    value=$(docker info 2>/dev/null | grep 'Docker Engine' | wc -l 2>/dev/null || echo "N/A")
                    status=$(check_status "$check_name" "$value")
                    ;;
            esac
            
            printf "  {\"name\": \"%s\", \"value\": \"%s\", \"status\": \"%s\"}" "$check_name" "$value" "$status"
        fi
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
