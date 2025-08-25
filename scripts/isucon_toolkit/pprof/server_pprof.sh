#!/bin/bash

# サーバー側で動作するpprofスクリプト
# このスクリプトはサーバー上で実行される

set -u

# 設定
PPROF_PORT="${PPROF_PORT:-8090}"
PROFILE_FILE="/tmp/isucon_profile.prof"
PID_FILE="/tmp/pprof.pid"
LOG_FILE="/tmp/pprof.log"

show_help() {
    cat << EOF
サーバー側pprofスクリプト

使用方法:
  ./server_pprof.sh start    # pprofサーバー起動
  ./server_pprof.sh stop     # pprofサーバー停止
  ./server_pprof.sh status   # 状態確認
  ./server_pprof.sh capture  # プロファイル取得のみ

動作フロー:
  1. capture: 負荷をかけてプロファイル取得
  2. start: pprofサーバー起動
  3. ローカルからポートフォワードで接続
EOF
}

# プロファイル取得
capture_profile() {
    echo "=== プロファイル取得開始 ==="
    
    # 負荷生成
    echo "アプリケーションに負荷をかけています..."
    for i in {1..50}; do 
        curl -s http://localhost:8080/api/app/users > /dev/null & 
    done
    wait
    
    # プロファイル取得
    echo "プロファイルを取得中（10秒間）..."
    curl -s 'http://localhost:6060/debug/pprof/profile?seconds=10' -o "$PROFILE_FILE"
    
    if [[ -f "$PROFILE_FILE" ]]; then
        echo "プロファイル取得完了: $PROFILE_FILE"
        ls -lh "$PROFILE_FILE"
    else
        echo "エラー: プロファイル取得失敗"
        return 1
    fi
}

# pprofサーバー起動
start_server() {
    echo "=== pprofサーバー起動 ==="
    
    # 既存のサーバーを停止
    stop_server
    
    # プロファイルファイル確認
    if [[ ! -f "$PROFILE_FILE" ]]; then
        echo "プロファイルファイルがありません。先に capture を実行してください"
        return 1
    fi
    
    # pprofサーバー起動
    echo "pprofサーバーを起動しています（ポート: $PPROF_PORT）..."
    export BROWSER=echo
    nohup go tool pprof -http=:${PPROF_PORT} "$PROFILE_FILE" > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$PID_FILE"
    
    sleep 2
    
    # 起動確認
    if ps -p $pid > /dev/null; then
        echo "pprofサーバー起動成功（PID: $pid）"
        echo "ポート $PPROF_PORT で待機中"
        echo ""
        echo "ローカルから以下のコマンドでポートフォワード:"
        echo "  ssh -L ${PPROF_PORT}:localhost:${PPROF_PORT} [このサーバー]"
        return 0
    else
        echo "pprofサーバー起動失敗"
        cat "$LOG_FILE"
        return 1
    fi
}

# pprofサーバー停止
stop_server() {
    echo "pprofサーバーを停止しています..."
    
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p $pid > /dev/null 2>&1; then
            kill $pid
            echo "pprofサーバー停止（PID: $pid）"
        fi
        rm -f "$PID_FILE"
    fi
    
    # 念のため全pprofプロセスを停止
    pkill -f "go tool pprof.*-http" 2>/dev/null || true
}

# 状態確認
check_status() {
    echo "=== pprofサーバー状態 ==="
    
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p $pid > /dev/null 2>&1; then
            echo "pprofサーバー稼働中（PID: $pid）"
            echo "ポート: $PPROF_PORT"
            ps -fp $pid
        else
            echo "pprofサーバー停止中（PIDファイルは存在）"
        fi
    else
        echo "pprofサーバー停止中"
    fi
    
    echo ""
    echo "プロファイルファイル:"
    if [[ -f "$PROFILE_FILE" ]]; then
        ls -lh "$PROFILE_FILE"
    else
        echo "  なし"
    fi
}

# メイン処理
case "${1:-}" in
    capture)
        capture_profile
        ;;
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    status)
        check_status
        ;;
    *)
        show_help
        ;;
esac