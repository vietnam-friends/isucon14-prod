#!/bin/bash

# ISUCON用alp分析ツール - セットアップスクリプト
# 使用方法: ./setup_alp.sh

set -euo pipefail

# 共通関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/common_functions.sh"

LOG_FILE="${SCRIPT_DIR}/setup_alp.log"
ALP_VERSION="v1.0.21"  # 最新版に更新可能
NGINX_CONF_BACKUP="${SCRIPT_DIR}/nginx_original.conf.backup"

# ヘルプ表示
show_help() {
    cat << EOF
ISUCON用alp分析ツール - セットアップスクリプト

使用方法:
  ./setup_alp.sh [オプション]

オプション:
  -h, --help         このヘルプを表示
  -c, --check        現在の設定を確認するのみ（変更しない）
  -f, --format TYPE  ログ形式を指定 (json|ltsv|combined) (デフォルト: json)
  -y, --yes          確認をスキップして自動実行
  --skip-install     alpのインストールをスキップ
  --version VERSION  alpのバージョンを指定（デフォルト: v1.0.21）

例:
  ./setup_alp.sh                    # デフォルト設定で実行
  ./setup_alp.sh --format ltsv      # LTSV形式でログを設定
  ./setup_alp.sh --check            # 現在の設定のみ確認
  ./setup_alp.sh --skip-install     # alpインストールをスキップ

EOF
}

# システム情報の確認
check_system() {
    info "システム情報を確認しています..."
    
    # OS確認
    if [[ -f /etc/os-release ]]; then
        local os_info
        os_info=$(grep '^NAME=' /etc/os-release | cut -d'"' -f2)
        info "OS: $os_info"
    fi
    
    # アーキテクチャ確認
    local arch
    arch=$(uname -m)
    info "アーキテクチャ: $arch"
    
    # 必要なコマンドの確認
    local required_commands=("curl" "tar" "sudo")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "必要なコマンドが見つかりません: $cmd"
            return 1
        fi
    done
    
    return 0
}

# alpのインストール
install_alp() {
    local version="$1"
    
    if command -v alp &> /dev/null; then
        local current_version
        current_version=$(alp --version 2>&1 | grep -o 'v[0-9.]*' | head -1 || echo "unknown")
        info "alp は既にインストールされています: $current_version"
        
        if [[ "$current_version" == "$version" ]]; then
            success "指定されたバージョンと一致しています"
            return 0
        else
            warning "バージョンが異なります。更新しますか？"
            read -p "更新しますか？ (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "更新をスキップしました"
                return 0
            fi
        fi
    fi
    
    info "alpをインストールしています (バージョン: $version)..."
    
    # アーキテクチャの判定
    local arch
    arch=$(uname -m)
    local alp_arch
    case "$arch" in
        x86_64) alp_arch="amd64" ;;
        aarch64|arm64) alp_arch="arm64" ;;
        armv7l) alp_arch="armv7" ;;
        *) 
            error "サポートされていないアーキテクチャ: $arch"
            return 1
            ;;
    esac
    
    # OSの判定
    local alp_os="linux"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        alp_os="darwin"
    fi
    
    local download_url="https://github.com/tkuchiki/alp/releases/download/${version}/alp_${alp_os}_${alp_arch}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    info "ダウンロード中: $download_url"
    
    # ダウンロードと展開
    if curl -L -o "${temp_dir}/alp.tar.gz" "$download_url"; then
        cd "$temp_dir"
        tar -xzf alp.tar.gz
        
        # インストール
        sudo mv alp /usr/local/bin/alp
        sudo chmod +x /usr/local/bin/alp
        
        # クリーンアップ
        cd "$SCRIPT_DIR"
        rm -rf "$temp_dir"
        
        success "alpのインストールが完了しました"
        alp --version
    else
        error "alpのダウンロードに失敗しました"
        rm -rf "$temp_dir"
        return 1
    fi
    
    return 0
}

