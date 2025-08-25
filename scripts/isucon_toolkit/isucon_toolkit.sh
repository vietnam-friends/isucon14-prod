#!/bin/bash

# ISUCON汎用分析ツール - 統合管理スクリプト
# 使用方法: ./isucon_toolkit.sh [コマンド] [オプション]

set -euo pipefail

# 共通関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_functions.sh"

LOG_FILE="${SCRIPT_DIR}/isucon_toolkit.log"
REPORT_DIR="${SCRIPT_DIR}/reports"

# ヘルプ表示
show_help() {
    cat << EOF
${CYAN}ISUCON汎用分析ツールキット${NC}

使用方法:
  ./isucon_toolkit.sh [コマンド] [オプション]

${YELLOW}メインコマンド:${NC}
  setup              全ツールの初期設定を一括実行
  start              ベンチマーク前の準備（ログローテート等）
  analyze            ベンチマーク後の分析実行
  report             統合レポートの生成
  compare            過去結果との比較
  status             現在の設定状況確認
  cleanup            設定の無効化とクリーンアップ

${YELLOW}個別ツールコマンド:${NC}
  setup-slowquery    スロークエリ分析ツールのセットアップ
  setup-alp          alp分析ツールのセットアップ
  setup-pprof        pprof分析ツールのセットアップ
  
  start-slowquery    スロークエリ記録開始
  start-alp          アクセスログ記録開始
  start-pprof        pprofサーバー確認
  
  analyze-slowquery  スロークエリ分析実行
  analyze-alp        alp分析実行
  analyze-pprof      pprof分析実行

${YELLOW}オプション:${NC}
  -h, --help         このヘルプを表示
  -v, --verbose      詳細出力
  -f, --force        確認をスキップして強制実行
  --parallel         可能な処理を並行実行
  --skip-setup       セットアップ済みの場合にスキップ

${YELLOW}基本フロー例:${NC}
  1. ${GREEN}./isucon_toolkit.sh setup${NC}          # 初期設定
  2. ${GREEN}./isucon_toolkit.sh start${NC}           # ベンチマーク前準備
  3. ${YELLOW}[ベンチマーク実行]${NC}                      # 手動でベンチマーク実行
  4. ${GREEN}./isucon_toolkit.sh analyze${NC}         # 分析実行
  5. ${GREEN}./isucon_toolkit.sh report${NC}          # レポート生成

${YELLOW}高度な使用例:${NC}
  ./isucon_toolkit.sh setup --parallel         # 並行セットアップ
  ./isucon_toolkit.sh analyze --verbose        # 詳細分析
  ./isucon_toolkit.sh report --force           # 強制レポート生成
  ./isucon_toolkit.sh status                   # 現在の状況確認

EOF
}

# 実行時間測定用
start_timer() {
    echo "$(date +%s)"
}

end_timer() {
    local start_time="$1"
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "${duration}秒"
}

