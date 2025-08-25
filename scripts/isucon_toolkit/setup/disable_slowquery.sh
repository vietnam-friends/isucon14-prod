#!/bin/bash

# ISUCON用スロークエリ分析ツール - 終了時スクリプト
# 使用方法: ./disable_slowquery.sh

set -euo pipefail

# 共通関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/common_functions.sh"

LOG_FILE="${SCRIPT_DIR}/disable_slowquery.log"
CONFIG_BACKUP_FILE="${SCRIPT_DIR}/mysql_original.cnf.backup"

# ヘルプ表示
show_help() {
    cat << EOF
ISUCON用スロークエリ分析ツール - 終了時スクリプト

使用方法:
  ./disable_slowquery.sh [オプション]

オプション:
  -h, --help       このヘルプを表示
  -k, --keep-logs  ログファイルを削除せずに保持
  -r, --restore    オリジナルの設定ファイルに完全復元

例:
  ./disable_slowquery.sh              # スロークエリログを無効化
  ./disable_slowquery.sh --keep-logs  # ログファイルを保持したまま無効化
  ./disable_slowquery.sh --restore    # バックアップから完全復元

EOF
}

# 現在の設定確認
check_current_settings() {
    info "現在のMySQL設定を確認しています..."
    
    # MySQL接続確認
    if ! test_mysql_connection; then
        error "MySQLに接続できません。MySQLが起動していることを確認してください。"
        return 1
    fi

    # 現在の設定値を確認
    echo
    echo "=== 現在のスロークエリ設定 ==="
    $(mysql_cmd) -e "
        SELECT 
            @@slow_query_log as 'slow_query_log',
            @@slow_query_log_file as 'slow_query_log_file',
            @@long_query_time as 'long_query_time',
            @@log_queries_not_using_indexes as 'log_queries_not_using_indexes'
        \G
    "
    echo
}

# オリジナル設定の復元
restore_original_config() {
    local config_file
    config_file=$(find_mysql_config)
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    if [[ ! -f "$CONFIG_BACKUP_FILE" ]]; then
        error "バックアップファイルが見つかりません: $CONFIG_BACKUP_FILE"
        error "setup_slowquery.shを実行していないか、バックアップが作成されていません"
        return 1
    fi
    
    info "オリジナル設定を復元しています..."
    info "バックアップ: $CONFIG_BACKUP_FILE → $config_file"
    
    # 現在の設定をバックアップ
    local current_backup="${config_file}.before_restore.$(date +%Y%m%d_%H%M%S)"
    sudo cp "$config_file" "$current_backup"
    info "現在の設定もバックアップしました: $current_backup"
    
    # オリジナル設定を復元
    sudo cp "$CONFIG_BACKUP_FILE" "$config_file"
    
    success "オリジナル設定の復元が完了しました"
    return 0
}

# スロークエリ設定の無効化（設定値のみ変更）
disable_slow_query() {
    local config_file
    config_file=$(find_mysql_config)
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    info "スロークエリログを無効化しています..."
    
    # 現在の設定をバックアップ
    local backup_file="${config_file}.before_disable.$(date +%Y%m%d_%H%M%S)"
    sudo cp "$config_file" "$backup_file"
    info "現在の設定をバックアップ: $backup_file"
    
    # ISUCON設定をコメントアウト
    sudo sed -i.tmp '/# ISUCON スロークエリ設定/,/^$/s/^[^#]/#&/' "$config_file"
    
    # 代替として、より軽量な設定を追加
    cat << EOF | sudo tee -a "$config_file" > /dev/null

# ISUCON スロークエリ設定 (無効化版)
slow_query_log = 0
long_query_time = 10.0
log_queries_not_using_indexes = 0

EOF

    success "スロークエリログの無効化が完了しました"
    return 0
}

