# Azure Static Web App GitHub認証ユーザー同期

## 概要

このプロジェクトは、Azure Static Web Appの組み込み認証において、GitHubリポジトリの編集権限（push権限）を持つユーザーのみにアクセスを許可するためのPowerShellスクリプトを提供します。

## 機能

- GitHubリポジトリでpush権限を持つユーザーを自動的に検出
- Azure Static Web Appの認証済みユーザーと同期
- 新規ユーザーの自動招待
- 権限を失ったユーザーの自動削除
- ドライランモードでの事前確認
- 詳細なログ出力とエラーハンドリング

## 前提条件

### 必要なツール

1. **Azure CLI** (バージョン 2.0以上)
   - インストール: https://docs.microsoft.com/cli/azure/install-azure-cli
   - 認証: `az login`

2. **GitHub CLI** (バージョン 2.0以上)
   - インストール: https://cli.github.com/
   - 認証: `gh auth login`

3. **PowerShell** (バージョン 5.1以上、PowerShell Core 7.0以上推奨)

### 必要な権限

- **GitHub**: 対象リポジトリの読み取り権限（コラボレーター一覧の取得）
- **Azure**: Static Web Appの共同作成者ロール以上

### Azure Static Web Appの準備

1. Azure Portalで以下の情報を確認：
   - Static Web App名
   - リソースグループ名
   - GitHub認証が有効になっていること

## インストール

リポジトリをクローンまたはスクリプトをダウンロード：

```bash
git clone https://github.com/nuitsjp/swa-github-auth-study.git
cd swa-github-auth-study
```

## 設定ファイルの作成

スクリプトは共通設定ファイル `config.json` をサポートしています。これにより、毎回同じ引数を指定する必要がなくなります。

### 1. テンプレートをコピー

```bash
cp config.json.template config.json
```

### 2. 設定値を編集

`config.json` を開いて、以下の値を設定してください：

```json
{
  "azure": {
    "subscriptionId": "12345678-1234-1234-1234-123456789012",
    "resourceGroup": "my-resource-group",
    "staticWebAppName": "my-static-web-app"
  },
  "servicePrincipal": {
    "name": "GitHub-Actions-SWA-Sync"
  },
  "invitationSettings": {
    "expiresInHours": 168
  },
  "discussion": {
    "enabled": true,
    "categoryId": "DIC_kwDOxxxxxx",
    "title": "Azure Static Web App への招待: {username}",
    "bodyTemplate": "invitation-body-template.txt"
  }
}
```

### 設定項目の説明

| 項目 | 説明 | 例 |
|------|------|-----|
| `azure.subscriptionId` | AzureサブスクリプションID | `12345678-1234-1234-1234-123456789012` |
| `azure.resourceGroup` | Azureリソースグループ名 | `my-resource-group` |
| `azure.staticWebAppName` | Azure Static Web App名 | `my-static-web-app` |
| `servicePrincipal.name` | サービスプリンシパル名 | `GitHub-Actions-SWA-Sync` |
| `invitationSettings.expiresInHours` | 招待の有効期限（時間） | `168`（7日間） |
| `discussion.enabled` | Discussion投稿を有効にするか | `true` または `false` |
| `discussion.categoryId` | DiscussionカテゴリのID（後述の取得方法を参照） | `DIC_kwDOxxxxxx` |
| `discussion.title` | Discussionタイトルテンプレート（`{username}`がユーザー名に置換される） | `Azure Static Web App への招待: {username}` |
| `discussion.bodyTemplate` | 本文テンプレートファイルのパス | `invitation-body-template.txt` |

GitHubリポジトリは現在のGitリポジトリの`origin`リモートから自動的に検出されます。
実行前に `git remote get-url origin` を実行し、想定しているGitHubリポジトリを指していることを確認してください。
`origin`が見つからない、またはGitHubを指していない場合はエラーになります。

**注意**: `config.json` は `.gitignore` に含まれており、Gitにコミットされません。

### DiscussionカテゴリIDの取得方法

GitHub DiscussionsにユーザーInvitation通知を投稿する場合、対象リポジトリのDiscussionカテゴリIDが必要です。

**手順:**

1. リポジトリでDiscussionsが有効になっていることを確認
2. 以下のコマンドでカテゴリIDを取得（`owner/repo`を実際のリポジトリ名に置き換え）:

