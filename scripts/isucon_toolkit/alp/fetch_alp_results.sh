#!/bin/bash

# alpの結果をローカルに取得して整理表示するスクリプト

set -u

# 共通設定の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/config.env"

# 設定
LOCAL_RESULT_DIR="./alp_results"

show_help() {
    cat << EOF
alp分析結果取得・表示スクリプト

使用方法:
  ./fetch_alp_results.sh          # 最新の結果を取得して表示
  ./fetch_alp_results.sh analyze  # サーバーで分析実行後、取得
  ./fetch_alp_results.sh clean    # ローカル結果を削除

動作:
  1. サーバーから最新のalp分析結果を取得
  2. エンドポイントごとに整理して表示
  3. ローカルファイルに保存
EOF
}

# サーバーで分析実行
run_analysis() {
    echo "=== サーバーでalp分析を実行 ==="
    
    # ベンチマーク実行を促す
    echo "ベンチマークを実行してください（別ターミナル）"
    echo "実行コマンド:"
    echo "  ssh -i $SSH_KEY_PATH $BENCH_SERVER \"cd ~/isucon14/bench && /usr/local/go/bin/go run . run --target https://xiv.isucon.net:443 --payment-url http://$BENCH_SERVER_IP:12345 -t 60 --skip-static-sanity-check\""
    echo ""
    read -p "ベンチマーク完了後、Enterキーを押してください..."
    
    # サーバーでalp分析実行
    echo "サーバーでalp分析を実行中..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "cd $TOOLKIT_REMOTE_DIR && ./alp_analysis.sh analyze"
}

# 結果取得と整理
fetch_and_display() {
    echo "=== alp分析結果を取得 ==="
    
    # ローカルディレクトリ作成
    mkdir -p "$LOCAL_RESULT_DIR"
    
    # 最新の分析結果ファイル名を取得
    local latest_file=$(ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "ls -t $TOOLKIT_REMOTE_DIR/alp_analysis/alp_analysis_*.txt 2>/dev/null | head -1")
    
    if [[ -z "$latest_file" ]]; then
        echo "エラー: 分析結果が見つかりません"
        echo "先に './fetch_alp_results.sh analyze' を実行してください"
        return 1
    fi
    
    # ファイル名だけ取得
    local filename=$(basename "$latest_file")
    local local_file="$LOCAL_RESULT_DIR/$filename"
    
    # 結果をローカルにコピー
    echo "結果を取得中: $filename"
    scp -i "$SSH_KEY_PATH" "$APP_SERVER:$latest_file" "$local_file"
    
    # 直接alpコマンドで整理された結果を取得
    echo ""
    echo "=== エンドポイントごとの詳細分析 ==="
    echo ""
    
    # JSONログから直接alpで解析（エンドポイントごとに集計）
    echo "サーバーで詳細分析を実行中..."
    
    # パターンマッチングの説明：
    # - [0-9A-Z]+ : ID部分（数字と大文字のアルファベット）
    # - [^/]+ : スラッシュ以外の任意の文字（より汎用的）
    
    local patterns=""
    patterns+="/api/initialize,"
    patterns+="/api/app/users,"
    patterns+="/api/app/payment-methods,"
    patterns+="/api/app/rides,"
    patterns+="/api/app/rides/[^/]+\$,"  # /api/app/rides/{ride_id}
    patterns+="/api/app/rides/[^/]+/evaluation,"  # /api/app/rides/{ride_id}/evaluation
    patterns+="/api/app/rides/estimated-fare,"
    patterns+="/api/app/notification,"
    patterns+="/api/app/nearby-chairs,"
    patterns+="/api/driver/register,"
    patterns+="/api/driver/chairs/[^/]+/rides,"  # /api/driver/chairs/{chair_id}/rides
    patterns+="/api/driver/chairs/[^/]+/activity,"  # /api/driver/chairs/{chair_id}/activity
    patterns+="/api/chair/chairs,"
    patterns+="/api/chair/activity,"
    patterns+="/api/chair/coordinate,"
    patterns+="/api/chair/notification,"
    patterns+="/api/chair/rides/[^/]+/status,"  # /api/chair/rides/{ride_id}/status
    patterns+="/api/owner/owners,"
    patterns+="/api/owner/chairs,"
    patterns+="/api/owner/sales,"
    patterns+="/api/internal/matching"
    
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "
        echo '=== レスポンス時間順（エンドポイントごと集計） ==='
        echo '※ 動的IDは正規表現でグループ化済み'
        echo ''
        alp json --file /var/log/nginx/access.log --sort sum -r -m '${patterns}' --limit 30
        
        echo ''
        echo '=== リクエスト数順（エンドポイントごと集計） ==='
        alp json --file /var/log/nginx/access.log --sort count -r -m '${patterns}' --limit 30
        
        echo ''
        echo '=== 平均レスポンス時間順（エンドポイントごと集計） ==='
        alp json --file /var/log/nginx/access.log --sort avg -r -m '${patterns}' --limit 30
        
        echo ''
        echo '=== P99レスポンス時間順（エンドポイントごと集計） ==='
        alp json --file /var/log/nginx/access.log --sort max -r -m '${patterns}' --percentiles '50,90,95,99' --limit 30
        
        echo ''
        echo '=== 最大レスポンス時間順（エンドポイントごと集計） ==='
        alp json --file /var/log/nginx/access.log --sort max -r -m '${patterns}' --limit 30
    " | tee "$LOCAL_RESULT_DIR/alp_detailed_$(date +%Y%m%d_%H%M%S).txt"
    
    echo ""
    echo "=== 結果をローカルに保存しました ==="
    echo "保存先: $LOCAL_RESULT_DIR/"
    ls -la "$LOCAL_RESULT_DIR/"
}

# ローカル結果削除
clean_results() {
    echo "ローカルの結果を削除します..."
    rm -rf "$LOCAL_RESULT_DIR"
    echo "削除完了"
}

# メイン処理
case "${1:-}" in
    analyze)
        run_analysis
        fetch_and_display
        ;;
    clean)
        clean_results
        ;;
    --help|-h)
        show_help
        ;;
    *)
        fetch_and_display
        ;;
esac