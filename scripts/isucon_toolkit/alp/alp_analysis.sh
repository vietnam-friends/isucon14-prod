#!/bin/bash

# alp分析スクリプト（JSON専用版）
# setup_alp.shでNginxをJSON形式に設定済みを前提

set -eu

# スクリプトのディレクトリ取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 共通設定と関数の読み込み
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/config.env"
source "${TOOLKIT_ROOT}/common_functions.sh"

# デフォルト設定（config.envで上書き可）
NGINX_ACCESS_LOG="${NGINX_ACCESS_LOG:-/var/log/nginx/access.log}"
ALP_LOGS_DIR="${SCRIPT_DIR}/alp_logs"
ANALYSIS_DIR="${SCRIPT_DIR}/alp_analysis"

# ディレクトリ作成
mkdir -p "$ALP_LOGS_DIR" "$ANALYSIS_DIR"

# alp存在確認
check_alp() {
    if ! command -v alp &> /dev/null; then
        error "alpがインストールされていません"
        error "setup_alp.sh を実行してインストールしてください"
        return 1
    fi
    
    local alp_version
    alp_version=$(alp --version 2>&1 | head -1)
    info "alp バージョン: $alp_version"
    return 0
}

# アクセスログ記録開始
start_logging() {
    info "アクセスログ記録を開始します..."
    
    if [[ ! -f "$NGINX_ACCESS_LOG" ]]; then
        error "アクセスログファイルが見つかりません: $NGINX_ACCESS_LOG"
        return 1
    fi
    
    info "アクセスログ: $NGINX_ACCESS_LOG (サイズ: $(du -h "$NGINX_ACCESS_LOG" | cut -f1))"
    
    # 既存ログをバックアップ
    if [[ -s "$NGINX_ACCESS_LOG" ]]; then
        local backup_file="${ALP_LOGS_DIR}/access_$(date '+%Y%m%d_%H%M%S').log"
        info "既存ログをバックアップ: $backup_file"
        sudo cp "$NGINX_ACCESS_LOG" "$backup_file"
        sudo chown "$(whoami):$(whoami)" "$backup_file"
    fi
    
    # ログファイルをリセット
    info "アクセスログをリセットしています..."
    sudo truncate -s 0 "$NGINX_ACCESS_LOG"
    
    # Nginxにリロードシグナル送信
    if sudo systemctl is-active "$NGINX_SERVICE" > /dev/null; then
        nginx_cmd reload
        info "Nginxにreloadシグナルを送信しました"
    else
        warning "Nginxが動作していません"
    fi
    
    success "アクセスログ記録開始完了"
    info "ベンチマークを実行してください"
}

