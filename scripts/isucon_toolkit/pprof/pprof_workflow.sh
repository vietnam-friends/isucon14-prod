#!/bin/bash

# pprof分析の完全ワークフロー管理スクリプト

set -u

# 共通設定の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/config.env"

# 設定
LOCAL_PORT="8090"

show_help() {
    cat << EOF
ISUCON pprof分析ワークフロー

使用方法:
  ./pprof_workflow.sh setup     # 初期セットアップ（サーバーにスクリプト配置）
  ./pprof_workflow.sh analyze   # 分析実行（ベンチ→プロファイル→表示）
  ./pprof_workflow.sh quick     # クイック分析（プロファイル→表示）
  ./pprof_workflow.sh status    # 状態確認
  ./pprof_workflow.sh stop      # 全停止

ワークフロー:
  1. setup: サーバーにスクリプトを配置
  2. analyze: ベンチマーク実行 → プロファイル取得 → pprof起動 → ブラウザ表示
  3. quick: プロファイル取得 → pprof起動 → ブラウザ表示（ベンチなし）
EOF
}

# 初期セットアップ
setup() {
    echo "=== pprofワークフロー初期セットアップ ==="
    
    # SSH鍵確認
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "エラー: SSH鍵が見つかりません: $SSH_KEY"
        exit 1
    fi
    
    # サーバーにディレクトリ作成
    echo "サーバーにツールキットディレクトリを作成..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "mkdir -p $TOOLKIT_REMOTE_DIR"
    
    # server_pprof.shをサーバーに転送
    echo "server_pprof.shをサーバーに転送..."
    scp -i "$SSH_KEY_PATH" "$(dirname "$0")/server_pprof.sh" "$APP_SERVER:$TOOLKIT_REMOTE_DIR/"
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "chmod +x $TOOLKIT_REMOTE_DIR/server_pprof.sh"
    
    echo "セットアップ完了"
    echo ""
    echo "次のステップ:"
    echo "  ./pprof_workflow.sh analyze  # 分析開始"
}

# フル分析（ベンチマーク付き）
analyze() {
    echo "=== ISUCON pprof完全分析開始 ==="
    echo "ステップ1: ベンチマーク実行"
    echo "ステップ2: プロファイル取得"
    echo "ステップ3: pprofサーバー起動"
    echo "ステップ4: ブラウザ表示"
    echo ""
    
    # Step 1: ベンチマーク実行（バックグラウンド）
    echo "[1/4] ベンチマーク実行中..."
    ssh -i "$SSH_KEY_PATH" "$BENCH_SERVER" "cd ~/isucon14/bench && timeout 40 /usr/local/go/bin/go run . run --target https://xiv.isucon.net:443 --payment-url http://$BENCH_SERVER_IP:12345 -t 30 --skip-static-sanity-check" &
    local bench_pid=$!
    
    # Step 2: プロファイル取得（ベンチと並行）
    sleep 5  # ベンチが開始するまで待機
    echo "[2/4] プロファイル取得中..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "cd $TOOLKIT_REMOTE_DIR && ./server_pprof.sh capture"
    
    # ベンチマーク完了待ち
    wait $bench_pid 2>/dev/null || true
    echo "ベンチマーク完了"
    
    # Step 3: pprofサーバー起動
    echo "[3/4] pprofサーバー起動中..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "cd $TOOLKIT_REMOTE_DIR && ./server_pprof.sh start"
    
    # Step 4: ローカルでポートフォワード＆ブラウザ起動
    echo "[4/4] ポートフォワード＆ブラウザ起動..."
    ./local_pprof.sh
}

# クイック分析（ベンチマークなし）
quick() {
    echo "=== pprofクイック分析 ==="
    
    # Step 1: プロファイル取得
    echo "[1/3] プロファイル取得中..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "cd $TOOLKIT_REMOTE_DIR && ./server_pprof.sh capture"
    
    # Step 2: pprofサーバー起動
    echo "[2/3] pprofサーバー起動中..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "cd $TOOLKIT_REMOTE_DIR && ./server_pprof.sh start"
    
    # Step 3: ローカルでポートフォワード＆ブラウザ起動
    echo "[3/3] ポートフォワード＆ブラウザ起動..."
    ./local_pprof.sh
}

# 状態確認
status() {
    echo "=== pprof状態確認 ==="
    
    # サーバー側の状態
    echo "サーバー側:"
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "cd $TOOLKIT_REMOTE_DIR && ./server_pprof.sh status" 2>/dev/null || echo "  server_pprof.sh が見つかりません（setupを実行してください）"
    
    echo ""
    echo "ローカル側:"
    # ローカルのポートフォワーディング確認
    if pgrep -f "ssh.*-L.*${LOCAL_PORT}:localhost" > /dev/null; then
        echo "  ポートフォワーディング: 稼働中"
        echo "  URL: http://localhost:${LOCAL_PORT}"
    else
        echo "  ポートフォワーディング: 停止中"
    fi
}

# 全停止
stop() {
    echo "=== pprof全停止 ==="
    
    # ローカルのポートフォワーディング停止
    echo "ローカルのポートフォワーディングを停止..."
    ./local_pprof.sh --kill 2>/dev/null || true
    
    # サーバー側のpprofサーバー停止
    echo "サーバー側のpprofサーバーを停止..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "cd $TOOLKIT_REMOTE_DIR && ./server_pprof.sh stop" 2>/dev/null || true
    
    echo "停止完了"
}

# メイン処理
case "${1:-}" in
    setup)
        setup
        ;;
    analyze)
        analyze
        ;;
    quick)
        quick
        ;;
    status)
        status
        ;;
    stop)
        stop
        ;;
    *)
        show_help
        ;;
esac