# 現在の設定確認
check_current_settings() {
    info "現在のNginx設定を確認しています..."
    
    local config_file="$NGINX_CONFIG_PATH"
    
    if [[ -f "$config_file" ]]; then
        info "Nginx設定ファイル: $config_file"
    else
        error "Nginx設定ファイルが見つかりません: $config_file"
        return 1
    fi

    # Nginx動作確認
    if ! nginx_test; then
        error "Nginx設定にエラーがあります"
        nginx_test
        return 1
    fi
    
    # 現在のログ設定を確認
    echo
    echo "=== 現在のアクセスログ設定 ==="
    grep -n "access_log\|log_format" "$config_file" || info "アクセスログ設定が見つかりません"
    echo
    
    # アクセスログファイルの確認
    local access_log_files
    access_log_files=$(grep "access_log" "$config_file" | awk '{print $2}' | tr -d ';' || echo "")
    
    if [[ -n "$access_log_files" ]]; then
        echo "=== 現在のアクセスログファイル ==="
        for log_file in $access_log_files; do
            if [[ -f "$log_file" ]]; then
                info "ファイル: $log_file (サイズ: $(du -h "$log_file" | cut -f1))"
            else
                warning "ファイル: $log_file (見つかりません)"
            fi
        done
        echo
    else
        info "デフォルトアクセスログ: ${NGINX_ACCESS_LOG}"
        if [[ -f "$NGINX_ACCESS_LOG" ]]; then
            info "ファイルサイズ: $(du -h "$NGINX_ACCESS_LOG" | cut -f1)"
        fi
    fi
    
    return 0
}

# Nginx設定のバックアップ
backup_nginx_config() {
    local config_file="$1"
    
    if [[ ! -f "$NGINX_CONF_BACKUP" ]]; then
        info "Nginx設定をバックアップしています: $NGINX_CONF_BACKUP"
        sudo cp "$config_file" "$NGINX_CONF_BACKUP"
        sudo chown "$(whoami):$(whoami)" "$NGINX_CONF_BACKUP"
        success "バックアップが完了しました"
    else
        warning "バックアップファイルが既に存在します: $NGINX_CONF_BACKUP"
    fi
}

