#!/bin/bash

# Go アプリケーションにpprofを有効化するスクリプト

set -e

echo "======================================"
echo "Go アプリケーション pprof 有効化"
echo "======================================"

# 実際のGoアプリケーションファイルを使用
GO_MAIN_FILE="home/isucon/webapp/go/main.go"

if [ ! -f "$GO_MAIN_FILE" ]; then
    echo "❌ Goアプリケーション(main.go)が見つかりません: $GO_MAIN_FILE"
    echo "手動で以下を main.go に追加してください："
    echo 'import _ "net/http/pprof"'
    exit 1
fi

echo "Goアプリケーション発見: ${GO_MAIN_FILE}"

# バックアップを作成
echo "バックアップ作成中: ${GO_MAIN_FILE}.backup"
sudo cp "$GO_MAIN_FILE" "${GO_MAIN_FILE}.backup"

# pprofが既に有効かチェック
if grep -q "net/http/pprof" "$GO_MAIN_FILE"; then
    echo "✅ pprof既に有効になっています"
else
    echo "pprofを有効化中..."
    
    # importセクションを見つけて net/http/pprof を追加
    if grep -q "import (" "$GO_MAIN_FILE"; then
        # 複数行のimport文がある場合
        sudo sed -i '/import ($/a\\t_ "net/http/pprof"' "$GO_MAIN_FILE"
    else
        # 単一のimport文の場合、複数行形式に変換
        sudo sed -i 's/import "/import (\n\t"/' "$GO_MAIN_FILE"
        sudo sed -i '/import ($/a\\t_ "net/http/pprof"' "$GO_MAIN_FILE"
        # 最後に閉じ括弧を追加する必要がある場合の処理
        if ! grep -q ")" "$GO_MAIN_FILE" | head -5; then
            sudo sed -i '/import (/,/^[^[:space:]]/{ /^[^[:space:]]/i\)
}' "$GO_MAIN_FILE"
        fi
    fi
    echo "✅ pprofインポート追加完了"
fi

# 変更内容を表示
echo ""
echo "=== 変更後のimportセクション ==="
grep -A 10 -B 2 "import" "$GO_MAIN_FILE" | head -15

echo ""
echo "=== pprofエンドポイント ==="
echo "アプリケーション起動後、以下のURLでアクセス可能："
echo "- http://localhost:8080/debug/pprof/           (プロファイル一覧)"
echo "- http://localhost:8080/debug/pprof/profile    (CPUプロファイル)" 
echo "- http://localhost:8080/debug/pprof/heap       (メモリプロファイル)"
echo "- http://localhost:8080/debug/pprof/goroutine  (ゴルーチンプロファイル)"

echo ""
echo "=== 注意事項 ==="
echo "1. アプリケーションを再起動してください"
echo "2. ベンチマーク実行前にpprofエンドポイントが応答することを確認"
echo "3. 本番環境では、pprofを無効化することを検討してください"

echo ""
echo "✅ pprof設定完了"