# 統合ステータス確認
show_status() {
    local verbose="${1:-false}"
    
    header "ISUCON分析ツールキット 状況確認"
    
    echo
    info "=== システム情報 ==="
    info "OS: $(uname -s) $(uname -r)"
    info "ホスト: $(hostname)"
    info "日時: $(date)"
    info "作業ディレクトリ: $SCRIPT_DIR"
    echo
    
    info "=== ツール状況 ==="
    
    # スロークエリ分析
    echo -n "スロークエリ分析: "
    if $(mysql_cmd) -e "SELECT @@slow_query_log" 2>/dev/null | grep -q "1"; then
        success "✓ 有効"
        if [[ "$verbose" == true ]]; then
            local slow_time
            slow_time=$($(mysql_cmd) -sNe "SELECT @@long_query_time" 2>/dev/null || echo "unknown")
            info "  閾値: ${slow_time}秒"
        fi
    else
        warning "× 無効"
    fi
    
    # alp分析
    echo -n "alp分析: "
    if command -v alp >/dev/null 2>&1; then
        success "✓ インストール済み"
        if [[ "$verbose" == true ]]; then
            local alp_version
            alp_version=$(alp --version 2>&1 | head -1 || echo "unknown")
            info "  バージョン: $alp_version"
        fi
    else
        warning "× 未インストール"
    fi
    
    # Nginx状況
    echo -n "Nginx: "
    if systemctl is-active "$NGINX_SERVICE" >/dev/null 2>&1; then
        success "✓ 起動中"
        if [[ "$verbose" == true ]]; then
            if [[ -f "$NGINX_ACCESS_LOG" ]]; then
                local log_size
                log_size=$(du -h "$NGINX_ACCESS_LOG" | cut -f1)
                info "  アクセスログサイズ: $log_size"
            fi
        fi
    else
        warning "× 停止中"
    fi
    
    # pprof分析
    echo -n "pprof分析: "
    if command -v go >/dev/null 2>&1; then
        success "✓ Go利用可能"
        if [[ "$verbose" == true ]]; then
            local go_version
            go_version=$(go version)
            info "  $go_version"
        fi
        
        # pprofサーバーの確認
        if curl -s "http://${PPROF_HOST}:${PPROF_PORT}/debug/pprof/" >/dev/null 2>&1; then
            success "  ✓ pprofサーバー起動中"
        else
            warning "  × pprofサーバー未起動"
        fi
    else
        warning "× Go未インストール"
    fi
    
    echo
    info "=== ディスク使用状況 ==="
    local dirs=("$SCRIPT_DIR/slowquery/slowquery_logs" "$SCRIPT_DIR/slowquery/slowquery_analysis" "$SCRIPT_DIR/alp/alp_logs" "$SCRIPT_DIR/alp/alp_analysis" "$SCRIPT_DIR/pprof/pprof_data" "$SCRIPT_DIR/pprof/pprof_analysis" "$REPORT_DIR")
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local size
            local count
            size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
            count=$(find "$dir" -type f 2>/dev/null | wc -l || echo "0")
            info "$(basename "$dir"): ${size} (${count}ファイル)"
        else
            info "$(basename "$dir"): 未作成"
        fi
    done
    
    echo
    success "状況確認完了"
}

# 統合セットアップ
run_setup() {
    local parallel="${1:-false}"
    local verbose="${2:-false}"
    local skip_setup="${3:-false}"
    
    header "ISUCON分析ツールキット セットアップ開始"
    
    local setup_timer
    setup_timer=$(start_timer)
    
    # 必要なディレクトリ作成
    step "必要なディレクトリを作成中..."
    mkdir -p "$REPORT_DIR"
    success "ディレクトリ作成完了"
    
    local setup_pids=()
    local setup_results=()
    
    if [[ "$parallel" == true ]]; then
        step "並行セットアップを開始..."
        
        # 並行実行
        {
            if [[ "$skip_setup" != true ]]; then
                info "スロークエリセットアップ開始..."
                if "$SCRIPT_DIR/setup_slowquery.sh" >> "$LOG_FILE" 2>&1; then
                    echo "slowquery:success"
                else
                    echo "slowquery:failed"
                fi
            else
                echo "slowquery:skipped"
            fi
        } &
        setup_pids+=($!)
        
        {
            if [[ "$skip_setup" != true ]]; then
                info "alpセットアップ開始..."
                if "$SCRIPT_DIR/setup_alp.sh" >> "$LOG_FILE" 2>&1; then
                    echo "alp:success"
                else
                    echo "alp:failed"
                fi
            else
                echo "alp:skipped"
            fi
        } &
        setup_pids+=($!)
        
        {
            if [[ "$skip_setup" != true ]]; then
                info "pprofセットアップ開始..."
                if "$SCRIPT_DIR/setup_pprof.sh" >> "$LOG_FILE" 2>&1; then
                    echo "pprof:success"
                else
                    echo "pprof:failed"
                fi
            else
                echo "pprof:skipped"
            fi
        } &
        setup_pids+=($!)
        
        # 結果待機
        for pid in "${setup_pids[@]}"; do
            wait "$pid"
        done
        
    else
        step "順次セットアップを開始..."
        
        # 順次実行
        if [[ "$skip_setup" != true ]]; then
            step "1/3: スロークエリ分析セットアップ..."
            if [[ "$verbose" == true ]]; then
                "$SCRIPT_DIR/setup/setup_slowquery.sh"
            else
                "$SCRIPT_DIR/setup/setup_slowquery.sh" >> "$LOG_FILE" 2>&1
            fi && success "スロークエリセットアップ完了" || error "スロークエリセットアップ失敗"
            
            step "2/3: alp分析セットアップ..."
            if [[ "$verbose" == true ]]; then
                "$SCRIPT_DIR/setup/setup_alp.sh"
            else
                "$SCRIPT_DIR/setup/setup_alp.sh" >> "$LOG_FILE" 2>&1
            fi && success "alpセットアップ完了" || error "alpセットアップ失敗"
            
            step "3/3: pprof分析セットアップ..."
            if [[ "$verbose" == true ]]; then
                "$SCRIPT_DIR/setup/setup_pprof.sh"
            else
                "$SCRIPT_DIR/setup/setup_pprof.sh" >> "$LOG_FILE" 2>&1
            fi && success "pprofセットアップ完了" || error "pprofセットアップ失敗"
        else
            info "セットアップをスキップしました"
        fi
    fi
    
    local setup_duration
    setup_duration=$(end_timer "$setup_timer")
    
    success "統合セットアップ完了 (所要時間: $setup_duration)"
    
    # セットアップ後の状況確認
    echo
    info "セットアップ後の状況確認..."
    show_status false
}

