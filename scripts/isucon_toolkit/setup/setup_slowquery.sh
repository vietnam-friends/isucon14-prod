#!/bin/bash

# ISUCON用スロークエリ分析ツール - 初期設定スクリプト
# 使用方法: ./setup_slowquery.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${SCRIPT_DIR}/setup_slowquery.log"

# 共通関数の読み込み
source "${TOOLKIT_ROOT}/common_functions.sh"

CONFIG_BACKUP_FILE="${SCRIPT_DIR}/mysql_original.cnf.backup"

# ヘルプ表示
show_help() {
    cat << EOF
ISUCON用スロークエリ分析ツール - 初期設定スクリプト

使用方法:
  ./setup_slowquery.sh [オプション]

オプション:
  -h, --help       このヘルプを表示
  -c, --check      現在の設定を確認するのみ（変更しない）
  -t, --threshold  スロークエリの閾値（秒）（デフォルト: 0）

例:
  ./setup_slowquery.sh                  # デフォルト設定で実行
  ./setup_slowquery.sh -t 0.1           # 0.1秒以上のクエリをスロークエリとして記録
  ./setup_slowquery.sh --check          # 現在の設定のみ確認

EOF
}

# 削除：共通関数に移動

# 現在の設定確認
check_current_settings() {
    info "現在のMySQL設定を確認しています..."
    
    local config_file
    config_file=$(find_mysql_config)
    
    if [[ $? -eq 0 ]]; then
        info "MySQL設定ファイル: $config_file"
    else
        return 1
    fi

    # MySQL接続確認
    if ! test_mysql_connection; then
        error "MySQLに接続できません。MySQLが起動していることを確認してください。"
        return 1
    fi

    # 現在の設定値を確認
    echo
    echo "=== 現在のスロークエリ設定 ==="
    local mysql_command
    mysql_command=$(mysql_cmd)
    $mysql_command -e "
        SELECT 
            @@slow_query_log as 'slow_query_log',
            @@slow_query_log_file as 'slow_query_log_file',
            @@long_query_time as 'long_query_time',
            @@log_queries_not_using_indexes as 'log_queries_not_using_indexes'
        \G
    "
    echo
}

# MySQL設定のバックアップ
backup_mysql_config() {
    local config_file="$1"
    
    if [[ ! -f "$CONFIG_BACKUP_FILE" ]]; then
        info "MySQL設定をバックアップしています: $CONFIG_BACKUP_FILE"
        sudo cp "$config_file" "$CONFIG_BACKUP_FILE"
        success "バックアップが完了しました"
    else
        warning "バックアップファイルが既に存在します: $CONFIG_BACKUP_FILE"
    fi
}

# スロークエリログの設定
configure_slow_query() {
    local threshold="$1"
    local config_file
    config_file=$(find_mysql_config)
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    info "MySQL設定ファイルを更新しています: $config_file"
    
    # バックアップ作成
    backup_mysql_config "$config_file"
    
    # 既存の設定をコメントアウト
    sudo sed -i.tmp '/^slow_query_log/s/^/#/' "$config_file"
    sudo sed -i.tmp '/^slow_query_log_file/s/^/#/' "$config_file" 
    sudo sed -i.tmp '/^long_query_time/s/^/#/' "$config_file"
    sudo sed -i.tmp '/^log_queries_not_using_indexes/s/^/#/' "$config_file"
    
    # [mysqld]セクションに新しい設定を追加
    local mysqld_section_exists
    mysqld_section_exists=$(sudo grep -c '^\[mysqld\]' "$config_file" || echo 0)
    
    if [[ $mysqld_section_exists -eq 0 ]]; then
        info "[mysqld]セクションを追加します"
        echo -e "\n[mysqld]" | sudo tee -a "$config_file" > /dev/null
    fi

    # スロークエリ設定を追加
    cat << EOF | sudo tee -a "$config_file" > /dev/null

# ISUCON スロークエリ設定 (自動追加)
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = $threshold
log_queries_not_using_indexes = 1

EOF

    success "MySQL設定ファイルの更新が完了しました"
}

# スロークエリログディレクトリとファイルの準備
prepare_log_files() {
    info "スロークエリログファイルの準備をしています..."
    
    # ログディレクトリの作成
    sudo mkdir -p /var/log/mysql
    
    # ログファイルの作成と権限設定
    sudo touch /var/log/mysql/mysql-slow.log
    sudo chown mysql:mysql /var/log/mysql/mysql-slow.log
    sudo chmod 644 /var/log/mysql/mysql-slow.log
    
    success "ログファイルの準備が完了しました"
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

# メイン処理
main() {
    local threshold=0
    local check_only=false
    
    # コマンドライン引数の解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -t|--threshold)
                threshold="$2"
                shift 2
                ;;
            *)
                error "不明なオプション: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    info "=== スロークエリ設定スクリプト開始 ==="
    
    # 現在の設定確認
    if ! check_current_settings; then
        exit 1
    fi
    
    # チェックのみの場合は終了
    if [[ $check_only == true ]]; then
        info "現在の設定確認が完了しました"
        exit 0
    fi
    
    # 設定変更の確認
    echo
    warning "スロークエリログを有効にします（閾値: ${threshold}秒）"
    read -p "続行しますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "処理をキャンセルしました"
        exit 0
    fi
    
    # スロークエリ設定実行
    configure_slow_query "$threshold"
    prepare_log_files
    restart_mysql
    
    # 設定確認
    echo
    success "=== 設定完了後の確認 ==="
    check_current_settings
    
    echo
    success "スロークエリログの設定が完了しました！"
    info "ログファイル: /var/log/mysql/mysql-slow.log"
    info "分析スクリプト: ./slowquery_analysis.sh"
    info "設定無効化: ./disable_slowquery.sh"
}

main "$@"