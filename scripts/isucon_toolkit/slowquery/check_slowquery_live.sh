#!/bin/bash

# スロークエリをリアルタイムで確認するスクリプト

set -u

# 共通設定の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/config.env"

# 設定
LOCAL_RESULT_DIR="./slowquery_results"

show_help() {
    cat << EOF
スロークエリリアルタイム確認スクリプト

使用方法:
  ./check_slowquery_live.sh               # 現在のスロークエリを確認
  ./check_slowquery_live.sh start         # ログをリセットして記録開始
  ./check_slowquery_live.sh detailed      # 詳細分析結果を取得

機能:
  - リアルタイムでスロークエリの状況確認
  - mysqldumpslowによる詳細分析
  - 最適化のヒント表示
EOF
}

# スロークエリログをリセットして記録開始
start_logging() {
    echo "=== スロークエリログ記録開始 ==="
    
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "
        echo 'スロークエリの現在設定を確認中...'
        mysql -e \"
            SELECT @@slow_query_log as 'Slow Query Log',
                   @@slow_query_log_file as 'Log File', 
                   @@long_query_time as 'Threshold (sec)';
        \"
        
        echo ''
        echo 'スロークエリログをリセット中...'
        if [[ -f /var/log/mysql/mysql-slow.log ]]; then
            sudo truncate -s 0 /var/log/mysql/mysql-slow.log
            echo 'ログファイルをリセットしました'
        else
            echo 'ログファイルが見つかりません（初回実行時は正常）'
        fi
        
        echo ''
        echo 'スロークエリログ記録準備完了'
        echo 'ベンチマークを実行してください'
    "
}

# 現在のスロークエリ状況を確認
check_current_status() {
    echo "=== 現在のスロークエリ状況 ==="
    
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "
        echo '=== MySQL設定確認 ==='
        mysql -e \"
            SELECT @@slow_query_log as 'Enabled',
                   @@slow_query_log_file as 'Log File', 
                   @@long_query_time as 'Threshold';
        \" 2>/dev/null || echo 'MySQLに接続できません'
        
        echo ''
        echo '=== ログファイル状況 ==='
        if [[ -f /var/log/mysql/mysql-slow.log ]]; then
            echo \"ファイルサイズ: \$(du -h /var/log/mysql/mysql-slow.log | cut -f1)\"
            echo \"行数: \$(wc -l < /var/log/mysql/mysql-slow.log)\"
            echo \"クエリ数: \$(grep -c '^# Time:' /var/log/mysql/mysql-slow.log || echo 0)\"
            
            if [[ -s /var/log/mysql/mysql-slow.log ]]; then
                echo \"最新エントリ: \$(tail -5 /var/log/mysql/mysql-slow.log | grep '^# Time:' | tail -1 | cut -d' ' -f3- || echo 'なし')\"
            else
                echo '最新エントリ: ログが空です'
            fi
        else
            echo 'スロークエリログファイルが見つかりません'
        fi
    "
}

