#!/bin/bash

# ISUCON用pprof分析ツール - セットアップスクリプト
# 使用方法: ./setup_pprof.sh

set -euo pipefail

# 共通関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${TOOLKIT_ROOT}/common_functions.sh"

LOG_FILE="${SCRIPT_DIR}/setup_pprof.log"

# ヘルプ表示
show_help() {
    cat << EOF
ISUCON用pprof分析ツール - セットアップスクリプト

使用方法:
  ./setup_pprof.sh [オプション]

オプション:
  -h, --help         このヘルプを表示
  -c, --check        現在の設定を確認するのみ（変更しない）
  -p, --port PORT    pprofサーバーのポート番号（デフォルト: 6060）
  -d, --dir DIR      Goプロジェクトのルートディレクトリを指定
  --dry-run          実際の変更を行わずに、変更内容のみ表示

例:
  ./setup_pprof.sh                    # カレントディレクトリで自動検出
  ./setup_pprof.sh -d /path/to/go     # 指定ディレクトリで実行
  ./setup_pprof.sh -p 6061            # ポート6061を使用
  ./setup_pprof.sh --check            # 現在の設定確認のみ

EOF
}

# Goプロジェクトの検出
find_go_projects() {
    local search_dir="${1:-$(pwd)}"
    
    info "Goプロジェクトを検索しています: $search_dir" >&2
    
    # main.goファイルを探す
    local main_files
    main_files=$(find "$search_dir" -name "main.go" -type f 2>/dev/null || echo "")
    
    if [[ -z "$main_files" ]]; then
        # go.modファイルがあるディレクトリを探す
        local mod_dirs
        mod_dirs=$(find "$search_dir" -name "go.mod" -type f -exec dirname {} \; 2>/dev/null || echo "")
        
        if [[ -n "$mod_dirs" ]]; then
            info "go.modファイルが見つかりました:" >&2
            echo "$mod_dirs" | while read -r mod_dir; do
                info "  $mod_dir" >&2
                # そのディレクトリ内でmain.goを探す
                find "$mod_dir" -name "main.go" -type f 2>/dev/null | head -5
            done
        fi
    else
        echo "$main_files"
    fi
}

# main.goファイルの解析
analyze_main_go() {
    local main_file="$1"
    
    info "main.goファイルを解析しています: $main_file"
    
    # パッケージ名確認
    local package_name
    package_name=$(grep -E '^package ' "$main_file" | awk '{print $2}' || echo "")
    
    if [[ "$package_name" != "main" ]]; then
        warning "$main_file はmainパッケージではありません (package $package_name)"
        return 1
    fi
    
    # main関数の存在確認
    if ! grep -q "func main()" "$main_file"; then
        warning "$main_file にmain関数が見つかりません"
        return 1
    fi
    
    # 既存のpprof importの確認
    local has_pprof_import=false
    local has_http_import=false
    
    if grep -q "net/http/pprof" "$main_file"; then
        has_pprof_import=true
        info "pprofのimportが既に存在します"
    fi
    
    if grep -q "net/http" "$main_file" || grep -q "http\." "$main_file"; then
        has_http_import=true
        info "httpパッケージのimportが既に存在します"
    fi
    
    # HTTPサーバーの起動処理の確認
    local has_http_server=false
    if grep -q "http.ListenAndServe\|http.Server\|ListenAndServe\|gin.Run\|echo.Start\|fiber.Listen" "$main_file"; then
        has_http_server=true
        info "HTTPサーバーの起動処理が見つかりました"
    fi
    
    echo "pprof_import:$has_pprof_import,http_import:$has_http_import,http_server:$has_http_server"
    return 0
}

