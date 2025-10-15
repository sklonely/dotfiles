<# bootstrap.ps1
功能：
  1) 檢查與安裝 Git
  2) 下載 / 更新 https://github.com/sklonely/dotfiles.git
  3) 執行 windows/scripts/install.ps1 → settings_install.ps1
  4) 自動套用設定、自啟 GlazeWM、重啟 WM

用法（系統管理員 PowerShell 建議）：
  irm https://raw.githubusercontent.com/sklonely/dotfiles/main/windows/bootstrap.ps1 | iex
#>

param(
  [string]$Branch = "main",
  [switch]$ApplyDotfiles
)

$RepoUrl = "https://github.com/sklonely/dotfiles.git"
$ErrorActionPreference = 'Stop'

function Has-Cmd($n){ [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Info($m){ Write-Host "INFO  $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "WARN  $m" -ForegroundColor Yellow }
function Ok($m){ Write-Host "OK    $m" -ForegroundColor Green }

# --- 提權（避免使用 ?:，改用參數陣列） ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Info "以管理員權限重新啟動 bootstrap.ps1..."
  $argList = @(
    '-NoProfile','-ExecutionPolicy','Bypass',
    '-File', ('"{0}"' -f $PSCommandPath),
    '-Branch', ('"{0}"' -f $Branch)
  )
  if ($ApplyDotfiles) { $argList += '-ApplyDotfiles' }
  Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
  exit
}

# --- 前置 ---
try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 安裝 Git ---
if (-not (Has-Cmd "git")) {
  Info "安裝 Git..."
  try {
    winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
  } catch {
    Warn "winget 安裝 Git 失敗，請手動安裝 Git 後再重試。"
    throw
  }
} else { Ok "Git 已存在。" }

# --- Clone / 更新 repo ---
$HOME     = $env:USERPROFILE
$RepoRoot = Join-Path $HOME "dev"
$RepoPath = Join-Path $RepoRoot "dotfiles"
New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null

if (-not (Test-Path $RepoPath)) {
  Info ("Clone：{0} → {1}（{2}）" -f $RepoUrl, $RepoPath, $Branch)
  git clone --branch $Branch --depth 1 $RepoUrl $RepoPath
} else {
  Info "更新：$RepoPath"
  Push-Location $RepoPath
  git fetch origin $Branch --prune
  git checkout $Branch
  git pull --rebase origin $Branch
  Pop-Location
}

# --- 執行安裝腳本 ---
$InstallScript  = Join-Path $RepoPath "windows\scripts\install.ps1"
$SettingsScript = Join-Path $RepoPath "windows\scripts\settings_install.ps1"

if (-not (Test-Path $InstallScript))  { throw "❌ 找不到 $InstallScript" }
if (-not (Test-Path $SettingsScript)) { throw "❌ 找不到 $SettingsScript" }

Write-Host "`n=== [1/2] 執行 install.ps1 ===`n" -ForegroundColor Magenta
& $InstallScript
if ($LASTEXITCODE -ne 0) { throw "install.ps1 執行失敗" }

Write-Host "`n=== [2/2] 執行 settings_install.ps1 ===`n" -ForegroundColor Magenta
$settingsArgs = @('-DotfilesRepoPath', $RepoPath)
if ($ApplyDotfiles) { $settingsArgs += '-ApplyDotfiles' }
& $SettingsScript @settingsArgs
if ($LASTEXITCODE -ne 0) { throw "settings_install.ps1 執行失敗" }

Ok "`n✅ 完成！GlazeWM 與 Zebar 已設定自啟。"
Ok "可登出 / 重啟確認環境是否自動載入。"
