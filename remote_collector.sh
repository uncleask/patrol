#!/bin/bash

# ============================================
# 远程采集脚本
# 读取 host_${HOST_IP}_patrol.conf 配置文件
# 输出带状态信息的 JSON
# ============================================

execshname=`basename $0`
sh_name=`basename $0|cut -d . -f 1`
PATROL_HOME=${HOME}/patrol
logspath=${PATROL_HOME}/logs
details_path=${PATROL_HOME}/data

if [ ! -d ${logspath} ]; then
    mkdir -p ${logspath}
fi

if [ ! -d "${details_path}" ]; then
    mkdir -p "${details_path}"
fi

CURRENT_DATE=$(date "+%Y%m%d")
curDay=`date '+%Y-%m-%d'`
actionlog=${logspath}/${sh_name}.${curDay}.log
initdir=$PWD

export TZ="Asia/Shanghai"

HOST_IP=$(hostname -I | awk '{print $1}' | head -1)
PATROL_CONFIG_FILE="host_${HOST_IP}_patrol.conf"

# 全局变量
declare -A DISK_THRESHOLDS
APPS_LIST=""
DOCKERS_LIST=""
DISK_LIST=""
cpu_warn=70
cpu_serious=85
mem_warn=70
mem_serious=85

# 使用文件来存储统计信息
STATS_FILE="/tmp/system_patrol_stats.$$"
DESCRIPTION_FILE="/tmp/system_patrol_desc.$$"

init_stats() {
    cat > "$STATS_FILE" << EOF
all_count=0
normal_count=0
warn_count=0
serious_count=0
EOF
    echo "" > "$DESCRIPTION_FILE"
}

update_stat() {
    local key="$1"
    local value="$2"
    sed -i "s/^${key}=.*/${key}=${value}/" "$STATS_FILE"
}

get_stat() {
    local key="$1"
    grep "^${key}=" "$STATS_FILE" | cut -d= -f2
}

add_description() {
    echo "$1" >> "$DESCRIPTION_FILE"
}

get_description() {
    if [ ! -s "$DESCRIPTION_FILE" ] || [ -z "$(grep -v '^[[:space:]]*$' "$DESCRIPTION_FILE")" ]; then
        echo "【正常】"
    else
        tr '\n' '|' < "$DESCRIPTION_FILE" | sed 's/|/<br\/>/g'
    fi
}

cleanup() {
    rm -f "$STATS_FILE" "$DESCRIPTION_FILE"
}

# ============ 获取状态等级 ============
get_usage_state() {
    local usage="$1"
    local warn_threshold="$2"
    local serious_threshold="$3"
    local item_name="$4"
    
    usage=$(echo "$usage" | sed 's/%//')
    usage=${usage%.*}
    
    local all_count=$(get_stat "all_count")
    update_stat "all_count" "$((all_count + 1))"
    
    if awk "BEGIN {exit !($usage >= $serious_threshold)}" 2>/dev/null; then
        local serious_count=$(get_stat "serious_count")
        update_stat "serious_count" "$((serious_count + 1))"
        add_description "【严重】$item_name 使用率 ${usage}% ≥ ${serious_threshold}%"
        echo "serious"
    elif awk "BEGIN {exit !($usage >= $warn_threshold)}" 2>/dev/null; then
        local warn_count=$(get_stat "warn_count")
        update_stat "warn_count" "$((warn_count + 1))"
        add_description "【警告】$item_name 使用率 ${usage}% ≥ ${warn_threshold}%"
        echo "warn"
    else
        local normal_count=$(get_stat "normal_count")
        update_stat "normal_count" "$((normal_count + 1))"
        echo "normal"
    fi
}

