# GitHub MCP セットアップガイド

## 概要

ISUCON14プロジェクト用のGitHub MCP（Model Context Protocol）設定手順です。
これにより、Claude CodeからGitHub APIを直接操作してプルリクエストの自動作成が可能になります。

## 🚀 クイックセットアップ

### 1. MCP設定スクリプトの実行

```bash
# プロジェクトルートで実行
bash scripts/setup_mcp.sh
```

### 2. GitHub Personal Access Token の準備

以下の手順でトークンを作成してください：

1. GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. **Generate new token (classic)** をクリック
3. 必要な権限を選択：
   - ✅ `repo` - Full control of private repositories
   - ✅ `pull_requests` - Read and write pull requests
   - ✅ `contents` - Read and write repository contents

### 3. 設定情報の入力

スクリプト実行時に以下を入力：
- **GitHub Personal Access Token**: 上記で作成したトークン
- **GitHub ユーザー名/組織名**: リポジトリオーナー名
- **リポジトリ名**: デフォルトは `isucon14-prod`

### 4. Claude Code の再起動

設定完了後、Claude Code を再起動して設定を反映させてください。

## 📁 作成されるファイル

### `.mcp.json`（バージョン管理対象）
```json
{
  "mcpServers": {
    "isucon14-github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}",
        "GITHUB_OWNER": "${GITHUB_OWNER}",
        "GITHUB_REPO": "${GITHUB_REPO}"
      }
    }
  }
}
```

### `.env`（バージョン管理対象外）
```bash
# GitHub認証情報（機密情報）
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
GITHUB_OWNER=your-username
GITHUB_REPO=isucon14-prod
```

## 🛠️ 利用可能な機能

### MCP関数の一覧

設定完了後、以下の関数が利用可能になります：

- **`mcp__github__create_pull_request`** - プルリクエスト作成
- **`mcp__github__list_pull_requests`** - プルリクエスト一覧取得
- **`mcp__github__get_repository`** - リポジトリ情報取得
- **`mcp__github__create_issue`** - Issue作成
- **`mcp__github__search_repositories`** - リポジトリ検索

### PR自動作成の使用例

```bash
# スコア改善後のPR作成例
mcp__github__create_pull_request \
  --title "Performance improvement: 1000 → 1500 points (+50%)" \
  --body "$(cat <<'EOF'
## Performance Improvement

**Score**: 1000 → 1500 points (+500, +50%)

## Changes Made
- Fixed N+1 query in user profile endpoint
- Added index on rides(user_id)
- Optimized image processing with streaming

## Impact Analysis
- Database query time: -80%
- Memory usage: -30%
- Response time: 200ms → 50ms

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)"
```

## ⚠️ セキュリティ注意事項

### 重要な安全対策

1. **`.env` ファイルの管理**
   - Git に含まれません（`.gitignore`で除外済み）
   - 権限を `600` に設定（所有者のみ読み書き可能）
   - 第三者と共有しないでください

2. **GitHub Token の権限**
   - 必要最小限の権限のみ付与
   - 定期的な更新を推奨
   - 漏洩時は即座に削除

3. **チーム共有**
   - `.mcp.json` はバージョン管理対象（認証情報なし）
   - 各メンバーが個別に `.env` を設定

## 🔧 トラブルシューティング

### よくある問題と解決方法

#### 1. MCP関数が利用できない
```bash
# Claude Code再起動後も利用できない場合
npx -y @modelcontextprotocol/server-github --help
```

#### 2. 認証エラー
- GitHub Tokenの権限を確認
- Tokenの有効期限をチェック
- `.env` ファイルの環境変数名を確認

#### 3. リポジトリアクセスエラー
- GitHub Owner/Repo名が正しいか確認
- プライベートリポジトリの場合、Tokenに `repo` 権限があるか確認

### ログの確認方法

```bash
# 設定確認
cat .env
cat .mcp.json

# MCPサーバーの動作確認
npx -y @modelcontextprotocol/server-github --help
```

## 🔄 更新・メンテナンス

### トークンの更新

```bash
# .env ファイルを編集
nano .env

# Claude Code を再起動
```

### 設定の削除

```bash
# MCP設定を完全に削除する場合
rm .env
# Claude Code を再起動
```

## 📚 参考資料

- [Claude Code MCP Documentation](https://docs.anthropic.com/en/docs/claude-code/mcp)
- [GitHub Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [Model Context Protocol](https://modelcontextprotocol.io/)

## 🎯 ISUCONでの活用

この設定により、以下のワークフローが可能になります：

1. **コード改善**
2. **ベンチマーク実行**
3. **スコア向上確認**
4. **PR自動作成** ← MCP機能
5. **チームでのレビュー**
6. **マージ・デプロイ**

効率的なISUCON攻略に活用してください！