# ISUCON 汎用分析ツールキット

ISUCON勉強用の汎用的なセットアップスクリプトとベンチマーク計測用ツールセットです。

## 🚀 概要

このツールキットは、ISUCON環境でのパフォーマンス分析を効率的に行うために開発されました。以下の3つの分析ツールを統合的に管理できます：

- **スロークエリ分析** - MySQLのスロークエリ分析
- **alp分析** - nginxアクセスログの分析  
- **pprof分析** - Goアプリケーションのプロファイリング

## 📋 目次

- [機能](#機能)
- [必要条件](#必要条件)
- [インストール](#インストール)
- [基本的な使用方法](#基本的な使用方法)
- [詳細な使用方法](#詳細な使用方法)
- [各ツールの詳細](#各ツールの詳細)
- [トラブルシューティング](#トラブルシューティング)
- [高度な使用例](#高度な使用例)
- [ファイル構成](#ファイル構成)

## ✨ 機能

### 🔄 統合管理
- 全ツールの一括セットアップ
- ベンチマーク前後の自動処理
- 統合レポート生成
- 過去結果との比較

### 📊 スロークエリ分析
- MySQLスロークエリログの自動設定
- mysqldumpslowによる詳細分析
- 実行時間・回数別の統計
- ログのローテーション管理

### 🌐 alp分析  
- alpの自動インストール
- nginx設定の自動変更（JSON/LTSV対応）
- レスポンス時間・リクエスト数分析
- URL別パフォーマンス統計

### 🔍 pprof分析
- Goアプリケーションの自動設定
- CPU/メモリ/ゴルーチンプロファイリング
- リアルタイム分析
- Webブラウザでの可視化

## 🔧 必要条件

### 対象環境
- Ubuntu 20.04/22.04
- CentOS 7/8 (一部機能)
- その他Linuxディストリビューション

### 必須ソフトウェア
- MySQL 5.7+ または MariaDB 10.3+
- nginx 1.14+
- Go 1.16+ (pprofを使用する場合)
- curl, wget
- sudo権限

### オプション
- jq (JSON解析用)
- git (バージョン管理用)

## 📥 インストール

### 1. ファイルをダウンロード

```bash
# Gitクローン（推奨）
git clone <repository-url> isucon_toolkit
cd isucon_toolkit/scripts/isucon_toolkit

# または直接ダウンロード
wget <archive-url>
tar -xzf isucon_toolkit.tar.gz
cd isucon_toolkit
```

### 2. 実行権限の設定

```bash
chmod +x *.sh
```

### 3. 設定ファイルの編集

環境に合わせて設定を変更：

```bash
vi config.env
```

**重要な設定項目:**
```bash
# データベース設定
DB_NAME="isuride"              # プロジェクトのDB名に変更
MYSQL_AUTH_MODE="sudo"         # sudo|auth を選択

# アプリケーション設定  
APP_PATH="/home/isucon/webapp" # アプリケーションのパスに変更
APP_SERVICE="isuride-go.service" # サービス名に変更

# Nginx設定
NGINX_CONFIG_PATH="/etc/nginx/nginx.conf"
NGINX_ACCESS_LOG="/var/log/nginx/access.log"

# pprof設定
PPROF_PORT="6060"
PPROF_HOST="localhost"
```

### 4. 初期設定の実行

```bash
# 統合セットアップ（推奨）
./isucon_toolkit.sh setup

# または個別にセットアップ
./setup_slowquery.sh
./setup_alp.sh  
./setup_pprof.sh
```

**依存関係の自動インストール:**
- graphviz（pprof用）は自動でインストールされます
- curl、tar（alp用）は必要に応じて確認されます
- MySQL、nginxは既存環境を使用します

## 🎯 基本的な使用方法

### クイックスタート（推奨フロー）

```bash
# 1. 初期設定（1回のみ）
./isucon_toolkit.sh setup

# 2. ベンチマーク前の準備
./isucon_toolkit.sh start

# 3. ベンチマーク実行（別ターミナル）
# [ここでベンチマークを実行]

# 4. 分析実行
./isucon_toolkit.sh analyze

# 5. 統合レポート生成
./isucon_toolkit.sh report

# 6. 状況確認
./isucon_toolkit.sh status
```

### 個別ツールの使用

```bash
# スロークエリ分析
./slowquery_analysis.sh start     # 記録開始
./slowquery_analysis.sh analyze   # 分析実行

# alp分析  
./alp_analysis.sh start           # 記録開始
./alp_analysis.sh analyze         # 分析実行

# pprof分析
./pprof_analysis.sh start         # サーバー確認
./pprof_analysis.sh capture       # プロファイル取得
./pprof_analysis.sh analyze       # 分析実行
```

## 📖 詳細な使用方法

### 統合管理スクリプト

#### `./isucon_toolkit.sh`

```bash
# 基本コマンド
./isucon_toolkit.sh setup          # 全ツール初期設定
./isucon_toolkit.sh start          # ベンチ前準備  
./isucon_toolkit.sh analyze        # 分析実行
./isucon_toolkit.sh report         # レポート生成
./isucon_toolkit.sh status         # 状況確認
./isucon_toolkit.sh cleanup        # クリーンアップ

# オプション
--parallel      # 並行処理実行
--verbose       # 詳細出力
--force         # 強制実行
--skip-setup    # セットアップスキップ

# 使用例
./isucon_toolkit.sh setup --parallel    # 並行セットアップ
./isucon_toolkit.sh analyze --verbose   # 詳細分析
./isucon_toolkit.sh report --force      # 強制レポート生成
```

## 🛠 各ツールの詳細

### スロークエリ分析ツール

#### セットアップ (`setup_slowquery.sh`)

```bash
./setup_slowquery.sh                    # 基本セットアップ
./setup_slowquery.sh -t 0.1             # 閾値0.1秒
./setup_slowquery.sh --check            # 設定確認のみ
```

**主な機能:**
- MySQL設定の自動バックアップ
- スロークエリログ有効化
- long_query_time設定
- ログファイル権限設定

#### 分析実行 (`slowquery_analysis.sh`)

```bash
./slowquery_analysis.sh start           # 記録開始
./slowquery_analysis.sh analyze         # 分析実行
./slowquery_analysis.sh analyze -t 20   # 上位20件表示
./slowquery_analysis.sh compare         # 過去結果比較
```

**分析内容:**
- 実行時間順ランキング
- 実行回数順ランキング  
- 平均実行時間順ランキング
- 実行時間分布統計

#### 設定無効化 (`disable_slowquery.sh`)

```bash
./disable_slowquery.sh                  # 無効化実行
./disable_slowquery.sh --keep-logs      # ログ保持
./disable_slowquery.sh --restore        # 完全復元
```

### alp分析ツール

#### セットアップ (`setup_alp.sh`)

```bash
./setup_alp.sh                          # JSON形式（推奨）
./setup_alp.sh --format ltsv            # LTSV形式
./setup_alp.sh --skip-install           # インストールスキップ
./setup_alp.sh --version v1.0.21        # バージョン指定
```

**主な機能:**
- alpの自動ダウンロード・インストール
- nginx設定の自動変更
- JSON/LTSV形式対応
- 設定ファイルバックアップ

#### 分析実行 (`alp_analysis.sh`)

```bash
./alp_analysis.sh start                 # 記録開始
./alp_analysis.sh analyze               # 基本分析
./alp_analysis.sh analyze -l 50         # 上位50件
./alp_analysis.sh analyze -m "^/api/"   # APIのみ
./alp_analysis.sh analyze --min-time 0.1 # 0.1秒以上のみ
```

**分析内容:**
- レスポンス時間順ランキング
- リクエスト数順ランキング
- URL別統計
- ステータスコード分布
- レスポンス時間分布

### pprof分析ツール

#### セットアップ (`setup_pprof.sh`)

```bash
./setup_pprof.sh                        # 自動検出
./setup_pprof.sh -d /path/to/go         # ディレクトリ指定
./setup_pprof.sh -p 6061                # ポート指定
./setup_pprof.sh --dry-run              # 変更内容確認
```

**主な機能:**
- main.goの自動検出
- pprofインポートの自動追加
- HTTPサーバーの自動設定
- バックアップファイル作成

#### 統合ワークフロー (`pprof_workflow.sh`) ⭐️推奨

```bash
# 初期セットアップ（初回のみ）
./pprof_workflow.sh setup

# フル分析（ベンチマーク実行込み）
./pprof_workflow.sh analyze

# クイック分析（ベンチマークなし）
./pprof_workflow.sh quick

# 状態確認
./pprof_workflow.sh status

# 全停止
./pprof_workflow.sh stop
```

**ワークフロー:**
1. `setup`: サーバーにpprof制御スクリプトを配置
2. `analyze`: ベンチマーク → プロファイル取得 → pprof起動 → ブラウザ表示
3. `quick`: プロファイル取得 → pprof起動 → ブラウザ表示（ベンチなし）

#### サーバー側制御 (`server_pprof.sh`)

サーバー上で直接実行する場合：

```bash
# プロファイル取得（負荷生成込み）
./server_pprof.sh capture

# pprofサーバー起動
./server_pprof.sh start

# 状態確認
./server_pprof.sh status

# 停止
./server_pprof.sh stop
```

#### ローカル側ポートフォワード (`local_pprof.sh`)

```bash
# ポートフォワード開始＆ブラウザ起動
./local_pprof.sh

# ポートフォワード停止
./local_pprof.sh --kill
```

#### 基本分析 (`pprof_analysis.sh`)

```bash
./pprof_analysis.sh start               # サーバー確認
./pprof_analysis.sh capture             # CPUプロファイル
./pprof_analysis.sh capture -t heap     # ヒープ
./pprof_analysis.sh capture --all-types # 全タイプ取得
./pprof_analysis.sh analyze             # 分析実行
./pprof_analysis.sh live -t cpu         # リアルタイム分析
```

**プロファイルタイプ:**
- `cpu` - CPU使用率
- `heap` - メモリ使用量
- `goroutine` - ゴルーチン数
- `block` - ブロッキング
- `mutex` - ミューテックス競合

## 🔧 トラブルシューティング

### よくある問題と解決策

#### 1. MySQL関連

**Q: "MySQL設定ファイルが見つかりません"**
```bash
# 手動で設定ファイル場所を確認
mysql --help | grep "Default options" -A 1

# 一般的な場所
ls -la /etc/mysql/my.cnf
ls -la /etc/my.cnf
```

**Q: "MySQLに接続できません"**
```bash
# MySQLサービス状況確認
sudo systemctl status mysql

# パスワード設定確認
mysql -u root -p -e "SELECT 1;"
```

**Q: "スロークエリログが空です"**
```bash
# 設定確認
mysql -e "SELECT @@slow_query_log, @@slow_query_log_file, @@long_query_time;"

# ログファイル権限確認
sudo ls -la /var/log/mysql/mysql-slow.log
```

#### 2. nginx関連

**Q: "alpが見つかりません"**
```bash
# 手動インストール
wget https://github.com/tkuchiki/alp/releases/download/v1.0.21/alp_linux_amd64.tar.gz
tar -xzf alp_linux_amd64.tar.gz
sudo mv alp /usr/local/bin/
```

**Q: "nginx設定にエラーがあります"**
```bash
# 設定テスト
sudo nginx -t

# バックアップからの復元
sudo cp nginx_original.conf.backup /etc/nginx/nginx.conf
sudo systemctl restart nginx
```

#### 3. Go/pprof関連

**Q: "main.goが見つかりません"**
```bash
# 手動検索
find /path/to/project -name "main.go" -type f

# 手動でpprofを追加
# main.goに以下を追加:
import _ "net/http/pprof"

go func() {
    log.Println(http.ListenAndServe(":6060", nil))
}()
```

**Q: "pprofサーバーに接続できません"**
```bash
# ポート確認
netstat -tlnp | grep :6060

# ファイアウォール確認
sudo ufw status
sudo firewall-cmd --list-ports
```

### ログファイルの確認

各スクリプトは詳細なログを出力します:

```bash
# 統合ログ
tail -f isucon_toolkit.log

# 個別ログ  
tail -f setup_slowquery.log
tail -f alp_analysis.log
tail -f pprof_analysis.log
```

### 権限問題の解決

```bash
# スクリプト実行権限
chmod +x *.sh

# ログディレクトリ権限
sudo chown -R $USER:$USER slowquery_logs/ alp_logs/ pprof_data/

# sudo権限なしでMySQLアクセス
# ~/.my.cnfに認証情報を設定
[client]
user=root
password=your_password
```

## 🚀 高度な使用例

### 1. 継続的分析

```bash
#!/bin/bash
# 継続的分析スクリプト例

while true; do
    echo "ベンチマーク準備開始: $(date)"
    ./isucon_toolkit.sh start
    
    echo "30秒待機..."
    sleep 30
    
    echo "分析実行: $(date)" 
    ./isucon_toolkit.sh analyze
    
    echo "1時間待機..."
    sleep 3600
done
```

### 2. 並行分析

```bash
# 複数のプロファイルを同時取得
./pprof_analysis.sh capture --all-types --concurrent

# 並行セットアップ
./isucon_toolkit.sh setup --parallel
```

### 3. カスタム分析

```bash
# 特定のURLパターンのみ分析
./alp_analysis.sh analyze -m "^/api/users/" -l 100

# 長時間のpprof取得
./pprof_analysis.sh capture -d 120s -t cpu
```

### 4. 結果の比較自動化

```bash
#!/bin/bash
# ベンチマーク前後の自動比較

echo "=== Before Benchmark ==="
./isucon_toolkit.sh analyze

echo "=== Running Benchmark ==="
# ベンチマークコマンドをここに

echo "=== After Benchmark ==="  
./isucon_toolkit.sh analyze

echo "=== Comparison ==="
./slowquery_analysis.sh compare
./alp_analysis.sh compare
./pprof_analysis.sh compare
```

## 📁 ファイル構成

```
scripts/isucon_toolkit/
├── README.md                    # このファイル
├── config.env                  # 環境設定ファイル
├── common_functions.sh         # 共通関数ライブラリ
├── isucon_toolkit.sh           # 統合管理スクリプト
│
├── setup_slowquery.sh          # スロークエリセットアップ
├── slowquery_analysis.sh       # スロークエリ分析
├── disable_slowquery.sh        # スロークエリ無効化
│
├── setup_alp.sh                # alpセットアップ  
├── alp_analysis.sh             # alp分析
│
├── setup_pprof.sh              # pprofセットアップ
├── pprof_analysis.sh           # pprof基本分析
├── pprof_workflow.sh           # pprof統合ワークフロー
├── server_pprof.sh             # サーバー側pprof制御
├── local_pprof.sh              # ローカル側ポートフォワード
│
├── slowquery_logs/             # スロークエリログ保存
├── slowquery_analysis/         # スロークエリ分析結果
├── alp_logs/                   # alpログ保存
├── alp_analysis/               # alp分析結果  
├── pprof_data/                 # pprofデータ保存
├── pprof_analysis/             # pprof分析結果
├── reports/                    # 統合レポート
│
└── *.log                       # 各種ログファイル
```

## 📋 分析結果の見方

### スロークエリ分析結果

```
Count: 150  Time=2.34s (351s)  Lock=0.00s (0s)  Rows=1.0 (150), user[user]@[host]
  SELECT * FROM users WHERE email = 'S'

Count: 75   Time=1.23s (92s)   Lock=0.00s (0s)  Rows=10.5 (788), user[user]@[host]  
  SELECT * FROM posts WHERE user_id = N ORDER BY created_at DESC LIMIT N
```

- **Count**: 実行回数
- **Time**: 平均実行時間（総実行時間）
- **Lock**: ロック待機時間
- **Rows**: 平均行数（総行数）

### alp分析結果

```
+-------+-----+-----+-----+-----+-----+--------+-------------------+-------+-------+---------+---------+
| COUNT | 1XX | 2XX | 3XX | 4XX | 5XX | METHOD |        URI        |  MIN  |  MAX  |   SUM   |   AVG   |
+-------+-----+-----+-----+-----+-----+--------+-------------------+-------+-------+---------+---------+
|  1000 |   0 | 800 |   0 | 150 |  50 |   GET  | /api/users        | 0.123 | 5.678 | 1234.56 |   1.235 |
|   500 |   0 | 450 |   0 |  30 |  20 |  POST  | /api/posts        | 0.234 | 3.456 |  567.89 |   1.136 |
+-------+-----+-----+-----+-----+-----+--------+-------------------+-------+-------+---------+---------+
```

### pprof Web画面アクセス

```bash
# ポートフォワーディング設定（ローカルからSSH接続時）
ssh -L 8081:localhost:6060 user@server

# ブラウザで以下にアクセス
http://localhost:8081/debug/pprof/
```

- **COUNT**: リクエスト数
- **1XX-5XX**: ステータスコード別件数
- **METHOD**: HTTPメソッド
- **URI**: エンドポイント
- **MIN/MAX/SUM/AVG**: レスポンス時間統計

### pprof分析結果

```
      flat  flat%   sum%        cum   cum%
     2.48s 41.33% 41.33%      2.48s 41.33%  runtime.mallocgc
     1.23s 20.50% 61.83%      1.23s 20.50%  main.expensiveFunction  
     0.89s 14.83% 76.66%      0.89s 14.83%  database/sql.(*DB).Query
```

- **flat**: そのファンクション自体での消費時間
- **flat%**: flat時間の割合
- **sum%**: 累積割合
- **cum**: そのファンクションとその呼び出し先の合計時間
- **cum%**: cum時間の割合

## 📊 パフォーマンス改善のヒント

### データベース最適化

1. **インデックス追加**
   ```sql
   -- スロークエリ結果から頻出するWHERE句にインデックスを追加
   CREATE INDEX idx_users_email ON users(email);
   CREATE INDEX idx_posts_user_id_created_at ON posts(user_id, created_at);
   ```

2. **クエリ最適化**
   ```sql
   -- N+1問題の解決
   SELECT u.*, p.* FROM users u LEFT JOIN posts p ON u.id = p.user_id;
   ```

### アプリケーション最適化

1. **ボトルネックの特定**
   - pprofでCPU使用率の高いファンクションを特定
   - メモリリークの検出

2. **レスポンス改善**
   - alpで遅いエンドポイントを特定
   - キャッシュの追加
   - 非同期処理の導入

### インフラ最適化

1. **nginx設定**
   ```nginx
   # 静的ファイルのキャッシュ
   location ~* \.(css|js|png|jpg)$ {
       expires 1d;
       add_header Cache-Control "public, no-transform";
   }
   
   # gzip圧縮
   gzip on;
   gzip_types text/plain application/json;
   ```

2. **MySQL設定**
   ```ini
   [mysqld]
   innodb_buffer_pool_size = 1G
   query_cache_size = 128M
   query_cache_type = 1
   ```

## 🔒 セキュリティ注意事項

- 本番環境での使用前に十分なテストを実施
- ログファイルに機密情報が含まれないよう注意
- pprofエンドポイントは本番では無効化
- バックアップファイルの権限設定に注意

## 🤝 貢献方法

バグ報告や機能改善の提案を歓迎します。

1. Issues での報告
2. Pull Request での改善提案
3. ドキュメントの改善

## 📄 ライセンス

MIT License

## 🆘 サポート

問題が解決しない場合は、以下の情報と共にお問い合わせください：

- OS バージョン
- MySQL バージョン
- nginx バージョン  
- Go バージョン（pprofを使用する場合）
- エラーメッセージ
- ログファイルの内容

---

**Happy ISUCON! 🎯**