# ============ 读取配置文件 ============
read_patrol_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        echo "配置文件不存在: $config_file" >> ${actionlog}
        return 1
    fi
    
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        # 解析行：name:type:command
        IFS=':' read -r name type command <<< "$line"
        
        case "$type" in
            threshold)
                # threshold:cpu:70,85 或 threshold:disk_root:80,90
                local warn=$(echo "$command" | cut -d',' -f1)
                local serious=$(echo "$command" | cut -d',' -f2)
                if [[ "$name" == "cpu" ]]; then
                    cpu_warn="$warn"
                    cpu_serious="$serious"
                elif [[ "$name" == "mem" ]]; then
                    mem_warn="$warn"
                    mem_serious="$serious"
                else
                    # 磁盘阈值
                    DISK_THRESHOLDS["${name}_warn"]="$warn"
                    DISK_THRESHOLDS["${name}_serious"]="$serious"
                fi
                ;;
            disk)
                # disk_root:disk:df -h /
                DISK_LIST="${DISK_LIST}${name}:${command}"$'\n'
                ;;
            vhost)
                # mysql:vhost:ps aux | grep mysql
                APPS_LIST="${APPS_LIST}${name}:${type}:${command}"$'\n'
                ;;
            docker)
                # opengauss:docker:docker ps --filter "name=opengauss"
                DOCKERS_LIST="${DOCKERS_LIST}${name}:${type}:${command}"$'\n'
                ;;
        esac
    done < "$config_file"
    
    export cpu_warn cpu_serious mem_warn mem_serious
    export APPS_LIST DOCKERS_LIST DISK_LIST
}

# ============ 获取系统基本信息 ============
get_basic_info() {
    local time=$(date "+%Y-%m-%d %H:%M:%S")
    local hostname=$(hostname)
    local os=$(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' 2>/dev/null || echo "Unknown")
    
    local uptime_seconds=$(awk '{print $1}' /proc/uptime | cut -d. -f1)
    local uptimesince=$(date -d "@$(($(date +%s) - $uptime_seconds))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
    local uptimeduration=$(uptime | sed 's/.*up //; s/, *[0-9]* users.*//' | xargs echo "up" 2>/dev/null || echo "unknown")
    
    jq -n \
        --arg time "$time" \
        --arg hostip "$HOST_IP" \
        --arg hostname "$hostname" \
        --arg os "$os" \
        --arg uptimesince "$uptimesince" \
        --arg uptimeduration "$uptimeduration" \
        '{
            "time": $time,
            "hostip": $hostip,
            "hostname": $hostname,
            "os": $os,
            "uptimesince": $uptimesince,
            "uptimeduration": $uptimeduration
        }'
}

# ============ 获取CPU信息 ============
get_cpu_info() {
    local cpu_line=$(top -bn1 | grep "Cpu(s)" | head -1 2>/dev/null || echo "Cpu(s):  0.0 us,  0.0 sy,  0.0 ni, 100.0 id,  0.0 wa")
    
    local us=$(echo "$cpu_line" | sed -n 's/.* \([0-9.]*\) us.*/\1/p')
    local sy=$(echo "$cpu_line" | sed -n 's/.* \([0-9.]*\) sy.*/\1/p')
    local id=$(echo "$cpu_line" | sed -n 's/.* \([0-9.]*\) id.*/\1/p')
    local wa=$(echo "$cpu_line" | sed -n 's/.* \([0-9.]*\) wa.*/\1/p')
    
    us=${us:-0}
    sy=${sy:-0}
    id=${id:-100}
    wa=${wa:-0}
    
    local usage=$(awk "BEGIN {printf \"%.2f\", 100 - $id}" 2>/dev/null || echo "0")
    local avgload=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ *//' 2>/dev/null || echo "0.00, 0.00, 0.00")
    
    local cpu_state=$(get_usage_state "$usage" "$cpu_warn" "$cpu_serious" "CPU")
    
    jq -n \
        --arg usage "$usage" \
        --arg sysusage "$sy" \
        --arg idle "$id" \
        --arg iowait "$wa" \
        --arg avgload "$avgload" \
        --arg usestate "$cpu_state" \
        '{
            "usage": $usage,
            "sysusage": $sysusage,
            "idle": $idle,
            "iowait": $iowait,
            "avgload": $avgload,
            "usestate": $usestate
        }'
}