# pprofの設定を追加
add_pprof_to_main() {
    local main_file="$1"
    local port="$2"
    local dry_run="${3:-false}"
    
    info "pprofの設定を追加します: $main_file (ポート: $port)"
    
    # バックアップを作成
    local backup_file="${main_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ "$dry_run" != true ]]; then
        cp "$main_file" "$backup_file"
        info "バックアップを作成: $backup_file"
    fi
    
    # 解析結果を取得
    local analysis_result
    analysis_result=$(analyze_main_go "$main_file")
    
    local has_pprof_import=$(echo "$analysis_result" | grep -o 'pprof_import:[^,]*' | cut -d: -f2)
    local has_http_import=$(echo "$analysis_result" | grep -o 'http_import:[^,]*' | cut -d: -f2)
    
    # 一時ファイルに新しい内容を作成
    local temp_file
    temp_file=$(mktemp)
    
    # ファイルを行ごとに処理
    local in_import_block=false
    local import_added=false
    local pprof_server_added=false
    
    while IFS= read -r line; do
        # import文の処理
        if [[ "$line" =~ ^import ]]; then
            echo "$line" >> "$temp_file"
            if [[ "$line" == *"(" ]]; then
                in_import_block=true
            elif [[ "$has_pprof_import" != "true" && "$has_http_import" != "true" && "$line" != *"(" ]]; then
                # single line import の場合
                echo -e "\nimport (" >> "$temp_file"
                echo -e '\t_ "net/http/pprof"' >> "$temp_file"
                echo -e '\t"log"' >> "$temp_file"
                echo -e '\t"net/http"' >> "$temp_file"
                echo ")" >> "$temp_file"
                import_added=true
            fi
            continue
        fi
        
        # import block内の処理
        if [[ "$in_import_block" == true ]]; then
            if [[ "$line" == *")" ]]; then
                # import block終了前にpprofを追加
                if [[ "$has_pprof_import" != "true" && "$import_added" != true ]]; then
                    echo -e '\t_ "net/http/pprof"' >> "$temp_file"
                    if [[ "$has_http_import" != "true" ]]; then
                        echo -e '\t"net/http"' >> "$temp_file"
                    fi
                    echo -e '\t"log"' >> "$temp_file"
                    import_added=true
                fi
                in_import_block=false
            fi
            echo "$line" >> "$temp_file"
            continue
        fi
        
        # main関数内でpprofサーバーを追加
        if [[ "$line" =~ ^func\ main\(\) ]] && [[ "$pprof_server_added" != true ]]; then
            echo "$line" >> "$temp_file"
            echo "" >> "$temp_file"
            echo -e '\t// ISUCON pprof server' >> "$temp_file"
            echo -e '\tgo func() {' >> "$temp_file"
            echo -e '\t\tlog.Println("Starting pprof server on :'"$port"'")' >> "$temp_file"
            echo -e '\t\tlog.Println(http.ListenAndServe(":'"$port"'", nil))' >> "$temp_file"
            echo -e '\t}()' >> "$temp_file"
            echo "" >> "$temp_file"
            pprof_server_added=true
            continue
        fi
        
        echo "$line" >> "$temp_file"
        
    done < "$main_file"
    
    # 変更内容の確認
    if [[ "$dry_run" == true ]]; then
        info "=== 変更内容（dry-run） ==="
        diff -u "$main_file" "$temp_file" || true
        info "=== 変更内容終了 ==="
        rm -f "$temp_file"
        return 0
    fi
    
    # ファイルを更新
    mv "$temp_file" "$main_file"
    
    success "pprofの設定を追加しました"
    info "バックアップファイル: $backup_file"
    
    return 0
}

# graphvizの確認とインストール
install_graphviz() {
    if command -v dot &> /dev/null; then
        success "graphviz は既にインストールされています"
        return 0
    fi
    
    info "graphviz をインストールしています（pprof のグラフ機能に必要）..."
    if sudo apt install -y graphviz; then
        success "graphviz のインストールが完了しました"
    else
        error "graphviz のインストールに失敗しました"
        info "手動でインストールしてください: sudo apt install -y graphviz"
        return 1
    fi
}

# 現在の設定確認
check_current_settings() {
    local project_dir="${1:-$(pwd)}"
    
    info "現在のpprof設定を確認しています: $project_dir"
    
    # Goのバージョン確認
    if command -v go &> /dev/null; then
        local go_version
        go_version=$(go version)
        info "Go バージョン: $go_version"
    else
        error "Goが見つかりません"
        return 1
    fi
    
    # graphvizの確認
    echo
    echo "=== システム依存関係の確認 ==="
    if command -v dot &> /dev/null; then
        success "graphviz: 利用可能"
    else
        warning "graphviz が見つかりません（pprof のグラフ機能に必要）"
    fi
    
    # main.goファイルの検出
    local main_files
    main_files=$(find_go_projects "$project_dir")
    
    if [[ -z "$main_files" ]]; then
        warning "main.goファイルが見つかりません"
        return 1
    fi
    
    info "検出されたmain.goファイル:"
    echo "$main_files" | while read -r main_file; do
        if [[ -n "$main_file" ]]; then
            info "  $main_file"
            
            # pprofの設定確認
            if grep -q "net/http/pprof" "$main_file"; then
                success "  ✓ pprofが設定済み"
            else
                warning "  × pprofが未設定"
            fi
            
            # HTTPサーバー確認
            if grep -q "ListenAndServe.*:$PPROF_PORT" "$main_file"; then
                success "  ✓ pprofサーバー設定済み (ポート: $PPROF_PORT)"
            else
                warning "  × pprofサーバー未設定"
            fi
        fi
    done
    
    echo
    return 0
}