# 詳細分析結果を取得
get_detailed_analysis() {
    echo "=== 詳細スロークエリ分析 ==="
    
    # ローカルディレクトリ作成
    mkdir -p "$LOCAL_RESULT_DIR"
    
    echo "サーバーで詳細分析を実行中..."
    ssh -i "$SSH_KEY_PATH" "$APP_SERVER" "
        if [[ ! -f /var/log/mysql/mysql-slow.log ]] || [[ ! -s /var/log/mysql/mysql-slow.log ]]; then
            echo 'スロークエリログが空です'
            echo 'ベンチマークを実行してからもう一度お試しください'
            exit 1
        fi
        
        echo '=== 🔥 実行時間順TOP10（最重要）==='
        echo '※ 合計実行時間が長い = 全体パフォーマンスへの影響大'
        echo ''
        mysqldumpslow -s t -t 10 /var/log/mysql/mysql-slow.log
        
        echo ''
        echo '=== 📈 実行回数順TOP10（頻度重要）==='
        echo '※ 実行回数が多い = N+1問題の可能性'
        echo ''
        mysqldumpslow -s c -t 10 /var/log/mysql/mysql-slow.log
        
        echo ''
        echo '=== ⏱️ 平均実行時間順TOP10（個別最適化）==='
        echo '※ 1回あたりの実行時間が長い = インデックス効果大'
        echo ''
        mysqldumpslow -s at -t 10 /var/log/mysql/mysql-slow.log
        
        echo ''
        echo '=== 📊 統計サマリー ==='
        total_queries=\$(grep -c '^# Time:' /var/log/mysql/mysql-slow.log)
        unique_patterns=\$(mysqldumpslow /var/log/mysql/mysql-slow.log 2>/dev/null | grep -c '^Count:' || echo 0)
        
        echo \"総スロークエリ数: \$total_queries\"
        echo \"ユニークパターン数: \$unique_patterns\"
        echo \"平均パターン実行回数: \$(( total_queries > 0 && unique_patterns > 0 ? total_queries / unique_patterns : 0 ))\"
        echo \"ログファイルサイズ: \$(du -h /var/log/mysql/mysql-slow.log | cut -f1)\"
        
        echo ''
        echo '=== 💡 最適化推奨アクション ==='
        
        # 実行時間TOP3の簡単な分析
        echo '【実行時間TOP3への対策】'
        mysqldumpslow -s t -t 3 /var/log/mysql/mysql-slow.log | grep -A3 '^Count:' | grep -v '^--' | while IFS= read -r line; do
            if [[ \$line =~ ^Count: ]]; then
                echo \"  → \$line\" 
            elif [[ \$line =~ ^[[:space:]]*SELECT ]] || [[ \$line =~ ^[[:space:]]*UPDATE ]] || [[ \$line =~ ^[[:space:]]*INSERT ]] || [[ \$line =~ ^[[:space:]]*DELETE ]]; then
                echo \"    \$line\"
                if [[ \$line =~ WHERE.*= ]]; then
                    echo \"    💡 WHERE句の列にインデックス追加を検討\"
                fi
                if [[ \$line =~ ORDER[[:space:]]+BY ]]; then
                    echo \"    💡 ORDER BY句の列にインデックス追加を検討\"  
                fi
                if [[ \$line =~ JOIN ]]; then
                    echo \"    💡 JOIN条件の列にインデックス追加を検討\"
                fi
            fi
        done 2>/dev/null || echo '  分析データを取得中...'
        
    " | tee "$LOCAL_RESULT_DIR/slowquery_live_$(date +%Y%m%d_%H%M%S).txt"
    
    echo ""
    echo "=== 結果をローカルに保存しました ==="
    echo "保存先: $LOCAL_RESULT_DIR/"
    ls -la "$LOCAL_RESULT_DIR/" | tail -5
}

# 最適化のヒント表示
show_optimization_guide() {
    echo ""
    echo "=== 🔧 スロークエリ最適化ガイド ==="
    echo ""
    echo "📊 結果の読み方:"
    echo "  Count: 実行回数"
    echo "  Time=XXXs (YYYs): 平均実行時間（合計実行時間）" 
    echo "  Lock=XXXs (YYYs): 平均ロック時間（合計ロック時間）"
    echo "  Rows=XXX (YYY): 平均行数（合計行数）"
    echo ""
    echo "🎯 最適化の優先順位:"
    echo "  1️⃣ 実行時間順TOP3 → 全体への影響が最大"
    echo "  2️⃣ 実行回数順TOP3 → N+1問題など頻度問題"  
    echo "  3️⃣ 平均時間順TOP3 → 個別クエリの重さ問題"
    echo ""
    echo "🛠️ よくある対策:"
    echo "  • WHERE条件の列 → CREATE INDEX idx_xxx ON table(column)"
    echo "  • ORDER BY列 → CREATE INDEX idx_xxx ON table(order_column)"
    echo "  • JOIN条件 → 両テーブルの結合キーにINDEX"
    echo "  • SELECT * → 必要な列のみ指定"
    echo "  • N+1問題 → JOINで一括取得 or IN句でまとめて取得"
    echo ""
    echo "📝 次のステップ:"
    echo "  1. 上記結果からTOP3のクエリを特定"
    echo "  2. EXPLAINで実行計画を確認"  
    echo "  3. 適切なINDEXを追加"
    echo "  4. 再度ベンチマーク実行して効果測定"
}

# メイン処理
case "${1:-}" in
    start)
        start_logging
        ;;
    detailed)
        get_detailed_analysis
        show_optimization_guide
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        check_current_status
        echo ""
        echo "詳細分析: ./check_slowquery_live.sh detailed"
        echo "ログリセット: ./check_slowquery_live.sh start"
        ;;
esac