# ============ 获取内存信息 ============
get_memory_info() {
    local mem_line=$(free -m 2>/dev/null | grep "^Mem:")
    if [ -z "$mem_line" ]; then
        mem_line=$(free -m 2>/dev/null | grep "Mem:")
    fi
    
    if [ -z "$mem_line" ]; then
        echo '{"total": "0", "used": "0", "free": "0", "available": "0", "usage": "0", "usestate": "serious", "swaptotal": "0", "swapused": "0", "swapfree": "0", "swapusage": "0"}'
        return
    fi
    
    local total=$(echo "$mem_line" | awk '{print $2}')
    local used=$(echo "$mem_line" | awk '{print $3}')
    local free=$(echo "$mem_line" | awk '{print $4}')
    local available=$(echo "$mem_line" | awk '{print $7}')
    
    if [ -z "$available" ]; then
        available=$(echo "$mem_line" | awk '{print $6}')
    fi
    
    total=${total:-0}
    used=${used:-0}
    free=${free:-0}
    available=${available:-0}
    
    local usage=$(awk "BEGIN {printf \"%.2f\", $used * 100 / $total}" 2>/dev/null || echo "0")
    local mem_state=$(get_usage_state "$usage" "$mem_warn" "$mem_serious" "内存")
    
    local swap_line=$(free -m 2>/dev/null | grep "^Swap:")
    if [ -z "$swap_line" ]; then
        swap_line=$(free -m 2>/dev/null | grep "Swap:")
    fi
    
    local swaptotal="0"
    local swapused="0"
    local swapfree="0"
    local swapusage="0"
    
    if [ -n "$swap_line" ]; then
        swaptotal=$(echo "$swap_line" | awk '{print $2}')
        swapused=$(echo "$swap_line" | awk '{print $3}')
        swapfree=$(echo "$swap_line" | awk '{print $4}')
        swapusage=$(awk "BEGIN {printf \"%.2f\", $swapused * 100 / $swaptotal}" 2>/dev/null || echo "0")
    fi
    
    # 生成使用率文本格式：使用率（使用量/总量）
    local usage_text="${usage}% ($used MB/$total MB)"
    local swapusage_text="${swapusage}% ($swapused MB/$swaptotal MB)"
    
    jq -n \
        --arg total "$total" \
        --arg used "$used" \
        --arg free "$free" \
        --arg available "$available" \
        --arg usage "$usage" \
        --arg usage_text "$usage_text" \
        --arg usestate "$mem_state" \
        --arg swaptotal "$swaptotal" \
        --arg swapused "$swapused" \
        --arg swapfree "$swapfree" \
        --arg swapusage "$swapusage" \
        --arg swapusage_text "$swapusage_text" \
        '{
            "total": $total,
            "used": $used,
            "free": $free,
            "available": $available,
            "usage": $usage,
            "usage_text": $usage_text,
            "usestate": $usestate,
            "swaptotal": $swaptotal,
            "swapused": $swapused,
            "swapfree": $swapfree,
            "swapusage": $swapusage,
            "swapusage_text": $swapusage_text
        }'
}

# ============ 获取磁盘信息 ============
get_disk_info() {
    if [ -z "$DISK_LIST" ]; then
        echo "[]"
        return
    fi
    
    local disk_json=""
    
    while IFS=':' read -r name command; do
        [ -z "$name" ] && continue
        
        local disk_line=$(eval "$command" 2>/dev/null | awk 'NR==2')
        
        local item
        if [ -z "$disk_line" ]; then
            local all_count=$(get_stat "all_count")
            update_stat "all_count" "$((all_count + 1))"
            local serious_count=$(get_stat "serious_count")
            update_stat "serious_count" "$((serious_count + 1))"
            add_description "【严重】磁盘 $name 无法获取信息"
            
            item=$(jq -n \
                --arg name "$name" \
                --arg state "error" \
                '{name: $name, state: $state}')
        else
            local filesystem=$(echo "$disk_line" | awk '{print $1}')
            local total=$(echo "$disk_line" | awk '{print $2}')
            local used=$(echo "$disk_line" | awk '{print $3}')
            local available=$(echo "$disk_line" | awk '{print $4}')
            local usage=$(echo "$disk_line" | awk '{print $5}' | sed 's/%//')
            local mounted=$(echo "$disk_line" | awk '{print $6}')
            
            local warn="${DISK_THRESHOLDS[${name}_warn]:-78}"
            local serious="${DISK_THRESHOLDS[${name}_serious]:-90}"
            
            local disk_state=$(get_usage_state "$usage" "$warn" "$serious" "磁盘 $mounted")
            
            item=$(jq -n \
                --arg name "$name" \
                --arg mounted "$mounted" \
                --arg filesystem "$filesystem" \
                --arg total "$total" \
                --arg used "$used" \
                --arg available "$available" \
                --arg usage "$usage" \
                --arg usestate "$disk_state" \
                '{
                    "name": $name,
                    "mounted": $mounted,
                    "filesystem": $filesystem,
                    "total": $total,
                    "used": $used,
                    "available": $available,
                    "usage": $usage,
                    "usestate": $usestate
                }')
        fi
        
        if [ -n "$disk_json" ]; then
            disk_json="$disk_json, $item"
        else
            disk_json="$item"
        fi
    done <<< "$(echo -e "$DISK_LIST")"
    
    echo "[$disk_json]"
}