```bash
gh api graphql -f query='
{
  repository(owner: "owner", name: "repo") {
    discussionCategories(first: 10) {
      nodes {
        id
        name
        description
      }
    }
  }
}'
```

3. 出力から希望するカテゴリの`id`（例: `DIC_kwDOxxxxxx`）をコピー
4. `config.json`の`discussion.categoryId`に設定

**例:**

```json
{
  "data": {
    "repository": {
      "discussionCategories": {
        "nodes": [
          {
            "id": "DIC_kwDOxxxxxx",
            "name": "General",
            "description": "Chat about anything and everything here"
          },
          {
            "id": "DIC_kwDOyyyyyy",
            "name": "Announcements",
            "description": "Updates from maintainers"
          }
        ]
      }
    }
  }
}
```

この例では `DIC_kwDOxxxxxx` または `DIC_kwDOyyyyyy` のいずれかを使用できます。

### メッセージテンプレートのカスタマイズ

招待通知の本文は、テキストファイルで自由にカスタマイズできます。タイトルは設定ファイル内でテンプレート文字列として定義します。

**デフォルトのテンプレートファイル:**

- `invitation-body-template.txt`: Discussionの本文

**本文テンプレートで使用可能なプレースホルダー:**

- `{{USERNAME}}`: 招待されたユーザー名
- `{{INVITATION_URL}}`: 招待リンクURL

**タイトルテンプレートで使用可能なプレースホルダー:**

- `{username}`: 招待されたユーザー名（設定ファイルの`discussion.title`内で使用）

**カスタマイズ例:**

`config.json`:
```json
{
  "discussion": {
    "enabled": true,
    "categoryId": "DIC_kwDOxxxxxx",
    "title": "[重要] @{username} さんへの招待通知",
    "bodyTemplate": "invitation-body-template.txt"
  }
}
```

`invitation-body-template.txt`:
```markdown
## Azure Static Web App アクセス権限が付与されました

こんにちは、**{{USERNAME}}** さん！

以下の招待リンクにアクセスして認証を完了してください。

### 招待リンク

{{INVITATION_URL}}

### 注意事項

- 招待リンクの有効期限は**7日間**です
- 期限内にアクセスして GitHub 認証を完了してください
- 認証後、Static Web App の全機能にアクセス可能になります

### サポート

問題がある場合は、リポジトリの Issues でお知らせください。
```

**重要:** 招待されたユーザーごとに個別のDiscussionが作成されます。複数ユーザーを招待した場合、それぞれに専用のDiscussionスレッドが立ちます。

## 使用方法

### 1. 設定ファイルを準備する

- リポジトリルートの `config.json` に Azure Static Web App の情報を記載します。
- `sync.dryRun` を `true` にするとプレビューのみ実行されます。同期を適用するときは `false` に戻します。
- 例:

```jsonc
{
  "azure": {
    "subscriptionId": "your-subscription-id",
    "resourceGroup": "your-resource-group",
    "staticWebAppName": "your-static-web-app-name"
  },
  "servicePrincipal": {
    "name": "GitHub-Actions-SWA-Sync"
  },
  "sync": {
    "dryRun": false
  }
}
```

### 2. 同期スクリプトを実行する

```powershell
pwsh -File .\scripts\Sync-SwaUsers.ps1
```

スクリプトは `config.json` の値と Git の `origin` から対象リポジトリを検出し、ログに概要を表示します。

### 3. ドライランを実施する

1. `config.json` の `sync.dryRun` を `true` に変更します。
2. `pwsh -File .\scripts\Sync-SwaUsers.ps1` を実行します。
3. 結果を確認したら `sync.dryRun` を `false` に戻して同期を適用します。

## 実行例

### 例1: 初回同期（`sync.dryRun: false`）

