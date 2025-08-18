#!/bin/bash

# ISUCON14 リソース監視スクリプト
# bottleneck-analyzerエージェントから呼び出されるリソース監視スクリプト

set -e

# 設定
MONITOR_INTERVAL=5  # 監視間隔（秒）
DURATION=${1:-60}   # 監視時間（秒、デフォルト60秒）
OUTPUT_DIR="/tmp/resource_monitor"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/resource_monitor_${TIMESTAMP}.log"
SUMMARY_FILE="${OUTPUT_DIR}/resource_summary_${TIMESTAMP}.log"

# 出力ディレクトリの作成
mkdir -p ${OUTPUT_DIR}

echo "======================================"
echo "リソース監視開始: $(date)"
echo "監視時間: ${DURATION}秒"
echo "監視間隔: ${MONITOR_INTERVAL}秒"
echo "出力ファイル: ${OUTPUT_FILE}"
echo "======================================"

# ヘッダーの作成
cat > ${OUTPUT_FILE} << EOF
# ISUCON14 Resource Monitor Log
# Start Time: $(date)
# Duration: ${DURATION} seconds
# Interval: ${MONITOR_INTERVAL} seconds

TIMESTAMP,CPU_USER,CPU_SYS,CPU_IDLE,CPU_IOWAIT,MEM_USED_PCT,MEM_AVAILABLE_MB,DISK_READ_MBPS,DISK_WRITE_MBPS,NET_RX_MBPS,NET_TX_MBPS,LOAD_AVG_1MIN
EOF

# 初期値の取得（差分計算用）
prev_disk_stats=$(awk '/^(sd|vd|nvme)/ {total_read+=$3; total_write+=$7} END {print total_read, total_write}' /proc/diskstats)
prev_net_stats=$(awk '/eth0:|ens|enp/ {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev)
prev_time=$(date +%s)

# 監視ループ
end_time=$(($(date +%s) + DURATION))
while [ $(date +%s) -lt $end_time ]; do
    current_time=$(date +%s)
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # CPU統計の取得
    cpu_stats=$(awk '/^cpu / {
        total = $2 + $3 + $4 + $5 + $6 + $7 + $8
        user_pct = $2 / total * 100
        sys_pct = $3 / total * 100
        idle_pct = $4 / total * 100
        iowait_pct = $5 / total * 100
        printf "%.2f,%.2f,%.2f,%.2f", user_pct, sys_pct, idle_pct, iowait_pct
    }' /proc/stat)
    
    # メモリ統計の取得
    mem_stats=$(awk '
        /MemTotal:/ {total = $2}
        /MemAvailable:/ {available = $2}
        END {
            used_pct = (total - available) / total * 100
            available_mb = available / 1024
            printf "%.2f,%.2f", used_pct, available_mb
        }' /proc/meminfo)
    
    # ディスクI/O統計の取得
    current_disk_stats=$(awk '/^(sd|vd|nvme)/ {total_read+=$3; total_write+=$7} END {print total_read, total_write}' /proc/diskstats)
    read_blocks=$(echo $current_disk_stats $prev_disk_stats | awk '{print $1 - $3}')
    write_blocks=$(echo $current_disk_stats $prev_disk_stats | awk '{print $2 - $4}')
    time_diff=$((current_time - prev_time))
    
    if [ $time_diff -gt 0 ]; then
        # 512バイトブロック → MB/s変換
        disk_read_mbps=$(echo "$read_blocks $time_diff" | awk '{printf "%.2f", $1 * 512 / 1024 / 1024 / $2}')
        disk_write_mbps=$(echo "$write_blocks $time_diff" | awk '{printf "%.2f", $2 * 512 / 1024 / 1024 / $2}')
    else
        disk_read_mbps="0.00"
        disk_write_mbps="0.00"
    fi
    
    # ネットワーク統計の取得
    current_net_stats=$(awk '/eth0:|ens|enp/ && !/lo:/ {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev)
    if [ -n "$current_net_stats" ]; then
        rx_bytes=$(echo $current_net_stats $prev_net_stats | awk '{print $1 - $3}')
        tx_bytes=$(echo $current_net_stats $prev_net_stats | awk '{print $2 - $4}')
        
        if [ $time_diff -gt 0 ]; then
            net_rx_mbps=$(echo "$rx_bytes $time_diff" | awk '{printf "%.2f", $1 / 1024 / 1024 / $2}')
            net_tx_mbps=$(echo "$tx_bytes $time_diff" | awk '{printf "%.2f", $1 / 1024 / 1024 / $2}')
        else
            net_rx_mbps="0.00"
            net_tx_mbps="0.00"
        fi
    else
        net_rx_mbps="0.00"
        net_tx_mbps="0.00"
    fi
    
    # ロードアベレージの取得
    load_avg=$(awk '{print $1}' /proc/loadavg)
    
    # データの記録
    echo "${timestamp},${cpu_stats},${mem_stats},${disk_read_mbps},${disk_write_mbps},${net_rx_mbps},${net_tx_mbps},${load_avg}" >> ${OUTPUT_FILE}
    
    # 次回計算用の値を更新
    prev_disk_stats=$current_disk_stats
    prev_net_stats=$current_net_stats
    prev_time=$current_time
    
    sleep ${MONITOR_INTERVAL}
done

echo ""
echo "======================================"
echo "リソース監視完了: $(date)"
echo "======================================"

# サマリーレポートの生成
cat > ${SUMMARY_FILE} << EOF
# ISUCON14 Resource Monitor Summary
# Generated: $(date)

## CPU統計
EOF

# CSVからサマリーを計算
awk -F',' 'NR>1 {
    cpu_user += $2; cpu_sys += $3; cpu_idle += $4; cpu_iowait += $5;
    if($2 > max_cpu_user) max_cpu_user = $2;
    if($5 > max_iowait) max_iowait = $5;
    count++
} END {
    printf "平均CPU使用率: %.2f%%\n", (cpu_user + cpu_sys) / count;
    printf "平均iowait: %.2f%%\n", cpu_iowait / count;
    printf "最大CPU使用率: %.2f%%\n", max_cpu_user;
    printf "最大iowait: %.2f%%\n", max_iowait;
}' ${OUTPUT_FILE} >> ${SUMMARY_FILE}

echo "" >> ${SUMMARY_FILE}
echo "## メモリ統計" >> ${SUMMARY_FILE}

awk -F',' 'NR>1 {
    mem_used += $6; 
    if($6 > max_mem_used) max_mem_used = $6;
    if($7 < min_mem_avail) min_mem_avail = $7;
    count++
} END {
    printf "平均メモリ使用率: %.2f%%\n", mem_used / count;
    printf "最大メモリ使用率: %.2f%%\n", max_mem_used;
    printf "最小利用可能メモリ: %.2f MB\n", min_mem_avail;
}' ${OUTPUT_FILE} >> ${SUMMARY_FILE}

echo "" >> ${SUMMARY_FILE}
echo "## ディスクI/O統計" >> ${SUMMARY_FILE}

awk -F',' 'NR>1 {
    disk_read += $8; disk_write += $9;
    if($8 > max_disk_read) max_disk_read = $8;
    if($9 > max_disk_write) max_disk_write = $9;
    count++
} END {
    printf "平均ディスク読み取り: %.2f MB/s\n", disk_read / count;
    printf "平均ディスク書き込み: %.2f MB/s\n", disk_write / count;
    printf "最大ディスク読み取り: %.2f MB/s\n", max_disk_read;
    printf "最大ディスク書き込み: %.2f MB/s\n", max_disk_write;
}' ${OUTPUT_FILE} >> ${SUMMARY_FILE}