# ============ 获取应用信息 ============
get_apps_info() {
    if [ -z "$APPS_LIST" ]; then
        echo "[]"
        return
    fi
    
    local json_array=""
    
    while IFS=':' read -r app_name app_type app_cmd; do
        [ -z "$app_name" ] && continue
        
        local process_info=$(eval "$app_cmd" 2>/dev/null | head -1)
        
        local item
        if [ -z "$process_info" ]; then
            local all_count=$(get_stat "all_count")
            update_stat "all_count" "$((all_count + 1))"
            local serious_count=$(get_stat "serious_count")
            update_stat "serious_count" "$((serious_count + 1))"
            add_description "【严重】应用 $app_name 未运行"
            
            item=$(jq -n \
                --arg name "$app_name" \
                --arg type "$app_type" \
                '{
                    "name": $name,
                    "type": $type,
                    "state": "stopped"
                }')
        else
            local normal_count=$(get_stat "normal_count")
            update_stat "normal_count" "$((normal_count + 1))"
            
            local user=$(echo "$process_info" | awk '{print $1}')
            local pid=$(echo "$process_info" | awk '{print $2}')
            local cpu_usage=$(echo "$process_info" | awk '{print $3}' | sed 's/%//')
            local mem_usage=$(echo "$process_info" | awk '{print $4}' | sed 's/%//')
            
            local runtime_sec=$(ps -o etimes= -p "$pid" 2>/dev/null | xargs)
            if [ -z "$runtime_sec" ]; then
                runtime_sec="0"
            fi
            
            local runtime_formatted=""
            if [ "$runtime_sec" -gt 0 ]; then
                local days=$((runtime_sec / 86400))
                local hours=$(((runtime_sec % 86400) / 3600))
                local mins=$(((runtime_sec % 3600) / 60))
                
                if [ $days -gt 0 ]; then
                    runtime_formatted="${days}天${hours}小时"
                elif [ $hours -gt 0 ]; then
                    runtime_formatted="${hours}小时${mins}分"
                elif [ $mins -gt 0 ]; then
                    runtime_formatted="${mins}分"
                else
                    runtime_formatted="刚刚"
                fi
            else
                runtime_formatted="0秒"
            fi
            
            item=$(jq -n \
                --arg name "$app_name" \
                --arg type "$app_type" \
                --arg user "$user" \
                --arg pid "$pid" \
                --arg cpuusage "$cpu_usage" \
                --arg memusage "$mem_usage" \
                --arg runtime "$runtime_formatted" \
                --arg runtime_sec "$runtime_sec" \
                '{
                    "name": $name,
                    "type": $type,
                    "user": $user,
                    "pid": $pid,
                    "cpuusage": $cpuusage,
                    "memusage": $memusage,
                    "runtime": $runtime,
                    "runtime_sec": $runtime_sec,
                    "state": "running"
                }')
        fi
        
        if [ -n "$json_array" ]; then
            json_array="$json_array, $item"
        else
            json_array="$item"
        fi
    done <<< "$(echo -e "$APPS_LIST")"
    
    echo "[$json_array]"
}