```powershell
PS> pwsh -File .\scripts\Sync-SwaUsers.ps1

[2025-11-03 16:00:00] [INFO] ========================================
[2025-11-03 16:00:00] [INFO] Azure Static Web App ユーザー同期スクリプト
[2025-11-03 16:00:00] [INFO] ========================================
[2025-11-03 16:00:00] [INFO] AppName: my-swa
[2025-11-03 16:00:00] [INFO] ResourceGroup: my-rg
[2025-11-03 16:00:00] [INFO] GitHubRepo: myorg/myrepo (detected from git)
[2025-11-03 16:00:00] [INFO] ========================================
[2025-11-03 16:00:00] [INFO] 前提条件を確認中...
[2025-11-03 16:00:01] [SUCCESS] Azure CLI: OK
[2025-11-03 16:00:01] [SUCCESS] GitHub CLI: OK
[2025-11-03 16:00:02] [SUCCESS] Azure認証: OK
[2025-11-03 16:00:02] [SUCCESS] GitHub認証: OK
[2025-11-03 16:00:02] [INFO] ========================================
[2025-11-03 16:00:02] [INFO] GitHubリポジトリのコラボレーター一覧を取得中: myorg/myrepo
[2025-11-03 16:00:03] [SUCCESS] push権限を持つコラボレーター数: 3
[2025-11-03 16:00:03] [INFO] Azure Static Web Appのユーザー一覧を取得中: my-swa
[2025-11-03 16:00:04] [SUCCESS] 現在のAzureユーザー数: 0
[2025-11-03 16:00:04] [INFO] ========================================
[2025-11-03 16:00:04] [INFO] 差分を計算中...
[2025-11-03 16:00:04] [INFO] 追加対象ユーザー数: 3
[2025-11-03 16:00:04] [INFO]   - user1
[2025-11-03 16:00:04] [INFO]   - user2
[2025-11-03 16:00:04] [INFO]   - user3
[2025-11-03 16:00:04] [INFO] 削除対象ユーザー数: 0
[2025-11-03 16:00:04] [INFO] ========================================
[2025-11-03 16:00:04] [INFO] ユーザーを追加中...
[2025-11-03 16:00:05] [INFO] ユーザーを招待中: user1
[2025-11-03 16:00:06] [SUCCESS] ユーザーの招待に成功しました: user1
[2025-11-03 16:00:06] [INFO] ユーザーを招待中: user2
[2025-11-03 16:00:07] [SUCCESS] ユーザーの招待に成功しました: user2
[2025-11-03 16:00:07] [INFO] ユーザーを招待中: user3
[2025-11-03 16:00:08] [SUCCESS] ユーザーの招待に成功しました: user3
[2025-11-03 16:00:08] [INFO] ========================================
[2025-11-03 16:00:08] [SUCCESS] 同期完了
[2025-11-03 16:00:08] [SUCCESS] 成功: 3 件
[2025-11-03 16:00:08] [INFO] 失敗: 0 件
[2025-11-03 16:00:08] [INFO] ========================================
```

### 例2: ドライラン（`sync.dryRun: true`）

```powershell
PS> pwsh -File .\scripts\Sync-SwaUsers.ps1

[2025-11-03 16:05:00] [INFO] ========================================
[2025-11-03 16:05:00] [INFO] Azure Static Web App ユーザー同期スクリプト
[2025-11-03 16:05:00] [INFO] ========================================
[2025-11-03 16:05:00] [WARNING] 実行モード: ドライラン（変更は適用されません）
[2025-11-03 16:05:00] [INFO] ========================================
...
[2025-11-03 16:05:04] [INFO] 追加対象ユーザー数: 1
[2025-11-03 16:05:04] [INFO]   - newuser
[2025-11-03 16:05:04] [INFO] 削除対象ユーザー数: 1
[2025-11-03 16:05:04] [INFO]   - olduser
[2025-11-03 16:05:04] [INFO] ========================================
[2025-11-03 16:05:04] [WARNING] ドライランモードのため、変更は適用されません
[2025-11-03 16:05:04] [INFO] ========================================
```

### 例3: 変更なし（`sync.dryRun: false`）

```powershell
PS> pwsh -File .\scripts\Sync-SwaUsers.ps1

...
[2025-11-03 16:10:04] [INFO] 追加対象ユーザー数: 0
[2025-11-03 16:10:04] [INFO] 削除対象ユーザー数: 0
[2025-11-03 16:10:04] [SUCCESS] 同期が必要なユーザーはありません
[2025-11-03 16:10:04] [INFO] ========================================
```

## スクリプトの動作

### 処理フロー

1. **前提条件の確認**
   - Azure CLI、GitHub CLIのインストール確認
   - 認証状態の確認

2. **GitHubコラボレーター取得**
   - GitHub APIを使用してリポジトリのコラボレーター一覧を取得
   - push、admin、maintain権限を持つユーザーのみを抽出