# 自動設定の実行
auto_setup_pprof() {
    local project_dir="${1:-$(pwd)}"
    local port="$2"
    local dry_run="${3:-false}"
    
    info "pprof自動設定を実行します..."
    
    local main_files
    main_files=$(find_go_projects "$project_dir")
    
    if [[ -z "$main_files" ]]; then
        error "main.goファイルが見つかりません"
        return 1
    fi
    
    local setup_count=0
    
    echo "$main_files" | while read -r main_file; do
        if [[ -n "$main_file" && -f "$main_file" ]]; then
            info "処理中: $main_file"
            
            # 既にpprofが設定済みかチェック
            if grep -q "net/http/pprof" "$main_file" && grep -q "ListenAndServe.*:$port" "$main_file"; then
                info "  既にpprof設定済み、スキップします"
                continue
            fi
            
            # pprofを追加
            if add_pprof_to_main "$main_file" "$port" "$dry_run"; then
                setup_count=$((setup_count + 1))
                success "  pprofの設定を追加しました"
            else
                error "  pprofの設定追加に失敗しました"
            fi
        fi
    done
    
    if [[ $setup_count -gt 0 ]]; then
        success "pprofの設定が完了しました (${setup_count}ファイル)"
        echo
        info "次の手順:"
        info "1. アプリケーションをビルド: go build"
        info "2. アプリケーションを起動"
        info "3. pprofサーバーが起動: http://${PPROF_HOST}:${port}/debug/pprof/"
        info "4. 分析スクリプト実行: ./pprof_analysis.sh"
    else
        warning "設定を追加したファイルがありません"
    fi
    
    return 0
}

# メイン処理
main() {
    local project_dir=""
    local port="$PPROF_PORT"
    local check_only=false
    local dry_run=false
    
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
            -p|--port)
                port="$2"
                shift 2
                ;;
            -d|--dir)
                project_dir="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                error "不明なオプション: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # プロジェクトディレクトリの設定
    if [[ -z "$project_dir" ]]; then
        # ISUCON環境のデフォルトパスを優先
        if [[ -d "$APP_PATH" ]]; then
            project_dir="$APP_PATH"
        else
            project_dir=$(pwd)
        fi
    fi
    
    if [[ ! -d "$project_dir" ]]; then
        error "指定されたディレクトリが見つかりません: $project_dir"
        exit 1
    fi
    
    info "=== pprof設定スクリプト開始 ==="
    
    # graphvizのインストール
    if ! install_graphviz; then
        warning "graphviz のインストールに失敗しましたが、続行します"
    fi
    
    # 現在の設定確認
    if ! check_current_settings "$project_dir"; then
        exit 1
    fi
    
    # チェックのみの場合は終了
    if [[ $check_only == true ]]; then
        info "現在の設定確認が完了しました"
        exit 0
    fi
    
    # 設定変更の確認
    echo
    if [[ $dry_run == true ]]; then
        info "Dry-run モードで実行します（実際の変更は行いません）"
    else
        warning "Goアプリケーションにpprofの設定を追加します（ポート: ${port}）"
        read -p "続行しますか？ (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "処理をキャンセルしました"
            exit 0
        fi
    fi
    
    # 自動設定実行
    auto_setup_pprof "$project_dir" "$port" "$dry_run"
    
    echo
    if [[ $dry_run != true ]]; then
        success "pprofの設定が完了しました！"
        info "ポート: $port"
        info "分析スクリプト: ./pprof_analysis.sh"
    else
        info "Dry-runが完了しました"
    fi
}

main "$@"