# ベンチマーク前準備
run_start() {
    local parallel="${1:-false}"
    local verbose="${2:-false}"
    
    header "ベンチマーク前準備開始"
    
    local start_timer
    start_timer=$(start_timer)
    
    if [[ "$parallel" == true ]]; then
        step "並行準備を開始..."
        
        {
            info "スロークエリ記録開始..."
            "$SCRIPT_DIR/slowquery/slowquery_analysis.sh" start >> "$LOG_FILE" 2>&1 && echo "slowquery:success" || echo "slowquery:failed"
        } &
        
        {
            info "アクセスログ記録開始..."
            "$SCRIPT_DIR/alp/alp_analysis.sh" start >> "$LOG_FILE" 2>&1 && echo "alp:success" || echo "alp:failed"
        } &
        
        {
            info "pprofサーバー確認..."
            "$SCRIPT_DIR/pprof/pprof_workflow.sh" start >> "$LOG_FILE" 2>&1 && echo "pprof:success" || echo "pprof:failed"
        } &
        
        wait
        
    else
        step "順次準備を開始..."
        
        step "1/3: スロークエリ記録開始..."
        if [[ "$verbose" == true ]]; then
            "$SCRIPT_DIR/slowquery/slowquery_analysis.sh" start
        else
            "$SCRIPT_DIR/slowquery/slowquery_analysis.sh" start >> "$LOG_FILE" 2>&1
        fi && success "スロークエリ記録開始完了" || error "スロークエリ記録開始失敗"
        
        step "2/3: アクセスログ記録開始..."
        if [[ "$verbose" == true ]]; then
            "$SCRIPT_DIR/alp/alp_analysis.sh" start
        else
            "$SCRIPT_DIR/alp/alp_analysis.sh" start >> "$LOG_FILE" 2>&1
        fi && success "アクセスログ記録開始完了" || error "アクセスログ記録開始失敗"
        
        step "3/3: pprofサーバー確認..."
        if [[ "$verbose" == true ]]; then
            "$SCRIPT_DIR/pprof/pprof_workflow.sh" start
        else
            "$SCRIPT_DIR/pprof/pprof_workflow.sh" start >> "$LOG_FILE" 2>&1
        fi && success "pprofサーバー確認完了" || error "pprofサーバー確認失敗"
    fi
    
    local start_duration
    start_duration=$(end_timer "$start_timer")
    
    success "ベンチマーク前準備完了 (所要時間: $start_duration)"
    
    echo
    warning "=== 次の手順 ==="
    warning "1. ベンチマークを実行してください"
    warning "2. ベンチマーク完了後、以下のコマンドを実行:"
    warning "   ./isucon_toolkit.sh analyze"
    echo
}

