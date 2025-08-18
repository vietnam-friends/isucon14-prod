#!/bin/bash

# ISUCON14 GitHub MCP セットアップスクリプト

set -e

echo "======================================"
echo "ISUCON14 GitHub MCP セットアップ"
echo "======================================"

# .envファイルが既に存在するかチェック
if [ -f ".env" ]; then
    echo "✅ .env ファイルが既に存在します"
    echo "既存の設定を確認中..."
    
    # 既存の設定を読み込み
    if grep -q "GITHUB_TOKEN=" .env && grep -q "GITHUB_OWNER=" .env; then
        echo "✅ GitHub設定が見つかりました"
        source .env
        echo "設定内容:"
        echo "  GitHub Owner: ${GITHUB_OWNER}"
        echo "  GitHub Repo: ${GITHUB_REPO}"
        echo "  GitHub Token: $(echo ${GITHUB_TOKEN} | cut -c1-8)..."
        
        echo ""
        echo "既存の設定を使用しますか？ (y/n)"
        read -r use_existing
        
        if [ "$use_existing" = "y" ] || [ "$use_existing" = "Y" ]; then
            echo "✅ 既存の設定を使用します"
        else
            echo "新しい設定を入力してください"
            rm .env
        fi
    fi
fi

# .envファイルが存在しない場合は作成
if [ ! -f ".env" ]; then
    echo ""
    echo "GitHub認証情報を設定します..."
    echo ""
    
    # GitHub Personal Access Token の入力
    echo "GitHub Personal Access Token を入力してください:"
    echo "（権限: repo, pull_requests, contents が必要）"
    echo -n "Token: "
    read -s GITHUB_TOKEN
    echo ""
    
    # GitHub Owner の入力
    echo -n "GitHub ユーザー名/組織名を入力してください: "
    read GITHUB_OWNER
    
    # GitHub Repository名の入力
    echo -n "リポジトリ名 (デフォルト: isucon14-prod): "
    read GITHUB_REPO
    GITHUB_REPO=${GITHUB_REPO:-isucon14-prod}
    
    # .envファイルの作成
    cat > .env << EOF
# ISUCON14 GitHub MCP設定
GITHUB_TOKEN=${GITHUB_TOKEN}
GITHUB_OWNER=${GITHUB_OWNER}
GITHUB_REPO=${GITHUB_REPO}
EOF
    
    echo ""
    echo "✅ .env ファイルを作成しました"
fi

# .mcp.json が既に存在するかチェック
if [ -f ".mcp.json" ]; then
    echo "✅ .mcp.json が既に存在します"
else
    echo "❌ .mcp.json が見つかりません"
    echo "プロジェクトルートで実行していることを確認してください"
    exit 1
fi

# MCP パッケージの確認
echo ""
echo "GitHub MCPサーバーの確認中..."
if npx -y @modelcontextprotocol/server-github --help >/dev/null 2>&1; then
    echo "✅ GitHub MCPサーバーが利用可能です"
else
    echo "⚠️  GitHub MCPサーバーのインストールを確認中..."
    echo "初回実行時は時間がかかる場合があります"
fi

# .env の権限設定（セキュリティのため）
chmod 600 .env

echo ""
echo "======================================"
echo "GitHub MCP セットアップ完了！"
echo "======================================"
echo ""
echo "次のステップ:"
echo "1. Claude Code を再起動してください"
echo "2. GitHub MCP が利用可能になります"
echo ""
echo "利用可能な機能:"
echo "- mcp__github__create_pull_request"
echo "- mcp__github__list_pull_requests" 
echo "- mcp__github__get_repository"
echo ""
echo "⚠️  セキュリティ注意:"
echo "- .env ファイルは git に含まれません"
echo "- GitHub Token は第三者と共有しないでください"