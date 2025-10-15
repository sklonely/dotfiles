<# bootstrap.ps1
用法（系統管理員 PowerShell）：
  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
  # 方式 A：先下載這支檔案後執行
  .\bootstrap.ps1 -RepoUrl "https://github.com/<you>/dotfiles" -Branch "main" -ApplyDotfiles
  # 方式 B：直接用 raw 連結一行跑（自己換成你的 Raw URL）
  irm https://raw.githubusercontent.com/<you>/dotfiles/main/windows/bootstrap.ps1 | iex
#>
param(
  [Parameter(Mandatory = $true)][string]$RepoUrl,
  [string]$Branch = "main",
  [switch]$ApplyDotfiles
)

$ErrorActionPreference = 'Stop'
function Has-Cmd($n){ [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Info($m){ Write-Host "INFO  $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "WARN  $m" -ForegroundColor Yellow }
function Ok($m){ Write-Host "OK    $m" -ForegroundColor Green }

# 管理員提權
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
  Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -RepoUrl `"$RepoUrl`" -Branch `"$Branch`" $([string]::Join(' ', ($ApplyDotfiles ? '-ApplyDotfiles' : '')))" -Verb RunAs
  exit
}

try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1) 安裝 Git（winget）
if (-not (Has-Cmd "git")) {
  Info "安裝 Git（winget）…"
  winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
} else { Ok "Git 已存在" }

# 2) Clone / 更新 repo → 預設到 %USERPROFILE%\dev\dotfiles
$HOME     = $env:USERPROFILE
$RepoRoot = Join-Path $HOME "dev"
$RepoPath = Join-Path $RepoRoot "dotfiles"
New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null

if (-not (Test-Path $RepoPath)) {
  Info "Clone：$RepoUrl → $RepoPath（$Branch）"
  git clone --branch $Branch --depth 1 $RepoUrl $RepoPath
} else {
  Info "更新：$RepoPath"
  Push-Location $RepoPath
  git fetch origin $Branch --prune
  git checkout $Branch
  git pull --rebase origin $Branch
  Pop-Location
}

# 3) 執行 windows/scripts 下兩支腳本
$InstallScript  = Join-Path $RepoPath "windows\scripts\install.ps1"
$SettingsScript = Join-Path $RepoPath "windows\scripts\settings_install.ps1"
if (-not (Test-Path $InstallScript))  { throw "找不到 $InstallScript" }
if (-not (Test-Path $SettingsScript)) { throw "找不到 $SettingsScript" }

Write-Host "`n=== [1/2] 安裝 install.ps1 ===`n" -ForegroundColor Magenta
& $InstallScript
if ($LASTEXITCODE -ne 0) { throw "install.ps1 執行失敗" }

Write-Host "`n=== [2/2] 設定 settings_install.ps1 ===`n" -ForegroundColor Magenta
$args = @(); $args += @("-DotfilesRepoPath", $RepoPath, "-ApplyDotfiles")
& $SettingsScript @args
if ($LASTEXITCODE -ne 0) { throw "settings_install.ps1 執行失敗" }

Ok "`n✅ 全部完成，建議登出/重開驗證自啟與設定。"
