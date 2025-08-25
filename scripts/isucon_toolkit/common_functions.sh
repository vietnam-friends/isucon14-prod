#!/bin/bash

# ISUCON分析ツールキット共通関数
# 全スクリプトから読み込まれる共通処理

# 設定ファイル読み込み
load_config() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    local config_file="${script_dir}/config.env"
    
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    else
        # デフォルト設定
        DB_NAME="${DB_NAME:-isuride}"
        DB_USER="${DB_USER:-root}"
        DB_PASSWORD="${DB_PASSWORD:-}"
        DB_HOST="${DB_HOST:-localhost}"
        DB_PORT="${DB_PORT:-3306}"
        MYSQL_AUTH_MODE="${MYSQL_AUTH_MODE:-sudo}"
        
        APP_PATH="${APP_PATH:-/home/isucon/webapp}"
        APP_SERVICE="${APP_SERVICE:-isuride-go.service}"
        APP_USER="${APP_USER:-isucon}"
        
        NGINX_CONFIG_PATH="${NGINX_CONFIG_PATH:-/etc/nginx/nginx.conf}"
        NGINX_ACCESS_LOG="${NGINX_ACCESS_LOG:-/var/log/nginx/access.log}"
        NGINX_SERVICE="${NGINX_SERVICE:-nginx}"
        
        PPROF_PORT="${PPROF_PORT:-6060}"
        PPROF_HOST="${PPROF_HOST:-localhost}"
        
        MYSQL_CONFIG_PATHS=(
            "/etc/mysql/mysql.conf.d/mysqld.cnf"
            "/etc/mysql/my.cnf"
            "/etc/my.cnf"
            "/usr/local/etc/my.cnf"
            "$HOME/.my.cnf"
        )
        
        DEFAULT_SLOWQUERY_THRESHOLD="${DEFAULT_SLOWQUERY_THRESHOLD:-0}"
        DEFAULT_ALP_LIMIT="${DEFAULT_ALP_LIMIT:-20}"
        DEFAULT_PPROF_DURATION="${DEFAULT_PPROF_DURATION:-30s}"
    fi
}

# MySQL接続コマンド生成
mysql_cmd() {
    case "$MYSQL_AUTH_MODE" in
        sudo)
            echo "sudo mysql ${DB_NAME}"
            ;;
        auth)
            local pwd_opt=""
            if [[ -n "$DB_PASSWORD" ]]; then
                pwd_opt="-p${DB_PASSWORD}"
            fi
            echo "mysql -u${DB_USER} ${pwd_opt} -h${DB_HOST} -P${DB_PORT} ${DB_NAME}"
            ;;
        *)
            echo "sudo mysql ${DB_NAME}"
            ;;
    esac
}

# MySQL接続テスト
test_mysql_connection() {
    local mysql_command
    mysql_command=$(mysql_cmd)
    
    if $mysql_command -e "SELECT 1;" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# MySQL設定ファイル検索
find_mysql_config() {
    for config_file in "${MYSQL_CONFIG_PATHS[@]}"; do
        if [[ -f "$config_file" ]]; then
            echo "$config_file"
            return 0
        fi
    done
    return 1
}

# アプリケーションサービス制御
app_service_cmd() {
    local action="$1"
    sudo systemctl "$action" "$APP_SERVICE"
}

# Nginx制御
nginx_cmd() {
    local action="$1"
    sudo systemctl "$action" "$NGINX_SERVICE"
}

# Nginx設定テスト
nginx_test() {
    sudo nginx -t
}

# ログ出力（カラー対応）
setup_logging() {
    if [[ "${ENABLE_COLOR_OUTPUT:-true}" == "true" ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        MAGENTA='\033[0;35m'
        NC='\033[0m'
    else
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        CYAN=''
        MAGENTA=''
        NC=''
    fi
}

# 共通ログ関数
log_base() {
    local level="$1"
    local color="$2"
    local message="$3"
    local log_file="${4:-}"
    
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local formatted_message="${timestamp} [${level}] ${message}"
    
    echo -e "${color}${formatted_message}${NC}"
    
    if [[ -n "$log_file" ]]; then
        echo "$formatted_message" >> "$log_file"
    fi
}

error() {
    log_base "ERROR" "$RED" "$1" "${LOG_FILE:-}"
}

success() {
    log_base "SUCCESS" "$GREEN" "$1" "${LOG_FILE:-}"
}

warning() {
    log_base "WARNING" "$YELLOW" "$1" "${LOG_FILE:-}"
}

info() {
    log_base "INFO" "$BLUE" "$1" "${LOG_FILE:-}"
}

debug() {
    if [[ "${LOG_LEVEL:-info}" == "debug" ]]; then
        log_base "DEBUG" "$MAGENTA" "$1" "${LOG_FILE:-}"
    fi
}

header() {
    log_base "===" "$CYAN" "$1" "${LOG_FILE:-}"
}

step() {
    log_base "STEP" "$MAGENTA" "$1" "${LOG_FILE:-}"
}

# 設定情報の表示
show_config() {
    echo "=== 現在の設定 ==="
    echo "データベース名: $DB_NAME"
    echo "MySQLホスト: $DB_HOST:$DB_PORT"
    echo "MySQL認証方式: $MYSQL_AUTH_MODE"
    echo "アプリケーションパス: $APP_PATH"
    echo "アプリケーションサービス: $APP_SERVICE"
    echo "Nginxアクセスログ: $NGINX_ACCESS_LOG"
    echo "pprofエンドポイント: http://$PPROF_HOST:$PPROF_PORT"
    echo "======================="
}

# 初期化（このファイルをsourceした際に実行）
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    load_config
    setup_logging
fi