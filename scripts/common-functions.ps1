<#
.SYNOPSIS
    スクリプト間で共有される共通関数とユーティリティ

.DESCRIPTION
    設定ファイルの読み込み、ログ出力、CLI存在確認などの共通機能を提供します。
#>

# ログ関数
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "White" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# 設定ファイルの読み込み
function Get-Configuration {
    param(
        [string]$ConfigPath = "config.json",
        [hashtable]$Overrides = @{}
    )
    
    $configFile = Join-Path $PSScriptRoot $ConfigPath
    
    # 設定ファイルが存在しない場合
    if (-not (Test-Path $configFile)) {
        # オーバーライドがすべて提供されている場合は警告のみ
        $requiredKeys = @("SubscriptionId", "ResourceGroup", "StaticWebAppName", "GitHubRepo")
        $allProvided = $requiredKeys | ForEach-Object { $Overrides.ContainsKey($_) } | Where-Object { $_ -eq $false } | Measure-Object | Select-Object -ExpandProperty Count
        
        if ($allProvided -eq 0) {
            Write-Log "設定ファイルが見つかりません。コマンドライン引数を使用します: $configFile" -Level WARNING
            return @{
                Azure = @{
                    SubscriptionId = $Overrides.SubscriptionId
                    ResourceGroup = $Overrides.ResourceGroup
                    StaticWebAppName = $Overrides.StaticWebAppName
                }
                GitHub = @{
                    Repository = $Overrides.GitHubRepo
                }
                ServicePrincipal = @{
                    Name = if ($Overrides.ContainsKey("ServicePrincipalName")) { $Overrides.ServicePrincipalName } else { "GitHub-Actions-SWA-Sync" }
                }
                InvitationSettings = @{
                    ExpiresInHours = if ($Overrides.ContainsKey("InvitationExpiresInHours")) { $Overrides.InvitationExpiresInHours } else { 168 }
                }
            }
        }
        
        Write-Log "設定ファイルが見つかりません: $configFile" -Level ERROR
        Write-Log "config.json.template をコピーして config.json を作成してください" -Level ERROR
        throw "設定ファイルが見つかりません"
    }
    
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        
        # 設定をハッシュテーブルに変換
        $configHash = @{
            Azure = @{
                SubscriptionId = $config.azure.subscriptionId
                ResourceGroup = $config.azure.resourceGroup
                StaticWebAppName = $config.azure.staticWebAppName
            }
            GitHub = @{
                Repository = $config.github.repository
            }
            ServicePrincipal = @{
                Name = $config.servicePrincipal.name
            }
            InvitationSettings = @{
                ExpiresInHours = $config.invitationSettings.expiresInHours
            }
        }
        
        # コマンドライン引数でオーバーライド
        if ($Overrides.ContainsKey("SubscriptionId")) {
            $configHash.Azure.SubscriptionId = $Overrides.SubscriptionId
        }
        if ($Overrides.ContainsKey("ResourceGroup")) {
            $configHash.Azure.ResourceGroup = $Overrides.ResourceGroup
        }
        if ($Overrides.ContainsKey("StaticWebAppName")) {
            $configHash.Azure.StaticWebAppName = $Overrides.StaticWebAppName
        }
        if ($Overrides.ContainsKey("GitHubRepo")) {
            $configHash.GitHub.Repository = $Overrides.GitHubRepo
        }
        if ($Overrides.ContainsKey("ServicePrincipalName")) {
            $configHash.ServicePrincipal.Name = $Overrides.ServicePrincipalName
        }
        if ($Overrides.ContainsKey("InvitationExpiresInHours")) {
            $configHash.InvitationSettings.ExpiresInHours = $Overrides.InvitationExpiresInHours
        }
        
        return $configHash
    }
    catch {
        Write-Log "設定ファイルの読み込みに失敗しました: $_" -Level ERROR
        throw
    }
}

# Azure CLIの存在確認
function Test-AzureCLI {
    try {
        $null = az --version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

# GitHub CLIの存在確認
function Test-GitHubCLI {
    try {
        $null = gh --version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

# 前提条件の確認（Azure CLI、GitHub CLI、認証状態）
function Test-Prerequisites {
    param(
        [switch]$SkipGitHub
    )
    
    Write-Log "前提条件を確認中..." -Level INFO
    
    if (-not (Test-AzureCLI)) {
        Write-Log "Azure CLI (az) がインストールされていません" -Level ERROR
        Write-Log "https://docs.microsoft.com/cli/azure/install-azure-cli からインストールしてください" -Level ERROR
        return $false
    }
    Write-Log "Azure CLI: OK" -Level SUCCESS
    
    if (-not $SkipGitHub) {
        if (-not (Test-GitHubCLI)) {
            Write-Log "GitHub CLI (gh) がインストールされていません" -Level ERROR
            Write-Log "https://cli.github.com/ からインストールしてください" -Level ERROR
            return $false
        }
        Write-Log "GitHub CLI: OK" -Level SUCCESS
    }
    
    # Azure認証状態の確認
    $azAccount = az account show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Azureにログインしていません。'az login' を実行してください" -Level ERROR
        return $false
    }
    Write-Log "Azure認証: OK" -Level SUCCESS
    
    if (-not $SkipGitHub) {
        # GitHub認証状態の確認
        $ghAuth = gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "GitHubにログインしていません。'gh auth login' を実行してください" -Level ERROR
            return $false
        }
        Write-Log "GitHub認証: OK" -Level SUCCESS
    }
    
    return $true
}
