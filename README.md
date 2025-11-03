# swa-github-auth-study

Azure Static Web AppとGitHub Repositoryユーザーの同期サンプル

## 概要

このリポジトリは、Azure Static Web Appの組み込み認証において、GitHubリポジトリの編集権限（push権限）を持つユーザーのみにアクセスを許可するためのPowerShellスクリプトを提供します。

## 主な機能

- GitHubリポジトリのコラボレーター（push権限以上）を自動検出
- Azure Static Web Appの認証済みユーザーと同期
- 新規ユーザーの自動招待と権限を失ったユーザーの自動削除
- ドライランモードでの事前確認機能
- 詳細なログ出力とエラーハンドリング

## クイックスタート

### 前提条件

- Azure CLI（認証済み）
- GitHub CLI（認証済み）
- PowerShell 5.1以上

### 基本的な使い方

```powershell
.\sync-swa-users.ps1 -AppName "your-app-name" -ResourceGroup "your-resource-group" -GitHubRepo "owner/repo"
```

### ドライラン（変更を適用せずに確認）

```powershell
.\sync-swa-users.ps1 -AppName "your-app-name" -ResourceGroup "your-resource-group" -GitHubRepo "owner/repo" -DryRun
```

## ドキュメント

詳細な使用方法、インストール手順、トラブルシューティングについては、[USAGE.md](USAGE.md)を参照してください。

## ファイル構成

- `sync-swa-users.ps1` - メインスクリプト
- `USAGE.md` - 詳細な使用方法とドキュメント
- `.github/workflows/` - Azure Static Web Apps CI/CD設定

## ライセンス

MIT License
