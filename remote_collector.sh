#!/bin/bash

# 远程执行脚本 - Patrol 系统巡检工具 (新版本)

# ========== 工具函数 ==========

json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo -n "$str"
}

read_thresholds() {
    THRESHOLDS=()
    local config_file="$1"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^threshold: ]]; then
            IFS=":" read -r type name rest <<< "$line"
            IFS="," read -r warn crit <<< "$rest"
            THRESHOLDS["$name"]="warn=$warn crit=$crit"
        fi
    done < "$config_file"
}

# 读取检查项配置
read_checks() {
    declare -A CHECKS
    local config_file="$1"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ ! "$line" =~ ^threshold: ]]; then
            IFS=":" read -r name type command <<< "$line"
            CHECKS["$name"]="type=$type command=$command"
        fi
    done < "$config_file"
}

check_alarm() {
    local name="$1"
    local value="$2"
    local threshold="${THRESHOLDS[$name]}"
    
    if [[ -z "$threshold" ]]; then
        echo "normal"
        return
    fi
    
    local warn=$(echo "$threshold" | awk '{print $1}' | cut -d'=' -f2)
    local crit=$(echo "$threshold" | awk '{print $2}' | cut -d'=' -f2)
    
    if awk "BEGIN {exit !($value >= $crit)}"; then
        echo "serious"
    elif awk "BEGIN {exit !($value >= $warn)}"; then
        echo "alarm"
    else
        echo "normal"
    fi
}

# ========== 系统信息采集 ==========

collect_system_info() {
    local system_output=""
    local kernel_output=""
    local uptime_output=""
    local cpu_arch_output=""
    
    # 系统版本
    if [[ -f /etc/os-release ]]; then
        local pretty_name=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"')
        system_output="$pretty_name"
    else
        system_output="unknown"
    fi
    
    # 内核版本
    kernel_output=$(uname -r)
    
    # 运行时长
    uptime_output=$(uptime | awk -F'[ ,]+' '{print $3,$4}')
    
    # CPU架构
    cpu_arch_output=$(uname -m)
    if [[ "$cpu_arch_output" == "x86_64" || "$cpu_arch_output" == "aarch64" ]]; then
        cpu_arch_output="64位"
    else
        cpu_arch_output="32位"
    fi
    
    cat <<EOF
  "system_info": {
    "os_version": "$(json_escape "$system_output")",
    "kernel_version": "$(json_escape "$kernel_output")",
    "uptime": "$(json_escape "$uptime_output")",
    "cpu_arch": "$(json_escape "$cpu_arch_output")"
  }
EOF
}

# ========== 资源信息采集 ==========

collect_resource_info() {
    # CPU 使用率
    local cpu_usage=$(top -bn1 | grep 'Cpu(s)' | awk '{print 100 - $8}')
    local cpu_alarm=$(check_alarm "system_cpu" "$cpu_usage")
    
    # 内存使用率
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/Mem:/ {print $3}')
    local mem_usage=$(awk "BEGIN {print ($mem_used/$mem_total)*100}")
    local mem_alarm=$(check_alarm "system_mem" "$mem_usage")
    
    # 磁盘信息
    local disk_array=()
    while read -r line; do
        [[ "$line" =~ ^Filesystem ]] && continue
        local fs=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')
        local use_pct=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        local mount=$(echo "$line" | awk '{print $6}')
        local disk_alarm=$(check_alarm "system_disk" "$use_pct")
        
        disk_array+=("{\"filesystem\":\"$(json_escape "$fs")\",\"size\":\"$(json_escape "$size")\",\"used\":\"$(json_escape "$used")\",\"available\":\"$(json_escape "$avail")\",\"use_percent\":$use_pct,\"mount_point\":\"$(json_escape "$mount")\",\"alarm_status\":\"$disk_alarm\"}")
    done < <(df -h)
    
    local disks=$(IFS=, ; echo "${disk_array[*]}")
    
    cat <<EOF
  "resource_info": {
    "cpu": {
      "usage": $cpu_usage,
      "alarm_status": "$cpu_alarm"
    },
    "memory": {
      "total_mb": $mem_total,
      "used_mb": $mem_used,
      "usage_percent": $mem_usage,
      "alarm_status": "$mem_alarm"
    },
    "disks": [$disks]
  }
EOF
}

# ========== 网络信息采集 ==========

