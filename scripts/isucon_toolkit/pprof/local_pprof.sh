#!/bin/bash

# ローカル側で動作するpprofポートフォワーディングスクリプト

set -u

# 共通設定の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/config.env"

# 設定
LOCAL_PORT="${LOCAL_PORT:-8090}"
REMOTE_PORT="${REMOTE_PORT:-8090}"

show_help() {
    cat << EOF
ローカル側pprofポートフォワーディングスクリプト

使用方法:
  ./local_pprof.sh           # ポートフォワード開始＆ブラウザ起動
  ./local_pprof.sh --kill    # ポートフォワード停止

動作:
  1. SSHポートフォワーディング確立
  2. ブラウザ自動起動
  3. http://localhost:${LOCAL_PORT} でpprof表示
EOF
}

# 既存のポートフォワーディングを停止
kill_forwarding() {
    echo "既存のポートフォワーディングを停止しています..."
    pkill -f "ssh.*-L.*${LOCAL_PORT}:localhost:${REMOTE_PORT}" 2>/dev/null || true
    sleep 1
    echo "停止完了"
}

# ポートフォワーディング開始
start_forwarding() {
    echo "=== ポートフォワーディング開始 ==="
    echo "接続先: $SERVER_HOST"
    echo "ローカルポート: $LOCAL_PORT"
    echo "リモートポート: $REMOTE_PORT"
    echo ""
    
    # SSH鍵確認
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "エラー: SSH鍵が見つかりません: $SSH_KEY"
        exit 1
    fi
    
    # 既存の接続を停止
    kill_forwarding
    
    # サーバー側の状態確認
    echo "サーバー側のpprofサーバー状態を確認中..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "
        if pgrep -f 'go tool pprof.*-http' > /dev/null; then
            echo 'pprofサーバー: 稼働中'
        else
            echo 'pprofサーバー: 停止中'
            echo '先にサーバー側で以下を実行してください:'
            echo '  cd /home/ubuntu/isucon_toolkit'
            echo '  ./server_pprof.sh capture  # プロファイル取得'
            echo '  ./server_pprof.sh start    # サーバー起動'
            exit 1
        fi
    "
    
    if [[ $? -ne 0 ]]; then
        echo "サーバー側でpprofサーバーが起動していません"
        exit 1
    fi
    
    # ポートフォワーディング開始
    echo "ポートフォワーディングを開始しています..."
    ssh -i "$SSH_KEY" -L "${LOCAL_PORT}:localhost:${REMOTE_PORT}" "$SERVER_HOST" -N &
    local ssh_pid=$!
    
    # 接続確認
    sleep 2
    if ! kill -0 "$ssh_pid" 2>/dev/null; then
        echo "エラー: ポートフォワーディング開始失敗"
        exit 1
    fi
    
    echo "ポートフォワーディング確立（PID: $ssh_pid）"
    
    # ブラウザ自動起動
    echo "ブラウザを開いています..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "http://localhost:${LOCAL_PORT}" 2>/dev/null || echo "ブラウザ自動起動失敗"
    else
        echo "ブラウザで http://localhost:${LOCAL_PORT} を開いてください"
    fi
    
    echo ""
    echo "=== 接続完了 ==="
    echo "ブラウザで http://localhost:${LOCAL_PORT} にアクセスしてください"
    echo ""
    echo "停止するには:"
    echo "  Ctrl+C または ./local_pprof.sh --kill"
    echo ""
    
    # Ctrl+C時の処理
    trap 'kill_forwarding; exit 0' INT TERM
    
    # フォアグラウンドで待機
    echo "接続維持中... (Ctrl+Cで停止)"
    wait $ssh_pid
}

# メイン処理
case "${1:-}" in
    --kill|-k)
        kill_forwarding
        ;;
    --help|-h)
        show_help
        ;;
    *)
        start_forwarding
        ;;
esac