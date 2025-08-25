#!/bin/bash

# ISUCON用スロークエリ分析ツール - 運用スクリプト
# 使用方法: ./slowquery_analysis.sh [start|analyze|compare]

set -euo pipefail

# 共通関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/common_functions.sh"

LOG_DIR="${SCRIPT_DIR}/slowquery_logs"
ANALYSIS_DIR="${SCRIPT_DIR}/slowquery_analysis"
LOG_FILE="${SCRIPT_DIR}/slowquery_analysis.log"
SLOWLOG_FILE="/var/log/mysql/mysql-slow.log"

# ヘルプ表示
show_help() {
    cat << EOF
ISUCON用スロークエリ分析ツール - 運用スクリプト

使用方法:
  ./slowquery_analysis.sh [コマンド] [オプション]

コマンド:
  start      スロークエリログの記録を開始（ローテート）
  analyze    現在のスロークエリログを分析
  compare    過去の分析結果と比較
  reset      スロークエリログをリセット
  
オプション:
  -h, --help     このヘルプを表示
  -t, --top N    上位N件の結果を表示（デフォルト: 10）
  -s, --sort     ソート順序 (t:時間順, c:回数順, a:平均順) (デフォルト: t)

例:
  ./slowquery_analysis.sh start          # 記録開始（ベンチマーク前）
  ./slowquery_analysis.sh analyze        # 分析実行（ベンチマーク後）
  ./slowquery_analysis.sh analyze -t 20  # 上位20件を表示
  ./slowquery_analysis.sh compare        # 過去結果との比較

フロー例:
  1. ベンチマーク前: ./slowquery_analysis.sh start
  2. ベンチマーク実行
  3. ベンチマーク後: ./slowquery_analysis.sh analyze

EOF
}

# 必要なディレクトリの作成
create_directories() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$ANALYSIS_DIR"
}

# スロークエリログの確認
check_slowlog() {
    if [[ ! -f "$SLOWLOG_FILE" ]]; then
        error "スロークエリログファイルが見つかりません: $SLOWLOG_FILE"
        error "setup_slowquery.shを実行してください"
        return 1
    fi
    
    # MySQL接続テスト
    if ! test_mysql_connection; then
        error "MySQL接続に失敗しました"
        return 1
    fi
    
    # MySQL設定確認
    local slow_log_enabled
    slow_log_enabled=$($(mysql_cmd) -sNe "SELECT @@slow_query_log" 2>/dev/null || echo "0")
    
    if [[ "$slow_log_enabled" != "1" ]]; then
        error "スロークエリログが無効です"
        error "setup_slowquery.shを実行してください"
        return 1
    fi
    
    return 0
}

# スロークエリログのローテート（記録開始）
start_logging() {
    info "スロークエリログ記録を開始します..."
    
    if ! check_slowlog; then
        return 1
    fi
    
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${LOG_DIR}/mysql-slow_${timestamp}.log"
    
    # 既存ログをバックアップ
    if [[ -s "$SLOWLOG_FILE" ]]; then
        info "既存ログをバックアップ: $backup_file"
        sudo cp "$SLOWLOG_FILE" "$backup_file"
        sudo chown "$(whoami):$(whoami)" "$backup_file"
    fi
    
    # ログファイルをリセット
    info "スロークエリログをリセットしています..."
    sudo truncate -s 0 "$SLOWLOG_FILE"
    
    # MySQLに対してフラッシュを実行
    $(mysql_cmd) -e "FLUSH LOGS;" 2>/dev/null || warning "FLUSH LOGSの実行に失敗しました"
    
    success "スロークエリログ記録開始完了"
    info "ベンチマークを実行してください"
}

# mysqldumpslowのインストール確認
check_mysqldumpslow() {
    if ! command -v mysqldumpslow &> /dev/null; then
        error "mysqldumpslowが見つかりません"
        info "以下のコマンドでインストールしてください:"
        info "sudo apt-get update && sudo apt-get install mysql-client"
        return 1
    fi
    return 0
}