collect_network_info() {
    local interfaces=$(ip -json addr 2>/dev/null || echo "[]")
    local routes=$(ip -json route 2>/dev/null || echo "[]")
    local firewall_output=""
    
    if command -v iptables &> /dev/null; then
        firewall_output=$(iptables -L -n -v 2>&1 | head -100)
    else
        firewall_output="iptables not available"
    fi
    
    cat <<EOF
  "network_info": {
    "interfaces": $(json_escape "$(ip addr 2>&1)"),
    "routes": $(json_escape "$(ip route 2>&1)"),
    "firewall": "$(json_escape "$firewall_output")"
  }
EOF
}

# ========== 磁盘IO采集 ==========

collect_disk_io() {
    local vmstat_output=$(vmstat 1 3 2>&1)
    local iostat_output=""
    if command -v iostat &> /dev/null; then
        iostat_output=$(iostat -x 1 2 2>&1)
    else
        iostat_output="iostat not available"
    fi
    
    cat <<EOF
  "disk_io": {
    "vmstat": "$(json_escape "$vmstat_output")",
    "iostat": "$(json_escape "$iostat_output")"
  }
EOF
}

# ========== 应用进程和容器采集 ==========

collect_app_info() {
    local config_file="$1"
    local process_array=()
    local docker_array=()
    
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        if [[ "$line" =~ ^process: ]]; then
            IFS=":" read -r type proc_name service_name <<< "$line"
            
            local ps_line=$(ps aux | grep -v grep | grep "$proc_name" | head -1)
            if [[ -n "$ps_line" ]]; then
                local pid=$(echo "$ps_line" | awk '{print $2}')
                local cpu_pct=$(echo "$ps_line" | awk '{print $3}')
                local mem_pct=$(echo "$ps_line" | awk '{print $4}')
                local state=$(ps -p $pid -o state= 2>/dev/null || echo "unknown")
                local etime=$(ps -p $pid -o etime= 2>/dev/null || echo "unknown")
                local cpu_alarm=$(check_alarm "process_cpu" "$cpu_pct")
                local mem_alarm=$(check_alarm "process_mem" "$mem_pct")
                
                process_array+=("{\"process_name\":\"$(json_escape "$proc_name")\",\"service_name\":\"$(json_escape "$service_name")\",\"pid\":$pid,\"state\":\"$(json_escape "$state")\",\"running_time\":\"$(json_escape "$etime")\",\"cpu_usage\":$cpu_pct,\"memory_usage\":$mem_pct,\"cpu_alarm_status\":\"$cpu_alarm\",\"memory_alarm_status\":\"$mem_alarm\",\"running\":true}")
            else
                process_array+=("{\"process_name\":\"$(json_escape "$proc_name")\",\"service_name\":\"$(json_escape "$service_name")\",\"running\":false}")
            fi
        elif [[ "$line" =~ ^docker: ]]; then
            IFS=":" read -r type container_name service_name <<< "$line"
            
            if command -v docker &> /dev/null; then
                local container_id=$(docker ps -a --filter "name=$container_name" --format "{{.ID}}" 2>/dev/null | head -1)
                if [[ -n "$container_id" ]]; then
                    local state=$(docker inspect "$container_id" --format "{{.State.Status}}" 2>/dev/null)
                    local docker_stats=$(docker stats --no-stream "$container_id" --format "{{.CPUPerc}},{{.MemPerc}},{{.MemUsage}}" 2>/dev/null)
                    local cpu_pct=$(echo "$docker_stats" | cut -d',' -f1 | sed 's/%//')
                    local mem_pct=$(echo "$docker_stats" | cut -d',' -f2 | sed 's/%//')
                    local mem_usage=$(echo "$docker_stats" | cut -d',' -f3)
                    local size=$(docker inspect "$container_id" --format "{{.SizeRw}}" 2>/dev/null | numfmt --to=iec --suffix=B 2>/dev/null || echo "unknown")
                    local cpu_alarm=$(check_alarm "process_cpu" "$cpu_pct")
                    local mem_alarm=$(check_alarm "process_mem" "$mem_pct")
                    
                    docker_array+=("{\"container_name\":\"$(json_escape "$container_name")\",\"service_name\":\"$(json_escape "$service_name")\",\"container_id\":\"$(json_escape "$container_id")\",\"state\":\"$(json_escape "$state")\",\"cpu_usage\":${cpu_pct:-0},\"memory_usage\":${mem_pct:-0},\"memory_used\":\"$(json_escape "$mem_usage")\",\"disk_used\":\"$(json_escape "$size")\",\"cpu_alarm_status\":\"$cpu_alarm\",\"memory_alarm_status\":\"$mem_alarm\"}")
                else
                    docker_array+=("{\"container_name\":\"$(json_escape "$container_name")\",\"service_name\":\"$(json_escape "$service_name")\",\"running\":false}")
                fi
            else
                docker_array+=("{\"container_name\":\"$(json_escape "$container_name")\",\"service_name\":\"$(json_escape "$service_name")\",\"docker_unavailable\":true}")
            fi
        fi
    done < "$config_file"
    
    local processes=$(IFS=, ; echo "${process_array[*]}")
    local dockers=$(IFS=, ; echo "${docker_array[*]}")
    
    cat <<EOF
  "app_info": {
    "processes": [${processes:-}],
    "docker_containers": [${dockers:-}]
  }
EOF
}