# 統合分析実行
run_analyze() {
    local parallel="${1:-false}"
    local verbose="${2:-false}"
    
    header "統合分析実行開始"
    
    local analyze_timer
    analyze_timer=$(start_timer)
    
    if [[ "$parallel" == true ]]; then
        step "並行分析を開始..."
        
        {
            info "スロークエリ分析実行..."
            "$SCRIPT_DIR/slowquery/slowquery_analysis.sh" analyze >> "$LOG_FILE" 2>&1 && echo "slowquery:success" || echo "slowquery:failed"
        } &
        
        {
            info "alp分析実行..."
            "$SCRIPT_DIR/alp/alp_analysis.sh" analyze >> "$LOG_FILE" 2>&1 && echo "alp:success" || echo "alp:failed"
        } &
        
        {
            info "pprof分析実行..."
            "$SCRIPT_DIR/pprof/pprof_workflow.sh" analyze >> "$LOG_FILE" 2>&1 && echo "pprof:success" || echo "pprof:failed"
        } &
        
        wait
        
    else
        step "順次分析を開始..."
        
        step "1/3: スロークエリ分析実行..."
        if [[ "$verbose" == true ]]; then
            "$SCRIPT_DIR/slowquery/slowquery_analysis.sh" analyze
        else
            "$SCRIPT_DIR/slowquery/slowquery_analysis.sh" analyze >> "$LOG_FILE" 2>&1
        fi && success "スロークエリ分析完了" || error "スロークエリ分析失敗"
        
        step "2/3: alp分析実行..."
        if [[ "$verbose" == true ]]; then
            "$SCRIPT_DIR/alp/alp_analysis.sh" analyze
        else
            "$SCRIPT_DIR/alp/alp_analysis.sh" analyze >> "$LOG_FILE" 2>&1
        fi && success "alp分析完了" || error "alp分析失敗"
        
        step "3/3: pprof分析実行..."
        if [[ "$verbose" == true ]]; then
            "$SCRIPT_DIR/pprof/pprof_workflow.sh" analyze
        else
            "$SCRIPT_DIR/pprof/pprof_workflow.sh" analyze >> "$LOG_FILE" 2>&1
        fi && success "pprof分析完了" || error "pprof分析失敗"
    fi
    
    local analyze_duration
    analyze_duration=$(end_timer "$analyze_timer")
    
    success "統合分析実行完了 (所要時間: $analyze_duration)"
    
    echo
    info "次は統合レポートを生成します:"
    info "./isucon_toolkit.sh report"
}

