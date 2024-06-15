#!/bin/bash

# 默认日志文件路径
LOG_DIR="/opt/ats/var/log/node"
CURRENT_LOG_FILE="${LOG_DIR}/cdnnode.log"
LOG_FILE=""
ARCHIVED_LOG_PATTERN="cdnnode-*.log"
LOG_PART_DIR="/tmp/log_parts"
BAN_THRESHOLD=800
LOGFILE="/var/log/fail2ban_custom.log"

# 获取最新的已生成日志文件
LATEST_ARCHIVED_LOG_FILE=$(ls -t ${LOG_DIR}/${ARCHIVED_LOG_PATTERN} 2>/dev/null | head -n 1)

# 确定要处理的日志文件顺序：先处理当前日志文件，再处理最新的已生成日志文件
LOG_FILES_TO_PROCESS=("$CURRENT_LOG_FILE")
if [[ -f "$LATEST_ARCHIVED_LOG_FILE" ]]; then
    LOG_FILES_TO_PROCESS+=("$LATEST_ARCHIVED_LOG_FILE")
fi

# 处理日志文件
for LOG_FILE in "${LOG_FILES_TO_PROCESS[@]}"; do
    echo "Processing log file: $LOG_FILE"

    # 确认日志文件存在
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "日志文件不存在: $LOG_FILE"
        exit 1
    fi

    # 清理临时文件
    rm -r "$LOG_PART_DIR"
    # 创建临时目录
    mkdir -p $LOG_PART_DIR

    # 将日志文件分成多个部分，每部分大约50MB
    split -b 50M "$LOG_FILE" "$LOG_PART_DIR/part_"
    if [[ $? -ne 0 ]]; then
        echo "拆分日志文件失败: $LOG_FILE"
        exit 1
    fi

    process_part() {
        local part_file=$1

        awk '
        function to_epoch(timestamp) {
            cmd = "date -d \"" timestamp "\" +%s"
            cmd | getline epoch
            close(cmd)
            return epoch
        }

        {
            log_time = ""
            ip = ""

            if (match($0, /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3})\+\d{4}/, time_arr)) {
                log_time = time_arr[1]
            } else if (match($0, /timestamp:([0-9]{10,13})/, time_arr)) {
                log_epoch = substr(time_arr[1], 1, 10)
                cmd = "date -d @" log_epoch " +\"%Y-%m-%dT%H:%M:%S.%3N\""
                cmd | getline log_time
                close(cmd)
            } else if (match($0, /(\d{10}\.\d{3})/, time_arr)) {
                log_epoch = substr(time_arr[1], 1, 10)
                cmd = "date -d @" log_epoch " +\"%Y-%m-%dT%H:%M:%S.%3N\""
                cmd | getline log_time
                close(cmd)
            }

            if (log_time != "") {
                log_epoch = to_epoch(log_time)
            } else {
                log_epoch = 0
            }

            if (match($0, /ip:\\\"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\\\"/, ip_arr)) {
                ip = ip_arr[1]
            } else if (match($0, / ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) /, ip_arr)) {
                ip = ip_arr[1]
            }

            if (ip != "" && log_epoch > 0) {
                access_times[ip][log_epoch]++
            }
        }
        END {
            for (ip in access_times) {
                max_count = 0
                n = asorti(access_times[ip], sorted_times)
                for (i = 1; i <= n; i++) {
                    start_time = sorted_times[i]
                    end_time = start_time + 60
                    count = 0
                    for (j = i; j <= n && sorted_times[j] <= end_time; j++) {
                        count += access_times[ip][sorted_times[j]]
                    }
                    if (count > max_count) {
                        max_count = count
                    }
                }
                ip_counts[ip] = max_count
            }

            PROCINFO["sorted_in"] = "@val_num_desc"
            for (ip in ip_counts) {
                print ip, ip_counts[ip]
            }
        }' "$part_file" >> "${part_file}_ip_counts.log"

        echo "Processed $part_file"
    }

    export -f process_part

    # 使用GNU Parallel并行处理所有部分
    find "$LOG_PART_DIR" -type f -name 'part_*' | parallel process_part {}

    # 汇总所有部分的结果并输出最终访问次数最多的前40个IP地址，并拉黑超过阈值的IP
    cat "$LOG_PART_DIR"/part_*_ip_counts.log | sort -k2 -nr | head -n 40 | while read -r line; do
        IP=$(echo $line | awk '{print $1}')
        COUNT=$(echo $line | awk '{print $2}')
        echo "$IP $COUNT"
        if (( COUNT > BAN_THRESHOLD )); then
            fail2ban-client set http-get-dos banip ${IP}
            firewall-cmd --zone=public --list-rich-rules | grep ${IP}        
            if [[ $? -eq 0 ]]; then
                echo "IP $IP has been banned"
            else
                echo "Failed to ban IP $IP"
            fi
        fi
    done

    # 检查Fail2ban状态以确认IP是否被封禁
    fail2ban-client status http-get-dos

    # 清理临时文件
    rm -r "$LOG_PART_DIR"
done

echo "脚本执行完毕"