# ========== 系统日志采集 ==========

collect_log_info() {
    local config_file="$1"
    local log_array=()
    
    while IFS= read -r log_path; do
        [[ -z "$log_path" || "$log_path" =~ ^# ]] && continue
        
        if [[ -f "$log_path" ]]; then
            local log_size=$(du -m "$log_path" | awk '{print $1}')
            local recent_logs=$(tail -10 "$log_path" 2>/dev/null || echo "Cannot read log file")
            
            log_array+=("{\"log_path\":\"$(json_escape "$log_path")\",\"size_mb\":$log_size,\"recent_lines\":\"$(json_escape "$recent_logs")\"}")
        else
            log_array+=("{\"log_path\":\"$(json_escape "$log_path")\",\"file_not_found\":true}")
        fi
    done < "$config_file"
    
    local logs=$(IFS=, ; echo "${log_array[*]}")
    
    cat <<EOF
  "log_info": {
    "log_files": [${logs:-}]
  }
EOF
}

# ========== 主函数 ==========

main() {
    local apps_config="$1"
    local logs_config="$2"
    local checks_config="$3"
    
    # 读取阈值配置
    read_thresholds "$checks_config"
    
    # 开始输出JSON
    echo "{"
    
    # 系统信息
    collect_system_info
    echo ","
    
    # 资源信息
    collect_resource_info
    echo ","
    
    # 网络信息
    collect_network_info
    echo ","
    
    # 磁盘IO
    collect_disk_io
    echo ","
    
    # 应用信息
    collect_app_info "$apps_config"
    echo ","
    
    # 检查项信息
    collect_checks "$checks_config"
    echo ","
    
    # 日志信息
    collect_log_info "$logs_config"
    
    echo "}"
}

# 收集检查项结果
collect_checks() {
    local config_file="$1"
    local -A CHECKS
    
    # 读取检查项配置
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ ! "$line" =~ ^threshold: ]]; then
            IFS=":" read -r name type command <<< "$line"
            CHECKS["$name"]="type=$type command=$command"
        fi
    done < "$config_file"
    
    local check_array=()
    
    for check_name in "${!CHECKS[@]}"; do
        local check_info="${CHECKS[$check_name]}"
        local check_type=$(echo "$check_info" | awk '{print $1}' | cut -d'=' -f2)
        local check_command=$(echo "$check_info" | awk '{$1=""; print substr($0,2)}' | cut -d'=' -f2-)
        
        local check_value=$(eval "$check_command" 2>/dev/null || echo "N/A")
        local check_status="normal"
        
        # 检查是否有阈值配置
        if [[ -n "${THRESHOLDS[$check_name]}" ]]; then
            # 提取数值进行阈值检查
            local numeric_value=$(echo "$check_value" | grep -E "[0-9]+(\.[0-9]+)?" | head -1 | sed 's/[^0-9.]//g')
            if [[ -n "$numeric_value" ]]; then
                check_status=$(check_alarm "$check_name" "$numeric_value")
            fi
        fi
        
        check_array+=("{\"name\":\"$(json_escape "$check_name")\",\"type\":\"$(json_escape "$check_type")\",\"value\":\"$(json_escape "$check_value")\",\"status\":\"$check_status\"}")
    done
    
    local checks=$(IFS=, ; echo "${check_array[*]}")
    
    cat <<EOF
  "checks": [${checks:-}]
EOF
}

# 执行主函数
if [[ $# -eq 3 ]]; then
    main "$1" "$2" "$3"
else
    # 默认配置文件名
    SCRIPT_DIR="$(dirname "$0")"
    main "$SCRIPT_DIR/conf/apps.conf" "$SCRIPT_DIR/conf/logs.conf" "$SCRIPT_DIR/conf/checks.conf"
fi