# 統合レポート生成
generate_report() {
    local force="${1:-false}"
    
    header "統合レポート生成開始"
    
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local report_file="${REPORT_DIR}/isucon_report_${timestamp}.md"
    
    if [[ -f "$report_file" && "$force" != true ]]; then
        warning "レポートファイルが既に存在します: $report_file"
        read -p "上書きしますか？ (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "レポート生成をキャンセルしました"
            return 0
        fi
    fi
    
    step "統合レポートを生成中..."
    
    {
        echo "# ISUCON分析レポート"
        echo
        echo "生成日時: $(date)"
        echo "ホスト: $(hostname)"
        echo
        
        echo "## システム情報"
        echo
        echo "- OS: $(uname -s) $(uname -r)"
        echo "- CPU: $(nproc) cores"
        echo "- メモリ: $(free -h | grep '^Mem:' | awk '{print $2}' || echo 'unknown')"
        echo "- ディスク: $(df -h / | tail -1 | awk '{print $2" ("$5" used)"}')"
        echo
        
        echo "## スロークエリ分析結果"
        echo
        local latest_slowquery
        latest_slowquery=$(find "$SCRIPT_DIR/slowquery/slowquery_analysis" -name "analysis_*.txt" -type f 2>/dev/null | sort -t_ -k2 -r | head -1 || echo "")
        
        if [[ -n "$latest_slowquery" && -f "$latest_slowquery" ]]; then
            echo '```'
            tail -50 "$latest_slowquery" | head -30
            echo '```'
            echo
            echo "詳細: $(basename "$latest_slowquery")"
        else
            echo "分析結果が見つかりません"
        fi
        echo
        
        echo "## alp分析結果"
        echo
        local latest_alp
        latest_alp=$(find "$SCRIPT_DIR/alp/alp_analysis" -name "alp_analysis_*.txt" -type f 2>/dev/null | sort -t_ -k3 -r | head -1 || echo "")
        
        if [[ -n "$latest_alp" && -f "$latest_alp" ]]; then
            echo '```'
            tail -50 "$latest_alp" | head -30
            echo '```'
            echo
            echo "詳細: $(basename "$latest_alp")"
        else
            echo "分析結果が見つかりません"
        fi
        echo
        
        echo "## pprof分析結果"
        echo
        local latest_pprof
        latest_pprof=$(find "$SCRIPT_DIR/pprof/pprof_analysis" -name "analysis_*.txt" -type f 2>/dev/null | sort -t_ -k2 -r | head -1 || echo "")
        
        if [[ -n "$latest_pprof" && -f "$latest_pprof" ]]; then
            echo '```'
            tail -50 "$latest_pprof" | head -30
            echo '```'
            echo
            echo "詳細: $(basename "$latest_pprof")"
        else
            echo "分析結果が見つかりません"
        fi
        echo
        
        echo "## パフォーマンスサマリー"
        echo
        
        # スロークエリ統計
        if [[ -n "$latest_slowquery" && -f "$latest_slowquery" ]]; then
            local query_count
            query_count=$(grep "総クエリ数:" "$latest_slowquery" | awk '{print $2}' || echo "0")
            echo "- 総スロークエリ数: $query_count"
        fi
        
        # アクセス統計
        if [[ -n "$latest_alp" && -f "$latest_alp" ]]; then
            local request_count
            request_count=$(grep "総リクエスト数:" "$latest_alp" | awk '{print $2}' || echo "0")
            echo "- 総リクエスト数: $request_count"
        fi
        
        echo
        echo "## 改善提案"
        echo
        
        # 簡単な改善提案を生成
        if [[ -n "$latest_slowquery" && -f "$latest_slowquery" ]]; then
            local slow_count
            slow_count=$(grep "総クエリ数:" "$latest_slowquery" | awk '{print $2}' || echo "0")
            if [[ $slow_count -gt 100 ]]; then
                echo "- **データベース**: スロークエリが${slow_count}件検出されました。インデックスの追加を検討してください"
            fi
        fi
        
        if [[ -n "$latest_alp" && -f "$latest_alp" ]]; then
            # 5秒以上のリクエストをチェック
            if grep -q "5.0秒以上:" "$latest_alp"; then
                local slow_requests
                slow_requests=$(grep "5.0秒以上:" "$latest_alp" | awk '{print $2}' || echo "0")
                if [[ $slow_requests -gt 0 ]]; then
                    echo "- **Webアプリ**: 5秒以上のリクエストが${slow_requests}件あります。処理の最適化が必要です"
                fi
            fi
        fi
        
        echo
        echo "---"
        echo "Generated by ISUCON Toolkit"
        
    } > "$report_file"
    
    success "統合レポート生成完了: $report_file"
    
    echo
    info "=== レポートサマリー ==="
    head -20 "$report_file"
    echo
    info "完全なレポート: $report_file"
}

