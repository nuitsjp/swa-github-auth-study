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

## 使用方法

### 基本的な使い方

```powershell
.\sync-swa-users.ps1 -AppName "your-app-name" -ResourceGroup "your-resource-group" -GitHubRepo "owner/repo"
```

### ドライランモード（変更を適用せずに確認）

```powershell
.\sync-swa-users.ps1 -AppName "your-app-name" -ResourceGroup "your-resource-group" -GitHubRepo "owner/repo" -DryRun
```

### パラメータ

| パラメータ | 必須 | 説明 | 例 |
|-----------|------|------|-----|
| `AppName` | ○ | Azure Static Web App名 | `my-static-web-app` |
| `ResourceGroup` | ○ | Azureリソースグループ名 | `my-resource-group` |
| `GitHubRepo` | ○ | GitHubリポジトリ（形式: owner/repo） | `nuitsjp/swa-github-auth-study` |
| `DryRun` | × | 変更を適用せずに実行結果をプレビュー | （スイッチパラメータ） |

## 実行例

### 例1: 初回同期

```powershell
PS> .\sync-swa-users.ps1 -AppName "my-swa" -ResourceGroup "my-rg" -GitHubRepo "myorg/myrepo"

[2025-11-03 16:00:00] [INFO] ========================================
[2025-11-03 16:00:00] [INFO] Azure Static Web App ユーザー同期スクリプト
[2025-11-03 16:00:00] [INFO] ========================================
[2025-11-03 16:00:00] [INFO] AppName: my-swa
[2025-11-03 16:00:00] [INFO] ResourceGroup: my-rg
[2025-11-03 16:00:00] [INFO] GitHubRepo: myorg/myrepo
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

### 例2: ドライラン

```powershell
PS> .\sync-swa-users.ps1 -AppName "my-swa" -ResourceGroup "my-rg" -GitHubRepo "myorg/myrepo" -DryRun

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

### 例3: 変更なし

```powershell
PS> .\sync-swa-users.ps1 -AppName "my-swa" -ResourceGroup "my-rg" -GitHubRepo "myorg/myrepo"

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
.\sync-swa-users.ps1 -AppName "your-app-name" -ResourceGroup "your-resource-group" -GitHubRepo "owner/repo"
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
     -ExecutionPolicy Bypass -File "C:\path\to\sync-swa-users.ps1" -AppName "your-app-name" -ResourceGroup "your-resource-group" -GitHubRepo "owner/repo"
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
          .\sync-swa-users.ps1 -AppName "${{ secrets.SWA_APP_NAME }}" -ResourceGroup "${{ secrets.SWA_RESOURCE_GROUP }}" -GitHubRepo "${{ github.repository }}"
```

**必要なシークレット:**
- `AZURE_CREDENTIALS`: Azureサービスプリンシパルの認証情報
- `GH_PAT`: GitHub Personal Access Token（repo権限）
- `SWA_APP_NAME`: Static Web App名
- `SWA_RESOURCE_GROUP`: リソースグループ名

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