# ============ 获取Docker容器信息 ============
get_dockers_info() {
    if ! command -v docker &> /dev/null; then
        echo "[]"
        return
    fi
    
    if [ -z "$DOCKERS_LIST" ]; then
        echo "[]"
        return
    fi
    
    local json_array=""
    
    while IFS=':' read -r container_name container_type container_cmd; do
        [ -z "$container_name" ] && continue
        
        if [[ "$container_cmd" != *"--format"* ]]; then
            container_cmd="$container_cmd --format \"{{.ID}}|{{.Names}}|{{.Status}}|{{.Image}}\""
        fi
        
        local container_info=$(eval "$container_cmd" 2>/dev/null | head -1)
        
        local item
        if [ -z "$container_info" ]; then
            local all_count=$(get_stat "all_count")
            update_stat "all_count" "$((all_count + 1))"
            local serious_count=$(get_stat "serious_count")
            update_stat "serious_count" "$((serious_count + 1))"
            add_description "【严重】Docker容器 $container_name 未找到"
            
            item=$(jq -n \
                --arg name "$container_name" \
                '{
                    "name": $name,
                    "state": "not_found"
                }')
        else
            local normal_count=$(get_stat "normal_count")
            update_stat "normal_count" "$((normal_count + 1))"
            
            local id=$(echo "$container_info" | cut -d'|' -f1)
            local name=$(echo "$container_info" | cut -d'|' -f2)
            local status=$(echo "$container_info" | cut -d'|' -f3)
            local image=$(echo "$container_info" | cut -d'|' -f4)
            
            if [[ "$status" == *"Up"* ]]; then
                state="running"
            else
                state="exited"
            fi
            
            item=$(jq -n \
                --arg name "$container_name" \
                --arg id "$id" \
                --arg state "$state" \
                --arg status "$status" \
                --arg image "$image" \
                '{
                    "name": $name,
                    "id": $id,
                    "state": $state,
                    "status": $status,
                    "image": $image
                }')
        fi
        
        if [ -n "$json_array" ]; then
            json_array="$json_array, $item"
        else
            json_array="$item"
        fi
    done <<< "$(echo -e "$DOCKERS_LIST")"
    
    echo "[$json_array]"
}

# ============ 获取巡检结果统计 ============
get_patrol_result() {
    local all_count=$(get_stat "all_count")
    local normal_count=$(get_stat "normal_count")
    local warn_count=$(get_stat "warn_count")
    local serious_count=$(get_stat "serious_count")
    local description=$(get_description)
    
    jq -n \
        --argjson all_count "$all_count" \
        --argjson normal_count "$normal_count" \
        --argjson warn_count "$warn_count" \
        --argjson serious_count "$serious_count" \
        --arg description "$description" \
        '{
            "all_count": $all_count,
            "normal_count": $normal_count,
            "warn_count": $warn_count,
            "serious_count": $serious_count,
            "description": $description
        }'
}

# ============ 主函数 ============
main() {
    init_stats
    
    echo "读取配置文件: $PATROL_CONFIG_FILE" >> ${actionlog}
    read_patrol_config "$PATROL_CONFIG_FILE"
    
    echo "获取系统基本信息..."
    local basic_info=$(get_basic_info)
    echo "获取CPU信息..."
    local cpu_info=$(get_cpu_info)
    echo "获取内存信息..."
    local memory_info=$(get_memory_info)
    echo "获取磁盘信息..."
    local disk_info=$(get_disk_info)
    echo "获取应用信息..."
    local apps_info=$(get_apps_info)
    echo "获取Docker信息..."
    local dockers_info=$(get_dockers_info)
    
    echo "生成巡检结果..."
    local result_info=$(get_patrol_result)
    
    jq -n \
        --argjson basic "$basic_info" \
        --argjson cpu "$cpu_info" \
        --argjson memory "$memory_info" \
        --argjson disk "$disk_info" \
        --argjson apps "$apps_info" \
        --argjson dockers "$dockers_info" \
        --argjson result "$result_info" \
        '$basic + {
            "cpu": $cpu,
            "memory": $memory,
            "disk": $disk,
            "apps": $apps,
            "dockers": $dockers,
            "result": $result
        }' > "${details_path}/data_${HOST_IP}_${CURRENT_DATE}.json"

    cleanup
    
    echo "巡检数据已保存到: ${details_path}/data_${HOST_IP}_${CURRENT_DATE}.json"
    cat "${details_path}/data_${HOST_IP}_${CURRENT_DATE}.json"
}

trap cleanup EXIT

curTime=`date '+%Y-%m-%d %T'`
echo "======start run: ${curTime}..." >> ${actionlog}
cd ${PATROL_HOME}

main

curTime=`date '+%Y-%m-%d %T'`
echo "finish get remote datas." >> ${actionlog}
echo "#####end run at: ${curTime}." >> ${actionlog}
echo "" >> ${actionlog}
cd $initdir
echo "[end] finish run."

find ${logspath} -type f -ctime +180 -name "*.log" 2>/dev/null | xargs rm -f 2>/dev/null