3. **Azureユーザー取得**
   - Azure CLIを使用してStatic Web Appの現在のユーザー一覧を取得
   - `authenticated`ロールを持つユーザーを抽出

4. **差分計算**
   - 追加対象: GitHubにあってAzureにないユーザー
   - 削除対象: Azureにのみ存在するユーザー

5. **ユーザー同期**
   - 新規ユーザーを`authenticated`ロールで招待（有効期限: 7日間）
   - 削除対象ユーザーを`anonymous`ロールに変更

### エラーハンドリング

- API呼び出しの失敗時に最大3回まで自動リトライ
- 部分的な成功/失敗を記録し、最終的なサマリーを表示
- すべての操作を詳細にログ出力

### 招待の有効期限

ユーザー招待の有効期限は**168時間（7日間）**です。招待されたユーザーは、この期間内にGitHub認証でStatic Web Appにアクセスする必要があります。

## 運用方法

### 手動実行

権限の変更があった際に手動で実行：

```powershell
pwsh -File .\scripts\Sync-SwaUsers.ps1
```

### 定期実行（Windowsタスクスケジューラ）

1. タスクスケジューラを開く
2. 「タスクの作成」を選択
3. 「全般」タブ:
   - 名前: `Azure SWA User Sync`
   - セキュリティオプション: 適切なアカウントで実行

4. 「トリガー」タブ:
   - 新規トリガーを追加（例: 毎日1回実行）

5. 「操作」タブ:
- プログラム/スクリプト: `powershell.exe`
- 引数の追加:
  ```
  -ExecutionPolicy Bypass -File "C:\path\to\repo\scripts\Sync-SwaUsers.ps1"
  ```

6. タスクを保存

### 定期実行（GitHub Actions）

`.github/workflows/sync-users.yml`を作成：

```yaml
name: Sync Azure SWA Users

on:
  schedule:
    - cron: '0 0 * * *'  # 毎日午前0時（UTC）に実行
  workflow_dispatch:  # 手動実行も可能

jobs:
  sync:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Setup GitHub CLI
        run: |
          gh auth login --with-token <<< "${{ secrets.GH_PAT }}"
      
      - name: Sync Users
        run: |
          pwsh -File .\scripts\Sync-SwaUsers.ps1
```

**必要なシークレット:**
- `AZURE_CREDENTIALS`: Azureサービスプリンシパルの認証情報
- `GH_PAT`: GitHub Personal Access Token（repo権限）

Static Web App 名やリソースグループは `config.json` から読み込まれるため、CI 環境でも同じファイルを配置してください。

## トラブルシューティング

### Azure CLIがインストールされていない

```
[ERROR] Azure CLI (az) がインストールされていません
```

**解決方法**: https://docs.microsoft.com/cli/azure/install-azure-cli からAzure CLIをインストールしてください。

### GitHub CLIがインストールされていない

```
[ERROR] GitHub CLI (gh) がインストールされていません
```

**解決方法**: https://cli.github.com/ からGitHub CLIをインストールしてください。

### Azure認証エラー

```
[ERROR] Azureにログインしていません。'az login' を実行してください
```

**解決方法**:
```bash
az login
```

### GitHub認証エラー

```
[ERROR] GitHubにログインしていません。'gh auth login' を実行してください
```

**解決方法**:
```bash
gh auth login
```

### リポジトリへのアクセス権限がない

```
[ERROR] GitHubコラボレーターの取得に失敗しました
```

**解決方法**: GitHubリポジトリへの読み取り権限があることを確認してください。

### Azure Static Web Appへのアクセス権限がない

```
[ERROR] Azureユーザーの取得に失敗しました
```

**解決方法**: Azureで対象のStatic Web Appに対して「共同作成者」ロール以上が付与されていることを確認してください。

## 制約事項

- GitHubユーザー名での招待となるため、ユーザーは初回アクセス時にGitHub認証が必要です
- 招待の有効期限は168時間（7日間）です
- Azure Static Web App無償プランで動作します
- ユーザー削除は`anonymous`ロールへの変更で実現されます（完全削除ではありません）

## セキュリティに関する注意事項

- Azure認証情報とGitHub認証情報は安全に管理してください
- スクリプトはGitHub/Azure APIを使用するため、適切な権限管理が重要です
- 定期実行する場合は、ログを監視し異常な動作がないか確認してください

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。

## サポート

問題や質問がある場合は、GitHubのIssuesページで報告してください。
