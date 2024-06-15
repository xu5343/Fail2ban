#!/bin/bash

# 默认日志文件路径
LOG_FILE="/opt/ats/var/log/node/cdnnode.log"
LOG_DIR="/tmp/log_parts"

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -log|--logfile) LOG_FILE="$2"; shift ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
    shift
done

# 确认日志文件存在
if [[ ! -f "$LOG_FILE" ]]; then
    echo "日志文件不存在: $LOG_FILE"
    exit 1
fi

# 创建临时目录
mkdir -p $LOG_DIR

# 将日志文件分成多个部分，每部分大约50MB
split -b 100M "$LOG_FILE" "$LOG_DIR/part_"
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
find "$LOG_DIR" -type f -name 'part_*' | parallel process_part {}

# 汇总所有部分的结果并输出最终访问次数最多的前10个IP地址
cat "$LOG_DIR"/part_*_ip_counts.log | sort -k2 -nr | head -n 40

# 清理临时文件
rm -r "$LOG_DIR"

echo "脚本执行完毕"
