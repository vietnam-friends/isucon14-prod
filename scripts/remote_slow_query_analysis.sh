#!/bin/bash

# ISUCON14 リモートスロークエリ分析スクリプト
# このスクリプトはローカルから実行し、リモートサーバー上でスロークエリ分析を行います

set -e

# 設定
APP_SERVER="ubuntu@13.230.155.251"
BENCH_SERVER="ubuntu@3.112.110.105"
SSH_KEY="~/Downloads/isucon14.pem"
SLOW_LOG="/var/log/mysql/mysql-slow.log"
BACKUP_DIR="/tmp/slow_query_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "======================================"
echo "リモートスロークエリ分析 開始: $(date)"
echo "======================================"

# 1. アプリケーションサーバーでスロークエリログをクリア
echo "スロークエリログをクリア中..."
ssh -i ${SSH_KEY} ${APP_SERVER} << 'EOF'
    # バックアップディレクトリの作成
    sudo mkdir -p /tmp/slow_query_backups
    
    # 既存のログをバックアップ
    if [ -f /var/log/mysql/mysql-slow.log ]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        sudo cp /var/log/mysql/mysql-slow.log /tmp/slow_query_backups/before_bench_${TIMESTAMP}.log
    fi
    
    # ログをクリア
    sudo sh -c "echo '' > /var/log/mysql/mysql-slow.log"
    sudo chmod 644 /var/log/mysql/mysql-slow.log
    sudo chown mysql:mysql /var/log/mysql/mysql-slow.log
    
    # MySQLを再起動
    sudo systemctl restart mysql
    
    echo "スロークエリログのクリア完了"
EOF

sleep 3

# 2. ベンチマークを実行
echo ""
echo "ベンチマークを実行中..."
BENCH_START=$(date +%s)

ssh -i ${SSH_KEY} ${BENCH_SERVER} << 'EOF'
    cd ~/isucon14/bench
    /usr/local/go/bin/go run . run \
        --target https://xiv.isucon.net:443 \
        --payment-url http://13.230.155.251:12345 \
        -t 60 --skip-static-sanity-check
EOF

BENCH_END=$(date +%s)
BENCH_DURATION=$((BENCH_END - BENCH_START))
echo ""
echo "ベンチマーク完了 (実行時間: ${BENCH_DURATION}秒)"

# 3. スロークエリログを取得・分析
echo ""
echo "======================================"
echo "スロークエリログ分析結果:"
echo "======================================"

ssh -i ${SSH_KEY} ${APP_SERVER} << 'EOF'
    SLOW_LOG="/var/log/mysql/mysql-slow.log"
    
    if [ -s "${SLOW_LOG}" ]; then
        # ログファイルの統計情報
        LOG_SIZE=$(sudo stat -c%s "${SLOW_LOG}")
        LOG_LINES=$(sudo wc -l < "${SLOW_LOG}")
        
        echo "ログサイズ: ${LOG_SIZE} bytes"
        echo "ログ行数: ${LOG_LINES} lines"
        echo ""
        
        # スロークエリの簡易分析
        echo "=== クエリ統計 ==="
        echo ""
        
        # 1. 実行時間が長いクエリTOP10
        echo "【実行時間が長いクエリ TOP10】"
        sudo grep -E "^# Query_time:" ${SLOW_LOG} | \
            sort -t: -k2 -rn | \
            head -10 | \
            awk '{print "実行時間: " $3 "秒"}'
        
        echo ""
        
        # 2. 頻出クエリパターン
        echo "【頻出クエリパターン】"
        sudo grep -E "^(SELECT|INSERT|UPDATE|DELETE)" ${SLOW_LOG} | \
            sed 's/[0-9]\+/N/g' | \
            sed "s/'[^']*'/S/g" | \
            sort | uniq -c | sort -rn | head -10
        
        echo ""
        echo "=== 詳細ログ ==="
        echo ""
        
        # 全ログを出力
        sudo cat ${SLOW_LOG}
        
        # 分析用にログを保存
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        ANALYSIS_FILE="/tmp/slow_query_backups/analysis_${TIMESTAMP}.log"
        sudo cp ${SLOW_LOG} ${ANALYSIS_FILE}
        echo ""
        echo "分析用ファイル保存: ${ANALYSIS_FILE}"
    else
        echo "スロークエリログが空です。"
        echo "以下を確認してください："
        echo "1. スロークエリの閾値設定 (long_query_time)"
        echo "2. slow_query_logが有効になっているか"
        echo "3. ベンチマーク中にクエリが実行されたか"
    fi
EOF

echo ""
echo "======================================"
echo "リモートスロークエリ分析 完了: $(date)"
echo "======================================"