echo "" >> ${SUMMARY_FILE}
echo "## ネットワーク統計" >> ${SUMMARY_FILE}

awk -F',' 'NR>1 {
    net_rx += $10; net_tx += $11;
    if($10 > max_net_rx) max_net_rx = $10;
    if($11 > max_net_tx) max_net_tx = $11;
    count++
} END {
    printf "平均ネットワーク受信: %.2f MB/s\n", net_rx / count;
    printf "平均ネットワーク送信: %.2f MB/s\n", net_tx / count;
    printf "最大ネットワーク受信: %.2f MB/s\n", max_net_rx;
    printf "最大ネットワーク送信: %.2f MB/s\n", max_net_tx;
}' ${OUTPUT_FILE} >> ${SUMMARY_FILE}

echo "" >> ${SUMMARY_FILE}
echo "## ボトルネック判定" >> ${SUMMARY_FILE}

# ボトルネック判定
awk -F',' 'NR>1 {
    avg_cpu_total += ($2 + $3); avg_iowait += $5; avg_mem += $6;
    count++
} END {
    avg_cpu = avg_cpu_total / count;
    avg_io = avg_iowait / count;
    avg_memory = avg_mem / count;
    
    print "";
    if(avg_cpu > 80) print "【警告】CPU使用率が高い: " avg_cpu "%";
    else if(avg_cpu > 50) print "【注意】CPU使用率が中程度: " avg_cpu "%";
    else print "【正常】CPU使用率: " avg_cpu "%";
    
    if(avg_io > 20) print "【警告】iowaitが高い（DB負荷の可能性）: " avg_io "%";
    else if(avg_io > 10) print "【注意】iowaitが中程度: " avg_io "%";
    else print "【正常】iowait: " avg_io "%";
    
    if(avg_memory > 90) print "【警告】メモリ使用率が高い: " avg_memory "%";
    else if(avg_memory > 70) print "【注意】メモリ使用率が中程度: " avg_memory "%";
    else print "【正常】メモリ使用率: " avg_memory "%";
}' ${OUTPUT_FILE} >> ${SUMMARY_FILE}

echo ""
echo "サマリーレポート作成完了: ${SUMMARY_FILE}"
echo ""
echo "=== サマリー内容 ==="
cat ${SUMMARY_FILE}

echo ""
echo "詳細ログ: ${OUTPUT_FILE}"