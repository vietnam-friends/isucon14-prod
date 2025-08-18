#!/bin/bash

# ISUCON14 スロークエリ分析スクリプト
# このスクリプトはアプリケーションサーバー上で実行されます

set -e

# 設定
SLOW_LOG="/var/log/mysql/mysql-slow.log"
BACKUP_DIR="/tmp/slow_query_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/slow_query_${TIMESTAMP}.log"
BENCH_SERVER="ubuntu@3.112.110.105"
BENCH_KEY="~/Downloads/isucon14.pem"

# バックアップディレクトリの作成
sudo mkdir -p ${BACKUP_DIR}

echo "======================================"
echo "スロークエリ分析 開始: $(date)"
echo "======================================"

# 1. 既存のスロークエリログをバックアップ
if [ -f "${SLOW_LOG}" ]; then
    echo "既存のスロークエリログをバックアップ中..."
    sudo cp ${SLOW_LOG} ${BACKUP_FILE}
    echo "バックアップ完了: ${BACKUP_FILE}"
fi

# 2. スロークエリログをクリア
echo "スロークエリログをクリア中..."
sudo sh -c "echo '' > ${SLOW_LOG}"
sudo chmod 644 ${SLOW_LOG}
sudo chown mysql:mysql ${SLOW_LOG}

# 3. MySQLを再起動してログファイルを有効化
echo "MySQLサービスを再起動中..."
sudo systemctl restart mysql
sleep 2

# 4. ベンチマーク実行前のタイムスタンプを記録
BENCH_START=$(date +%s)
echo "ベンチマーク開始時刻: $(date)"

# 5. ベンチマークサーバーからベンチマークを実行
echo "ベンチマークを実行中..."
echo "コマンド: ssh -i ${BENCH_KEY} ${BENCH_SERVER} 'cd ~/isucon14/bench && /usr/local/go/bin/go run . run --target https://xiv.isucon.net:443 --payment-url http://13.230.155.251:12345 -t 60 --skip-static-sanity-check'"
echo ""
echo "注意: このスクリプトはアプリケーションサーバー上で実行してください"
echo "ベンチマークは手動で実行するか、別ターミナルから実行してください"
echo ""
echo "ベンチマーク実行後、Enterキーを押してください..."
read -r

# 6. ベンチマーク終了後のタイムスタンプを記録
BENCH_END=$(date +%s)
echo "ベンチマーク終了時刻: $(date)"
BENCH_DURATION=$((BENCH_END - BENCH_START))
echo "ベンチマーク実行時間: ${BENCH_DURATION}秒"

# 7. スロークエリログを取得
echo ""
echo "======================================"
echo "スロークエリログの内容:"
echo "======================================"

if [ -s "${SLOW_LOG}" ]; then
    # ログファイルのサイズを確認
    LOG_SIZE=$(sudo stat -c%s "${SLOW_LOG}")
    LOG_LINES=$(sudo wc -l < "${SLOW_LOG}")
    
    echo "ログサイズ: ${LOG_SIZE} bytes"
    echo "ログ行数: ${LOG_LINES} lines"
    echo ""
    
    # ログ全体を出力
    sudo cat ${SLOW_LOG}
    
    # 分析用にログを保存
    ANALYSIS_FILE="${BACKUP_DIR}/analysis_${TIMESTAMP}.log"
    sudo cp ${SLOW_LOG} ${ANALYSIS_FILE}
    echo ""
    echo "分析用ファイル保存: ${ANALYSIS_FILE}"
else
    echo "スロークエリログが空です。"
    echo "スロークエリの閾値設定を確認してください。"
fi

echo ""
echo "======================================"
echo "スロークエリ分析 完了: $(date)"
echo "======================================"