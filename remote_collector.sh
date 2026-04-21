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
    "interfaces": "$(json_escape "$(ip addr 2>&1)")",
    "routes": "$(json_escape "$(ip route 2>&1)")",
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
    local checks_config="$1"
    
    local processes=$(collect_process_info "$checks_config")
    local containers=$(collect_container_info "$checks_config")
    
    cat <<EOF
  "app_info": {
    "processes": [${processes:-}],
    "docker_containers": [${containers:-}]
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

# 收集服务器完整信息
collect_server_info() {
    local checks_config="$1"
    
    # 基本信息
    local time=$(date '+%Y-%m-%d %H:%M:%S')
    local hostip=$(hostname -I | awk '{print $1}')
    local hostname=$(hostname)
    local os=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"')
    local uptimeduration=$(uptime)
    
    # 系统启动时间（近似值）
    local uptimesince=$(date -d "$(uptime -s)" '+%Y-%m-%d %H:%M:%S')
    
    # CPU信息
    local cpu_info=$(top -bn1 | grep 'Cpu(s)')
    local cpu_usage=$(echo "$cpu_info" | awk '{print 100 - $8}')
    local sysusage=$(echo "$cpu_info" | awk '{print $2}' | sed 's/%//')
    local idle=$(echo "$cpu_info" | awk '{print $8}' | sed 's/%//')
    local iowait=$(echo "$cpu_info" | awk '{print $10}' | sed 's/%//')
    local avgload=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ //')
    local cpu_usestate=$(check_alarm "system_cpu" "$cpu_usage")
    
    # 内存信息
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/Mem:/ {print $3}')
    local mem_free=$(free -m | awk '/Mem:/ {print $4}')
    local mem_available=$(free -m | awk '/Mem:/ {print $7}')
    local mem_usage=$(awk "BEGIN {print ($mem_used/$mem_total)*100}")
    local mem_usestate=$(check_alarm "system_mem" "$mem_usage")
    
    # 交换空间信息
    local swap_total=$(free -m | awk '/Swap:/ {print $2}')
    local swap_used=$(free -m | awk '/Swap:/ {print $3}')
    local swap_free=$(free -m | awk '/Swap:/ {print $4}')
    local swap_usage=""
    if [[ $swap_total -gt 0 ]]; then
        swap_usage=$(awk "BEGIN {print ($swap_used/$swap_total)*100}")
    fi
    local swap_usestate="normal"
    
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
        local disk_usestate=$(check_alarm "system_disk" "$use_pct")
        
        disk_array+=(
            "{
                \"mounted\": \"$(json_escape "$mount")\",
                \"filesystem\": \"$(json_escape "$fs")\",
                \"total\": \"$(json_escape "$size")\",
                \"used\": \"$(json_escape "$used")\",
                \"available\": \"$(json_escape "$avail")\",
                \"usage\": $use_pct,
                \"usestate\": \"$disk_usestate\"}"
        )
    done < <(df -h)
    
    local disks=$(IFS=, ; echo "${disk_array[*]}")
    
    # 应用信息
    local apps_array=()
    local -A PROCESSES
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^process: ]]; then
            IFS=":" read -r type proc_name service_name <<< "$line"
            PROCESSES["$proc_name"]="$service_name"
        fi
    done < "$checks_config"
    
    for proc_name in "${!PROCESSES[@]}"; do
        local service_name="${PROCESSES[$proc_name]}"
        local ps_line=$(ps aux | grep -v grep | grep "$proc_name" | head -1)
        
        if [[ -n "$ps_line" ]]; then
                local user=$(echo "$ps_line" | awk '{print $1}')
                local pid=$(echo "$ps_line" | awk '{print $2}')
                local cpu_pct=$(echo "$ps_line" | awk '{print $3}')
                local mem_pct=$(echo "$ps_line" | awk '{print $4}')
                local etime=$(ps -p $pid -o etime= 2>/dev/null || echo "unknown")
                
                # 计算运行时间（秒）
                local runtime_sec=0
                if [[ "$etime" != "unknown" ]]; then
                    runtime_sec=$(ps -p $pid -o etimes= 2>/dev/null || echo 0)
                fi
                
                apps_array+=("{
                    \"name\": \"$(json_escape "$proc_name")\",
                    \"type\": \"vhost\",
                    \"user\": \"$(json_escape "$user")\",
                    \"pid\": \"$pid\",
                    \"cpuusage\": $cpu_pct,
                    \"memusage\": $mem_pct,
                    \"runtime\": \"$(json_escape "$etime")\",
                    \"runtime_sec\": $runtime_sec,
                    \"state\": \"running\"}")
            else
                apps_array+=("{
                    \"name\": \"$(json_escape "$proc_name")\",
                    \"type\": \"vhost\",
                    \"user\": \"\",
                    \"pid\": \"\",
                    \"cpuusage\": \"\",
                    \"memusage\": \"\",
                    \"runtime\": \"\",
                    \"runtime_sec\": \"\",
                    \"state\": \"stopped\"}")
            fi
    done
    
    local apps=$(IFS=, ; echo "${apps_array[*]}")
    
    # 容器信息
    local dockers_array=()
    local -A CONTAINERS
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^docker: ]]; then
            IFS=":" read -r type container_name service_name <<< "$line"
            CONTAINERS["$container_name"]="$service_name"
        fi
    done < "$checks_config"
    
    if command -v docker &> /dev/null; then
        for container_name in "${!CONTAINERS[@]}"; do
            local service_name="${CONTAINERS[$container_name]}"
            local container_id=$(docker ps -a --filter "name=$container_name" --format "{{.ID}}" 2>/dev/null | head -1)
            
            if [[ -n "$container_id" ]]; then
                local state=$(docker inspect "$container_id" --format "{{.State.Status}}" 2>/dev/null)
                local status=$(docker ps -a --filter "name=$container_name" 2>/dev/null | head -1)
                
                dockers_array+=("{
                    \"name\": \"$(json_escape "$container_name")\",
                    \"id\": \"CONTAINER\",
                    \"state\": \"$(json_escape "$state")\",
                    \"status\": \"$(json_escape "$status")\"}")
            else
                dockers_array+=("{
                    \"name\": \"$(json_escape "$container_name")\",
                    \"id\": \"\",
                    \"state\": \"not_found\",
                    \"status\": \"\"}")
            fi
        done
    else
        # Docker不可用
        for container_name in "${!CONTAINERS[@]}"; do
            dockers_array+=(
                "{
                    \"name\": \"$(json_escape "$container_name")\",
                    \"id\": \"\",
                    \"state\": \"not_found\",
                    \"status\": \"\"}"
            )
        done
    fi
    
    local dockers=$(IFS=, ; echo "${dockers_array[*]}")
    
    # 结果汇总
    local all_count=$((1 + 1 + ${#disk_array[@]} + ${#apps_array[@]} + ${#dockers_array[@]}))
    local normal_count=0
    local warn_count=0
    local serious_count=0
    local description=""
    
    # 检查CPU状态
    if [[ "$cpu_usestate" == "normal" ]]; then
        normal_count=$((normal_count + 1))
    elif [[ "$cpu_usestate" == "alarm" ]]; then
        warn_count=$((warn_count + 1))
        description+="<br/>【警告】CPU 使用率 ${cpu_usage}% ≥ 70%<br/>"
    else
        serious_count=$((serious_count + 1))
        description+="<br/>【严重】CPU 使用率 ${cpu_usage}% ≥ 85%<br/>"
    fi
    
    # 检查内存状态
    if [[ "$mem_usestate" == "normal" ]]; then
        normal_count=$((normal_count + 1))
    elif [[ "$mem_usestate" == "alarm" ]]; then
        warn_count=$((warn_count + 1))
        description+="<br/>【警告】内存使用率 ${mem_usage}% ≥ 70%<br/>"
    else
        serious_count=$((serious_count + 1))
        description+="<br/>【严重】内存使用率 ${mem_usage}% ≥ 85%<br/>"
    fi
    
    # 检查磁盘状态
    for ((i=0; i<${#disk_array[@]}; i++)); do
        normal_count=$((normal_count + 1))
    done
    
    # 检查应用状态
    for ((i=0; i<${#apps_array[@]}; i++)); do
        if [[ "${apps_array[$i]}" =~ "\"state\": \"running\"" ]]; then
            normal_count=$((normal_count + 1))
        else
            serious_count=$((serious_count + 1))
            local app_name=$(echo "${apps_array[$i]}" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
            description+="<br/>【严重】应用 $app_name 未运行<br/>"
        fi
    done
    
    # 检查容器状态
    if ! command -v docker &> /dev/null; then
        serious_count=$((serious_count + 1))
        description+="<br/>【严重】Docker 不可用<br/>"
    else
        for ((i=0; i<${#dockers_array[@]}; i++)); do
            if [[ "${dockers_array[$i]}" =~ "\"state\": \"running\"" ]]; then
                normal_count=$((normal_count + 1))
            else
                serious_count=$((serious_count + 1))
                local container_name=$(echo "${dockers_array[$i]}" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
                description+="<br/>【严重】Docker容器 $container_name 未找到<br/>"
            fi
        done
    fi
    
    if [[ $serious_count -eq 0 && $warn_count -eq 0 ]]; then
        description="【正常】"
    fi
    
    # 输出完整结构
    cat <<EOF
  {
    "time": "$time",
    "hostip": "$hostip",
    "hostname": "$hostname",
    "os": "$os",
    "uptimesince": "$uptimesince",
    "uptimeduration": "$uptimeduration",
    "cpu": {
      "usage": "$cpu_usage",
      "sysusage": "$sysusage",
      "idle": "$idle",
      "iowait": "$iowait",
      "avgload": "$avgload",
      "usestate": "$cpu_usestate"
    },
    "memory": {
      "total": "$mem_total",
      "used": "$mem_used",
      "free": "$mem_free",
      "available": "$mem_available",
      "usage": "$mem_usage",
      "usestate": "$mem_usestate",
      "swaptotal": "$swap_total",
      "swapused": "$swap_used",
      "swapfree": "$swap_free",
      "swapusage": "$swap_usage",
      "swapusestate": "$swap_usestate"
    },
    "disk": [$disks],
    "apps": [$apps],
    "dockers": [$dockers],
    "result": {
      "all_count": $all_count,
      "normal_count": $normal_count,
      "warn_count": $warn_count,
      "serious_count": $serious_count,
      "description": "$description"
    }
  }
EOF
}

# ========== 主函数 ==========

main() {
    local checks_config="$1"
    
    # 读取阈值配置
    read_thresholds "$checks_config"
    
    # 开始输出JSON
    echo "["
    
    # 服务器信息
    collect_server_info "$checks_config"
    
    echo "]"
}

# 收集检查项结果
collect_checks() {
    local config_file="$1"
    local -A CHECKS
    local -A PROCESSES
    local -A CONTAINERS
    local -A LOGS
    
    # 读取检查项配置
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ ! "$line" =~ ^threshold: ]]; then
            IFS=":" read -r type name rest <<< "$line"
            if [[ "$type" == "process" || "$type" == "docker" || "$type" == "log" ]]; then
                # 特殊类型处理
                if [[ "$type" == "process" ]]; then
                    PROCESSES["$name"]="$rest"
                elif [[ "$type" == "docker" ]]; then
                    CONTAINERS["$name"]="$rest"
                elif [[ "$type" == "log" ]]; then
                    LOGS["$name"]="$rest"
                fi
            else
                # 普通检查项
                CHECKS["$type"]="name=$name command=$rest"
            fi
        fi
    done < "$config_file"
    
    local check_array=()
    
    # 处理普通检查项
    for check_type in "${!CHECKS[@]}"; do
        local check_info="${CHECKS[$check_type]}"
        local check_name=$(echo "$check_info" | awk '{print $1}' | cut -d'=' -f2)
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

# 收集进程信息
collect_process_info() {
    local config_file="$1"
    local -A PROCESSES
    
    # 从 checks.conf 中读取进程配置
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^process: ]]; then
            IFS=":" read -r type proc_name service_name <<< "$line"
            PROCESSES["$proc_name"]="$service_name"
        fi
    done < "$config_file"
    
    local process_array=()
    
    for proc_name in "${!PROCESSES[@]}"; do
        local service_name="${PROCESSES[$proc_name]}"
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
    done
    
    local processes=$(IFS=, ; echo "${process_array[*]}")
    echo "$processes"
}

# 收集容器信息
collect_container_info() {
    local config_file="$1"
    local -A CONTAINERS
    
    # 从 checks.conf 中读取容器配置
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^docker: ]]; then
            IFS=":" read -r type container_name service_name <<< "$line"
            CONTAINERS["$container_name"]="$service_name"
        fi
    done < "$config_file"
    
    local docker_array=()
    
    if command -v docker &> /dev/null; then
        for container_name in "${!CONTAINERS[@]}"; do
            local service_name="${CONTAINERS[$container_name]}"
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
        done
    else
        for container_name in "${!CONTAINERS[@]}"; do
            local service_name="${CONTAINERS[$container_name]}"
            docker_array+=("{\"container_name\":\"$(json_escape "$container_name")\",\"service_name\":\"$(json_escape "$service_name")\",\"docker_unavailable\":true}")
        done
    fi
    
    local containers=$(IFS=, ; echo "${docker_array[*]}")
    echo "$containers"
}

# 收集日志信息
collect_log_info() {
    local config_file="$1"
    local -A LOGS
    
    # 从 checks.conf 中读取日志配置
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^log: ]]; then
            IFS=":" read -r type log_path log_name <<< "$line"
            LOGS["$log_path"]="$log_name"
        fi
    done < "$config_file"
    
    local log_array=()
    
    for log_path in "${!LOGS[@]}"; do
        local log_name="${LOGS[$log_path]}"
        if [[ -f "$log_path" ]]; then
            local log_size=$(du -m "$log_path" 2>/dev/null | awk '{print $1}' || echo "N/A")
            local recent_logs=$(tail -10 "$log_path" 2>/dev/null || echo "Cannot read log file")
            
            log_array+=("{\"log_path\":\"$(json_escape "$log_path")\",\"log_name\":\"$(json_escape "$log_name")\",\"size_mb\":${log_size:-0},\"recent_lines\":\"$(json_escape "$recent_logs")\"}")
        else
            log_array+=("{\"log_path\":\"$(json_escape "$log_path")\",\"log_name\":\"$(json_escape "$log_name")\",\"file_not_found\":true}")
        fi
    done
    
    local logs=$(IFS=, ; echo "${log_array[*]}")
    
    cat <<EOF
  "log_info": {
    "log_files": [${logs:-}]
  }
EOF
}

# 执行主函数
if [[ $# -eq 1 ]]; then
    main "$1"
else
    # 默认配置文件名
    SCRIPT_DIR="$(dirname "$0")"
    main "$SCRIPT_DIR/conf/checks.conf"
fi