# alp分析実行（JSON専用）
analyze_logs() {
    local limit="${1:-30}"
    local matching="${2:-}"
    
    info "alp分析を実行します..."
    
    if ! check_alp; then
        return 1
    fi
    
    if [[ ! -s "$NGINX_ACCESS_LOG" ]]; then
        warning "アクセスログが空です"
        info "ベンチマークを実行後に再度実行してください"
        return 1
    fi
    
    info "ログ形式: JSON（setup_alp.shで設定済み）"
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local analysis_file="${ANALYSIS_DIR}/alp_analysis_${timestamp}.txt"
    
    info "分析結果を保存: $analysis_file"
    
    # alpコマンドのオプション構築（JSON固定）
    local alp_options=()
    alp_options+=("json")  # サブコマンド
    alp_options+=("--file" "$NGINX_ACCESS_LOG")
    alp_options+=("--limit" "$limit")
    alp_options+=("-r")  # 逆順（大きい順）
    
    # エンドポイントグルーピングパターン（動的IDをまとめる）
    # TODO: ISUCON競技ごとに変更する。
    local patterns=""
    patterns+="/api/initialize,"
    patterns+="/api/app/users,"
    patterns+="/api/app/payment-methods,"
    patterns+="/api/app/rides,"
    patterns+="/api/app/rides/[^/]+\$,"
    patterns+="/api/app/rides/[^/]+/evaluation,"
    patterns+="/api/app/rides/estimated-fare,"
    patterns+="/api/app/notification,"
    patterns+="/api/app/nearby-chairs,"
    patterns+="/api/driver/register,"
    patterns+="/api/driver/chairs/[^/]+/rides,"
    patterns+="/api/driver/chairs/[^/]+/activity,"
    patterns+="/api/chair/chairs,"
    patterns+="/api/chair/activity,"
    patterns+="/api/chair/coordinate,"
    patterns+="/api/chair/notification,"
    patterns+="/api/chair/rides/[^/]+/status,"
    patterns+="/api/owner/owners,"
    patterns+="/api/owner/chairs,"
    patterns+="/api/owner/sales,"
    patterns+="/api/internal/matching"
    
    if [[ -n "$matching" ]]; then
        alp_options+=("-m" "$matching")
    else
        alp_options+=("-m" "$patterns")
    fi
    
    {
        echo "=== alp分析結果 ==="
        echo "分析日時: $(date)"
        echo "対象ファイル: $NGINX_ACCESS_LOG"
        echo "ファイルサイズ: $(du -h "$NGINX_ACCESS_LOG" | cut -f1)"
        echo "総リクエスト数: $(wc -l < "$NGINX_ACCESS_LOG")"
        echo "ログ形式: JSON"
        echo ""
        
        echo "=== レスポンス時間順分析（上位${limit}件） ==="
        alp "${alp_options[@]}" --sort sum
        echo ""
        
        echo "=== リクエスト数順分析（上位${limit}件） ==="
        alp "${alp_options[@]}" --sort count
        echo ""
        
        echo "=== 平均レスポンス時間順分析（上位${limit}件） ==="
        alp "${alp_options[@]}" --sort avg
        echo ""
        
        echo "=== P99レスポンス時間順（上位${limit}件） ==="
        alp "${alp_options[@]}" --sort max --percentiles '50,90,95,99'
        echo ""
        
        echo "=== 詳細統計情報 ==="
        echo "# リクエスト数分布（上位10パス）"
        jq -r '.uri' "$NGINX_ACCESS_LOG" 2>/dev/null | sort | uniq -c | sort -nr | head -10
        echo ""
        
        echo "# ステータスコード分布"
        jq -r '.status' "$NGINX_ACCESS_LOG" 2>/dev/null | sort | uniq -c | sort -nr
        echo ""
        
        echo "# レスポンス時間分布"
        jq -r '.request_time' "$NGINX_ACCESS_LOG" 2>/dev/null | awk '
            {
                time = $1 + 0
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
            }'
    } | tee "$analysis_file"
    
    success "分析完了: $analysis_file"
}

# ヘルプ表示
show_help() {
    cat << EOF
alp分析スクリプト（JSON専用版）

使用方法:
  $(basename "$0") start                    # ログリセット＆記録開始
  $(basename "$0") analyze [limit]          # 分析実行
  $(basename "$0") status                   # 状況確認
  
例:
  $(basename "$0") start                    # ログ記録開始
  # ベンチマーク実行
  $(basename "$0") analyze                  # 分析（上位30件）
  $(basename "$0") analyze 50               # 分析（上位50件）

注意:
  - setup_alp.shでNginxをJSON形式に設定済みが前提
  - 動的IDは自動的にグループ化されます
EOF
}

# ステータス確認
check_status() {
    echo "=== alpステータス確認 ==="
    
    if command -v alp &> /dev/null; then
        echo "alp: インストール済み ($(alp --version 2>&1 | head -1))"
    else
        echo "alp: 未インストール"
    fi
    
    if [[ -f "$NGINX_ACCESS_LOG" ]]; then
        echo "アクセスログ: $NGINX_ACCESS_LOG"
        echo "  サイズ: $(du -h "$NGINX_ACCESS_LOG" | cut -f1)"
        echo "  行数: $(wc -l < "$NGINX_ACCESS_LOG")"
        
        # 最初の1行でJSON形式か確認
        if [[ -s "$NGINX_ACCESS_LOG" ]]; then
            local first_line=$(head -1 "$NGINX_ACCESS_LOG")
            if [[ "$first_line" =~ ^\{.*\}$ ]]; then
                echo "  形式: JSON ✓"
            else
                echo "  形式: JSON以外（要再設定）"
            fi
        fi
    else
        echo "アクセスログ: 見つかりません"
    fi
    
    echo ""
    echo "分析結果ディレクトリ: $ANALYSIS_DIR"
    if [[ -d "$ANALYSIS_DIR" ]]; then
        echo "  保存済み結果数: $(find "$ANALYSIS_DIR" -name "*.txt" 2>/dev/null | wc -l)"
    fi
}

# メイン処理
main() {
    local command="${1:-help}"
    
    info "=== alp分析スクリプト開始 ==="
    info "コマンド: $command"
    
    case "$command" in
        start)
            start_logging
            ;;
        analyze)
            shift
            analyze_logs "$@"
            ;;
        status)
            check_status
            ;;
        help|--help|-h)
            show_help
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