# クリーンアップ
run_cleanup() {
    local force="${1:-false}"
    
    header "クリーンアップ開始"
    
    if [[ "$force" != true ]]; then
        warning "以下の処理を実行します:"
        warning "1. スロークエリログの無効化"
        warning "2. 分析結果ファイルの整理"
        warning "3. 一時ファイルの削除"
        echo
        read -p "続行しますか？ (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "クリーンアップをキャンセルしました"
            return 0
        fi
    fi
    
    step "スロークエリ設定の無効化..."
    "$SCRIPT_DIR/setup/disable_slowquery.sh" --keep-logs >> "$LOG_FILE" 2>&1 && success "スロークエリ無効化完了" || warning "スロークエリ無効化に問題あり"
    
    step "古い分析ファイルの整理..."
    local dirs=("$SCRIPT_DIR/slowquery/slowquery_analysis" "$SCRIPT_DIR/alp/alp_analysis" "$SCRIPT_DIR/pprof/pprof_analysis")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # 最新5件以外を削除
            find "$dir" -name "analysis_*.txt" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
            info "$(basename "$dir"): 古いファイルを削除"
        fi
    done
    
    step "一時ファイルの削除..."
    find "$SCRIPT_DIR" -name "*.tmp" -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -name "*.backup.*" -mtime +7 -delete 2>/dev/null || true
    
    success "クリーンアップ完了"
}

# メイン処理
main() {
    local command=""
    local verbose=false
    local force=false
    local parallel=false
    local skip_setup=false
    
    # 引数がない場合はヘルプを表示
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    # コマンドライン引数の解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            setup|start|analyze|report|compare|status|cleanup)
                command="$1"
                shift
                ;;
            setup-slowquery|setup-alp|setup-pprof|start-slowquery|start-alp|start-pprof|analyze-slowquery|analyze-alp|analyze-pprof)
                command="$1"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            --parallel)
                parallel=true
                shift
                ;;
            --skip-setup)
                skip_setup=true
                shift
                ;;
            *)
                error "不明なオプション: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    info "=== ISUCON Toolkit 実行開始 ==="
    info "コマンド: $command"
    
    case $command in
        setup)
            run_setup "$parallel" "$verbose" "$skip_setup"
            ;;
        start)
            run_start "$parallel" "$verbose"
            ;;
        analyze)
            run_analyze "$parallel" "$verbose"
            ;;
        report)
            generate_report "$force"
            ;;
        status)
            show_status "$verbose"
            ;;
        cleanup)
            run_cleanup "$force"
            ;;
        compare)
            info "個別ツールの比較機能を使用してください:"
            info "./slowquery/slowquery_analysis.sh compare"
            info "./alp/alp_analysis.sh compare"
            info "./pprof/pprof_workflow.sh compare"
            ;;
            
        # 個別コマンド
        setup-slowquery)
            "$SCRIPT_DIR/setup/setup_slowquery.sh"
            ;;
        setup-alp)
            "$SCRIPT_DIR/setup/setup_alp.sh"
            ;;
        setup-pprof)
            "$SCRIPT_DIR/setup/setup_pprof.sh"
            ;;
        start-slowquery)
            "$SCRIPT_DIR/slowquery/slowquery_analysis.sh" start
            ;;
        start-alp)
            "$SCRIPT_DIR/alp/alp_analysis.sh" start
            ;;
        start-pprof)
            "$SCRIPT_DIR/pprof/pprof_workflow.sh" start
            ;;
        analyze-slowquery)
            "$SCRIPT_DIR/slowquery/slowquery_analysis.sh" analyze
            ;;
        analyze-alp)
            "$SCRIPT_DIR/alp/alp_analysis.sh" analyze
            ;;
        analyze-pprof)
            "$SCRIPT_DIR/pprof/pprof_workflow.sh" analyze
            ;;
            
        *)
            error "不明なコマンド: $command"
            show_help
            exit 1
            ;;
    esac
    
    success "実行完了"
}

main "$@"