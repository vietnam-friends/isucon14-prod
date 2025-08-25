#!/bin/bash

# スロークエリ結果をローカルに取得して整理表示するスクリプト

set -u

# 共通設定の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/config.env"

# 設定
LOCAL_RESULT_DIR="./slowquery_results"

show_help() {
    cat << EOF
スロークエリ分析結果取得・表示スクリプト

使用方法:
  ./fetch_slowquery_results.sh          # 最新の結果を取得して表示
  ./fetch_slowquery_results.sh analyze  # サーバーで分析実行後、取得
  ./fetch_slowquery_results.sh clean    # ローカル結果を削除

動作:
  1. サーバーから最新のスロークエリ分析結果を取得
  2. 実行時間・回数・平均時間順に整理して表示
  3. ローカルファイルに保存
EOF
}

# サーバーで分析実行
run_analysis() {
    echo "=== サーバーでスロークエリ分析を実行 ==="
    
    # ベンチマーク実行を促す
    echo "ベンチマークを実行してください（別ターミナル）"
    echo "実行コマンド:"
    echo "  ssh -i $SSH_KEY_PATH $BENCH_SERVER \"cd ~/isucon14/bench && /usr/local/go/bin/go run . run --target https://xiv.isucon.net:443 --payment-url http://$BENCH_SERVER_IP:12345 -t 60 --skip-static-sanity-check\""
    echo ""
    read -p "ベンチマーク完了後、Enterキーを押してください..."
    
    # サーバーでスロークエリ分析実行
    echo "サーバーでスロークエリ分析を実行中..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "cd $TOOLKIT_REMOTE_DIR && ./slowquery_analysis.sh analyze"
}

# 結果取得と整理
fetch_and_display() {
    echo "=== スロークエリ分析結果を取得 ==="
    
    # ローカルディレクトリ作成
    mkdir -p "$LOCAL_RESULT_DIR"
    
    # 最新の分析結果ファイル名を取得
    local latest_file=$(ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "ls -t $TOOLKIT_REMOTE_DIR/slowquery_analysis/slowquery_analysis_*.txt 2>/dev/null | head -1")
    
    if [[ -z "$latest_file" ]]; then
        echo "エラー: 分析結果が見つかりません"
        echo "先に './fetch_slowquery_results.sh analyze' を実行してください"
        return 1
    fi
    
    # ファイル名だけ取得
    local filename=$(basename "$latest_file")
    local local_file="$LOCAL_RESULT_DIR/$filename"
    
    # 結果をローカルにコピー
    echo "結果を取得中: $filename"
    scp -i "$SSH_KEY_PATH" "$APP_SERVER:$latest_file" "$local_file"
    
    # 直接mysqldumpslowで詳細分析を実行
    echo ""
    echo "=== 詳細スロークエリ分析（整理済み） ==="
    echo ""
    
    echo "サーバーで詳細分析を実行中..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "
        echo '=== 実行時間順TOP20（最重要） ==='
        echo '※ 合計実行時間が長いクエリ（最優先で最適化）'
        echo ''
        if [[ -f /var/log/mysql/mysql-slow.log ]] && [[ -s /var/log/mysql/mysql-slow.log ]]; then
            mysqldumpslow -s t -t 20 /var/log/mysql/mysql-slow.log | head -40
        else
            echo 'スロークエリログが空またはファイルが見つかりません'
        fi
        
        echo ''
        echo '=== 実行回数順TOP20（頻度重要） ==='
        echo '※ 実行回数が多いクエリ（N+1問題など）'
        echo ''
        if [[ -f /var/log/mysql/mysql-slow.log ]] && [[ -s /var/log/mysql/mysql-slow.log ]]; then
            mysqldumpslow -s c -t 20 /var/log/mysql/mysql-slow.log | head -40
        else
            echo 'スロークエリログが空またはファイルが見つかりません'
        fi
        
        echo ''
        echo '=== 平均実行時間順TOP20（個別最適化） ==='
        echo '※ 1クエリあたりの実行時間が長い（重いクエリ）'
        echo ''
        if [[ -f /var/log/mysql/mysql-slow.log ]] && [[ -s /var/log/mysql/mysql-slow.log ]]; then
            mysqldumpslow -s at -t 20 /var/log/mysql/mysql-slow.log | head -40
        else
            echo 'スロークエリログが空またはファイルが見つかりません'
        fi
        
        echo ''
        echo '=== ロック時間順TOP10（競合問題） ==='
        echo '※ ロック待機時間が長いクエリ（デッドロック対策）'
        echo ''
        if [[ -f /var/log/mysql/mysql-slow.log ]] && [[ -s /var/log/mysql/mysql-slow.log ]]; then
            mysqldumpslow -s l -t 10 /var/log/mysql/mysql-slow.log | head -25
        else
            echo 'スロークエリログが空またはファイルが見つかりません'
        fi
        
        echo ''
        echo '=== スロークエリ統計サマリー ==='
        if [[ -f /var/log/mysql/mysql-slow.log ]] && [[ -s /var/log/mysql/mysql-slow.log ]]; then
            echo \"総クエリ数: \$(grep '^# Time:' /var/log/mysql/mysql-slow.log | wc -l)\"
            echo \"ユニークパターン数: \$(mysqldumpslow /var/log/mysql/mysql-slow.log | grep -c '^Count:')\"
            echo \"ログファイルサイズ: \$(du -h /var/log/mysql/mysql-slow.log | cut -f1)\"
            echo \"最新エントリ時刻: \$(grep '^# Time:' /var/log/mysql/mysql-slow.log | tail -1 | cut -d' ' -f3-)\"
        else
            echo '統計情報を取得できません（ログファイルが空）'
        fi
    " | tee "$LOCAL_RESULT_DIR/slowquery_detailed_$(date +%Y%m%d_%H%M%S).txt"
    
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

# クエリ最適化のヒント表示
show_optimization_tips() {
    echo ""
    echo "=== スロークエリ最適化のヒント ==="
    echo ""
    echo "📊 分析結果の見方："
    echo "  Count: 実行回数"
    echo "  Time: 平均実行時間（合計実行時間）"
    echo "  Lock: 平均ロック時間（合計ロック時間）"
    echo "  Rows: 平均行数（合計行数）"
    echo ""
    echo "🎯 最適化優先度："
    echo "  1. 実行時間順TOP5 - 全体パフォーマンスに最大の影響"
    echo "  2. 実行回数順TOP3 - N+1問題やループ内クエリ"
    echo "  3. 平均時間順TOP3 - インデックス追加の効果が大きい"
    echo "  4. ロック時間順TOP3 - デッドロック・競合の解消"
    echo ""
    echo "🔧 よくある最適化："
    echo "  • WHERE句の列にINDEX追加"
    echo "  • ORDER BY句の列にINDEX追加"
    echo "  • JOINの結合キーにINDEX追加"
    echo "  • N+1問題 → JOINまたはIN句で一括取得"
    echo "  • SELECT * → 必要な列のみ指定"
}

# メイン処理
case "${1:-}" in
    analyze)
        run_analysis
        fetch_and_display
        show_optimization_tips
        ;;
    clean)
        clean_results
        ;;
    tips)
        show_optimization_tips
        ;;
    --help|-h)
        show_help
        ;;
    *)
        fetch_and_display
        show_optimization_tips
        ;;
esac