# スロークエリ分析実行
analyze_queries() {
    local top_count="${1:-10}"
    local sort_order="${2:-t}"
    
    info "スロークエリ分析を実行します（上位${top_count}件、ソート: ${sort_order}）"
    
    if ! check_slowlog; then
        return 1
    fi
    
    if ! check_mysqldumpslow; then
        return 1
    fi
    
    if [[ ! -s "$SLOWLOG_FILE" ]]; then
        warning "スロークエリログが空です"
        info "ベンチマークを実行するか、start_logging後にベンチマークを実行してください"
        return 1
    fi
    
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local analysis_file="${ANALYSIS_DIR}/analysis_${timestamp}.txt"
    
    info "分析結果を保存: $analysis_file"
    
    {
        echo "=== スロークエリ分析結果 ==="
        echo "分析日時: $(date)"
        echo "対象ファイル: $SLOWLOG_FILE"
        echo "ファイルサイズ: $(du -h "$SLOWLOG_FILE" | cut -f1)"
        echo "総クエリ数: $(grep -c '^# Time:' "$SLOWLOG_FILE" || echo '0')"
        echo ""
        
        echo "=== 実行時間順上位${top_count}件 ==="
        mysqldumpslow -s t -t "$top_count" "$SLOWLOG_FILE" | head -50
        echo ""
        
        echo "=== 実行回数順上位${top_count}件 ==="
        mysqldumpslow -s c -t "$top_count" "$SLOWLOG_FILE" | head -50
        echo ""
        
        echo "=== 平均実行時間順上位${top_count}件 ==="
        mysqldumpslow -s a -t "$top_count" "$SLOWLOG_FILE" | head -50
        echo ""
        
        echo "=== 詳細統計情報 ==="
        echo "# 実行時間別分布"
        awk '
        /^# Query_time: / {
            time = $3
            if (time < 0.1) range_01++
            else if (time < 0.5) range_05++
            else if (time < 1.0) range_10++
            else if (time < 5.0) range_50++
            else range_over5++
            total++
        }
        END {
            print "0.1秒未満:", range_01+0, "件"
            print "0.1-0.5秒:", range_05+0, "件"
            print "0.5-1.0秒:", range_10+0, "件"  
            print "1.0-5.0秒:", range_50+0, "件"
            print "5.0秒以上:", range_over5+0, "件"
            print "総計:", total+0, "件"
        }' "$SLOWLOG_FILE"
        
    } | tee "$analysis_file"
    
    success "分析が完了しました: $analysis_file"
    echo
    info "最新の分析結果:"
    tail -20 "$analysis_file"
    
    # 結果のサマリー表示
    echo
    echo "=== クイックサマリー ==="
    echo "総クエリ数: $(grep -c '^# Time:' "$SLOWLOG_FILE" || echo '0')"
    echo "最も遅いクエリ:"
    mysqldumpslow -s t -t 1 "$SLOWLOG_FILE" | grep -A 5 "Count:" | head -10
}

# 分析結果の比較
compare_results() {
    info "過去の分析結果と比較します..."
    
    local analysis_files
    analysis_files=($(ls -t "${ANALYSIS_DIR}"/analysis_*.txt 2>/dev/null || echo ""))
    
    if [[ ${#analysis_files[@]} -lt 2 ]]; then
        warning "比較するための分析結果が不足しています（${#analysis_files[@]}件）"
        info "analyze コマンドを実行して分析結果を蓄積してください"
        return 1
    fi
    
    local latest="${analysis_files[0]}"
    local previous="${analysis_files[1]}"
    
    info "最新: $(basename "$latest")"
    info "比較: $(basename "$previous")"
    
    echo
    echo "=== 比較結果 ==="
    
    # 総クエリ数の比較
    local latest_count
    local previous_count
    latest_count=$(grep "総クエリ数:" "$latest" | awk '{print $2}' || echo "0")
    previous_count=$(grep "総クエリ数:" "$previous" | awk '{print $2}' || echo "0")
    
    echo "総クエリ数: $previous_count → $latest_count"
    
    if [[ $latest_count -gt $previous_count ]]; then
        local increase=$((latest_count - previous_count))
        warning "クエリ数が${increase}件増加しています"
    elif [[ $latest_count -lt $previous_count ]]; then
        local decrease=$((previous_count - latest_count))
        success "クエリ数が${decrease}件減少しています"
    else
        info "クエリ数に変化なし"
    fi
    
    # 最も遅いクエリの比較
    echo
    echo "=== 最も遅いクエリの比較 ==="
    echo "【前回】"
    grep -A 3 "最も遅いクエリ:" "$previous" | tail -3
    echo
    echo "【今回】"
    grep -A 3 "最も遅いクエリ:" "$latest" | tail -3
    
    info "詳細な比較は以下のファイルを確認してください:"
    info "最新: $latest"
    info "前回: $previous"
}

# ログのリセット
reset_logs() {
    warning "スロークエリログをリセットします"
    read -p "続行しますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "リセットをキャンセルしました"
        return 0
    fi
    
    info "スロークエリログをリセットしています..."
    
    if [[ -f "$SLOWLOG_FILE" ]]; then
        sudo truncate -s 0 "$SLOWLOG_FILE"
        $(mysql_cmd) -e "FLUSH LOGS;" 2>/dev/null || warning "FLUSH LOGSの実行に失敗しました"
        success "スロークエリログをリセットしました"
    else
        warning "スロークエリログファイルが見つかりません"
    fi
}

# メイン処理
main() {
    local command=""
    local top_count=10
    local sort_order="t"
    
    # 引数がない場合はヘルプを表示
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    # コマンドライン引数の解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            start|analyze|compare|reset)
                command="$1"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -t|--top)
                top_count="$2"
                shift 2
                ;;
            -s|--sort)
                sort_order="$2"
                shift 2
                ;;
            *)
                error "不明なオプション: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    create_directories
    
    info "=== スロークエリ分析スクリプト開始 ==="
    info "コマンド: $command"
    
    case $command in
        start)
            start_logging
            ;;
        analyze)
            analyze_queries "$top_count" "$sort_order"
            ;;
        compare)
            compare_results
            ;;
        reset)
            reset_logs
            ;;
        *)
            error "不明なコマンド: $command"
            show_help
            exit 1
            ;;
    esac
    
    success "処理が完了しました"
}

main "$@"