# JSON形式のログ設定を追加
configure_json_logging() {
    local config_file="$NGINX_CONFIG_PATH"

    info "Nginx設定ファイルを更新しています: $config_file"
    
    # バックアップ作成
    backup_nginx_config "$config_file"
    
    # 一時ファイルに新しい設定を作成
    local temp_config
    temp_config=$(mktemp)
    
    # JSON形式のログ設定を追加
    cat << 'EOF' > "$temp_config"

    # ISUCON alp用ログ形式設定
    log_format alp_json escape=json '{'
        '"time":"$time_iso8601",'
        '"host":"$remote_addr",'
        '"forwardedfor":"$http_x_forwarded_for",'
        '"req":"$request",'
        '"status":"$status",'
        '"method":"$request_method",'
        '"uri":"$request_uri",'
        '"body_bytes":$body_bytes_sent,'
        '"referer":"$http_referer",'
        '"ua":"$http_user_agent",'
        '"request_time":$request_time,'
        '"upstream_time":"$upstream_response_time",'
        '"cache":"$upstream_http_x_cache"'
    '}';

EOF

    # httpブロック内に設定を挿入
    if sudo awk "
        BEGIN { inserted = 0 }
        /^http {/ { 
            print \$0
            if (!inserted) {
                system(\"cat '$temp_config'\")
                inserted = 1
            }
            next 
        }
        { print }
    " "$config_file" > "${temp_config}.new"; then
        sudo mv "${temp_config}.new" "$config_file"
        success "JSON形式のログ設定を追加しました"
    else
        error "設定の更新に失敗しました"
        rm -f "$temp_config" "${temp_config}.new"
        return 1
    fi
    
    rm -f "$temp_config"
    
    # アクセスログの設定を更新
    info "アクセスログをJSON形式に変更しています..."
    
    # 既存のaccess_log設定をコメントアウト
    sudo sed -i.tmp "/access_log.*$(echo "$NGINX_ACCESS_LOG" | sed 's/\//\\\//g')/s/^[[:space:]]*/    # /" "$config_file"
    
    # 新しいaccess_log設定をlog_format定義後に追加
    sudo sed -i.tmp "/^    '}/a\\
\\
    # ISUCON JSON形式アクセスログ\\
    access_log $NGINX_ACCESS_LOG alp_json;" "$config_file"
    
    success "アクセスログの設定を更新しました"
    
    return 0
}

# LTSV形式のログ設定を追加
configure_ltsv_logging() {
    local config_file="$NGINX_CONFIG_PATH"

    info "LTSV形式のログ設定を追加しています..."
    
    backup_nginx_config "$config_file"
    
    local temp_config
    temp_config=$(mktemp)
    
    cat << 'EOF' > "$temp_config"

    # ISUCON alp用ログ形式設定 (LTSV)
    log_format alp_ltsv "time:$time_iso8601"
        "\thost:$remote_addr"
        "\tforwardedfor:$http_x_forwarded_for"
        "\treq:$request"
        "\tstatus:$status"
        "\tmethod:$request_method"
        "\turi:$request_uri"
        "\tsize:$body_bytes_sent"
        "\treferer:$http_referer"
        "\tua:$http_user_agent"
        "\treqtime:$request_time"
        "\tupstreamtime:$upstream_response_time"
        "\tcache:$upstream_http_x_cache";

EOF

    # httpブロック内に設定を挿入
    if sudo awk "
        BEGIN { inserted = 0 }
        /^http {/ { 
            print \$0
            if (!inserted) {
                system(\"cat '$temp_config'\")
                inserted = 1
            }
            next 
        }
        { print }
    " "$config_file" > "${temp_config}.new"; then
        sudo mv "${temp_config}.new" "$config_file"
        success "LTSV形式のログ設定を追加しました"
    else
        error "設定の更新に失敗しました"
        rm -f "$temp_config" "${temp_config}.new"
        return 1
    fi
    
    rm -f "$temp_config"
    
    # アクセスログの設定を更新
    sudo sed -i.tmp "/access_log.*$(echo "$NGINX_ACCESS_LOG" | sed 's/\//\\\//g')/s/^[[:space:]]*/    # /" "$config_file"
    sudo sed -i.tmp '/# ISUCON alp用ログ形式設定/a\
\
    # ISUCON LTSV形式アクセスログ\
    access_log '"$NGINX_ACCESS_LOG"' alp_ltsv;' "$config_file"
    
    success "アクセスログをLTSV形式に設定しました"
    
    return 0
}

# ログディレクトリとファイルの準備
prepare_log_files() {
    info "ログファイルの準備をしています..."
    
    # ログディレクトリの作成
    sudo mkdir -p /var/log/nginx
    
    # 権限設定
    sudo chown -R www-data:www-data /var/log/nginx 2>/dev/null || sudo chown -R nginx:nginx /var/log/nginx 2>/dev/null || true
    
    success "ログファイルの準備が完了しました"
}

# Nginx再起動
restart_nginx() {
    info "Nginx設定をテストしています..."
    
    if ! nginx_test; then
        error "Nginx設定にエラーがあります"
        return 1
    fi
    
    info "Nginxを再起動しています..."
    
    if nginx_cmd restart; then
        success "Nginxの再起動が完了しました"
    else
        error "Nginxの再起動に失敗しました"
        return 1
    fi
    
    # 起動確認
    sleep 2
    if sudo systemctl is-active "$NGINX_SERVICE" > /dev/null; then
        success "Nginx起動確認完了"
    else
        error "Nginxが起動していません"
        return 1
    fi
}

# メイン処理
main() {
    local log_format="json"
    local check_only=false
    local skip_install=false
    local alp_version="$ALP_VERSION"
    local auto_yes=false
    
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
            -f|--format)
                log_format="$2"
                shift 2
                ;;
            --skip-install)
                skip_install=true
                shift
                ;;
            --version)
                alp_version="$2"
                shift 2
                ;;
            -y|--yes)
                auto_yes=true
                shift
                ;;
            *)
                error "不明なオプション: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    info "=== alp設定スクリプト開始 ==="
    
    # システム確認
    if ! check_system; then
        exit 1
    fi
    
    # 現在の設定確認
    if ! check_current_settings; then
        exit 1
    fi
    
    # チェックのみの場合は終了
    if [[ $check_only == true ]]; then
        info "現在の設定確認が完了しました"
        exit 0
    fi
    
    # alpのインストール
    if [[ $skip_install != true ]]; then
        if ! install_alp "$alp_version"; then
            warning "alpのインストールに失敗しましたが、続行します"
        fi
    fi
    
    # 設定変更の確認
    if [[ $auto_yes != true ]]; then
        echo
        warning "Nginxの設定を変更します（ログ形式: ${log_format}）"
        read -p "続行しますか？ (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "処理をキャンセルしました"
            exit 0
        fi
    else
        info "自動実行モードで設定変更を続行します（ログ形式: ${log_format}）"
    fi
    
    # ログ設定実行
    case "$log_format" in
        json)
            configure_json_logging
            ;;
        ltsv)
            configure_ltsv_logging
            ;;
        combined)
            info "Combined形式はデフォルトのため、設定変更をスキップします"
            ;;
        *)
            error "サポートされていないログ形式: $log_format"
            exit 1
            ;;
    esac
    
    prepare_log_files
    restart_nginx
    
    # 設定確認
    echo
    success "=== 設定完了後の確認 ==="
    check_current_settings
    
    echo
    success "alp分析環境の設定が完了しました！"
    info "ログ形式: $log_format"
    info "分析スクリプト: ./alp_analysis.sh"
    info "alpコマンド: $(which alp || echo 'インストールされていません')"
}

main "$@"