# スロークエリログファイルの処理
handle_log_files() {
    local keep_logs="$1"
    
    if [[ "$keep_logs" == true ]]; then
        info "ログファイルは保持されます"
        return 0
    fi
    
    warning "スロークエリログファイルを削除しますか？"
    echo "対象ファイル: /var/log/mysql/mysql-slow.log"
    read -p "削除しますか？ (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -f /var/log/mysql/mysql-slow.log ]]; then
            # 削除前にバックアップ
            local backup_name="mysql-slow_final_$(date +%Y%m%d_%H%M%S).log"
            local backup_path="${SCRIPT_DIR}/slowquery_logs/$backup_name"
            
            mkdir -p "${SCRIPT_DIR}/slowquery_logs"
            sudo cp /var/log/mysql/mysql-slow.log "$backup_path" 2>/dev/null || true
            sudo chown "$(whoami):$(whoami)" "$backup_path" 2>/dev/null || true
            
            if [[ -f "$backup_path" ]]; then
                info "最終ログをバックアップ: $backup_path"
            fi
            
            # ログファイルを削除
            sudo rm -f /var/log/mysql/mysql-slow.log
            success "スロークエリログファイルを削除しました"
        else
            info "スロークエリログファイルが見つかりません"
        fi
    else
        info "ログファイルは保持されます"
    fi
}

# MySQL再起動
restart_mysql() {
    info "MySQLを再起動しています..."
    
    if sudo systemctl restart mysql; then
        success "MySQLの再起動が完了しました"
    else
        error "MySQLの再起動に失敗しました"
        return 1
    fi
    
    # 起動確認
    sleep 3
    if ! test_mysql_connection; then
        error "MySQL再起動後の接続に失敗しました"
        return 1
    fi
    
    success "MySQL接続確認完了"
}

# 後処理とクリーンアップ
cleanup() {
    info "クリーンアップを実行しています..."
    
    # 一時ファイルの削除
    sudo find /etc/mysql/ -name "*.tmp" -delete 2>/dev/null || true
    
    # 分析結果のサマリー表示
    local analysis_dir="${SCRIPT_DIR}/slowquery_analysis"
    if [[ -d "$analysis_dir" ]]; then
        local analysis_count
        analysis_count=$(find "$analysis_dir" -name "analysis_*.txt" | wc -l)
        if [[ $analysis_count -gt 0 ]]; then
            info "分析結果ファイル: ${analysis_count}件保存されています"
            info "場所: $analysis_dir"
        fi
    fi
    
    success "クリーンアップが完了しました"
}

# メイン処理
main() {
    local keep_logs=false
    local restore_original=false
    
    # コマンドライン引数の解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -k|--keep-logs)
                keep_logs=true
                shift
                ;;
            -r|--restore)
                restore_original=true
                shift
                ;;
            *)
                error "不明なオプション: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    info "=== スロークエリ無効化スクリプト開始 ==="
    
    # 現在の設定確認
    if ! check_current_settings; then
        exit 1
    fi
    
    # 処理確認
    echo
    if [[ "$restore_original" == true ]]; then
        warning "オリジナル設定への完全復元を行います"
    else
        warning "スロークエリログを無効化します"
    fi
    
    read -p "続行しますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "処理をキャンセルしました"
        exit 0
    fi
    
    # 設定変更実行
    if [[ "$restore_original" == true ]]; then
        if ! restore_original_config; then
            exit 1
        fi
    else
        if ! disable_slow_query; then
            exit 1
        fi
    fi
    
    # ログファイル処理
    handle_log_files "$keep_logs"
    
    # MySQL再起動
    restart_mysql
    
    # 設定確認
    echo
    success "=== 設定変更後の確認 ==="
    check_current_settings
    
    # クリーンアップ
    cleanup
    
    echo
    success "スロークエリログの無効化が完了しました！"
    
    if [[ "$restore_original" == true ]]; then
        info "オリジナル設定に復元されました"
    else
        info "スロークエリログが無効化されました"
    fi
    
    info "MySQLのパフォーマンスが向上するはずです"
}

main "$@"