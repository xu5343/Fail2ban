#!/bin/bash

# 日志文件位置
LOG_FILE="/opt/ats/var/log/node/cdnnode-2024-06-08T17-45-50.042.log"
TEMP_FILE="/tmp/temp_logs.log"

# 定义每批处理的行数
BATCH_SIZE=10000

# 获取日志文件的总行数
TOTAL_LINES=$(wc -l < "$LOG_FILE")

# 分批处理日志文件
start_line=1
while [ $start_line -le $TOTAL_LINES ]; do
    # 截取当前批次的日志行
    sed -n "${start_line},$(($start_line + $BATCH_SIZE - 1))p" "$LOG_FILE" > "$TEMP_FILE"

    # 使用awk处理当前批次的日志行
    awk '
    function to_epoch(timestamp) {
        cmd = "date -d \"" timestamp "\" +%s"
        cmd | getline epoch
        close(cmd)
        return epoch
    }

    {
        # 提取日志时间戳和IP地址
        log_time = ""
        ip = ""

        # 尝试提取标准格式的时间戳
        if (match($0, /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3})\+\d{4}/, time_arr)) {
            log_time = time_arr[1]
        } 
        # 尝试提取包含 "timestamp" 字段的时间戳
        else if (match($0, /timestamp:([0-9]{10,13})/, time_arr)) {
            log_epoch = substr(time_arr[1], 1, 10)
            cmd = "date -d @" log_epoch " +\"%Y-%m-%dT%H:%M:%S.%3N\""
            cmd | getline log_time
            close(cmd)
        } 
        # 尝试提取其他可能的时间戳格式
        else if (match($0, /(\d{10}\.\d{3})/, time_arr)) {
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

        # 提取IP地址
        if (match($0, /ip:\\\"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\\\"/, ip_arr)) {
            ip = ip_arr[1]
        } else if (match($0, / ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) /, ip_arr)) {
            ip = ip_arr[1]
        }

        # 输出调试信息以检查时间戳和IP提取
        print "log_time:", log_time, "log_epoch:", log_epoch, "ip:", ip > "/dev/stderr"

        # 将日志按IP地址和时间排序存储
        if (ip != "" && log_epoch > 0) {
            access_times[ip][log_epoch]++
        }
    }
    END {
        # 查找每个IP地址在任意60秒内的最大访问次数
        for (ip in access_times) {
            max_count = 0
            asorti(access_times[ip], sorted_times)
            for (i in sorted_times) {
                start_time = sorted_times[i]
                end_time = start_time + 60
                count = 0
                for (j in sorted_times) {
                    if (sorted_times[j] >= start_time && sorted_times[j] <= end_time) {
                        count += access_times[ip][sorted_times[j]]
                    }
                }
                if (count > max_count) {
                    max_count = count
                }
            }
            ip_counts[ip] = max_count
        }

        # 输出访问次数最多的前10个IP地址
        PROCINFO["sorted_in"] = "@val_num_desc"
        for (ip in ip_counts) {
            print ip, ip_counts[ip]
        }
    }' "$TEMP_FILE" >> /tmp/ip_counts.log

    # 更新起始行
    start_line=$(($start_line + $BATCH_SIZE))
done

# 统计所有批次结果并输出最终访问次数最多的前10个IP地址
sort -k2 -nr /tmp/ip_counts.log | head -n 10

# 清理临时文件
rm "$TEMP_FILE"
rm /tmp/ip_counts.log

# 输出结束标志
echo "脚本执行完毕"
