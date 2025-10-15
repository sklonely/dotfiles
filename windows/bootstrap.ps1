<# bootstrap.ps1
- 記錄日誌、支援 irm|iex、自動提權（ArgumentList 單一字串）、錯誤暫停
- 取得 repo：Git 優先；失敗→下載 ZIP（無需 Git）
- 執行：windows/scripts/install.ps1 → windows/scripts/settings_install.ps1
用法（建議以系統管理員 PowerShell）：
  irm https://raw.githubusercontent.com/sklonely/dotfiles/main/windows/bootstrap.ps1 | iex
#>
$ErrorActionPreference = 'Continue'
param(
  [string]$Branch = "main",
  [switch]$ApplyDotfiles,
  [string]$LogPath,
  [switch]$PreferZip   # 強制走 ZIP（不使用 Git）
)

$ErrorActionPreference = 'Stop'

function Has-Cmd($n){ [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Info($m){ Write-Host "INFO  $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "WARN  $m" -ForegroundColor Yellow }
function Ok($m){ Write-Host "OK    $m" -ForegroundColor Green }

# 常數
$RepoUrl   = "https://github.com/sklonely/dotfiles.git"
$RawSelf   = "https://raw.githubusercontent.com/sklonely/dotfiles/$Branch/windows/bootstrap.ps1"
$HomeDir   = $env:USERPROFILE
$RepoRoot  = Join-Path $HomeDir "dev"
$RepoPath  = Join-Path $RepoRoot "dotfiles"
$ZipUrl    = "https://github.com/sklonely/dotfiles/archive/refs/heads/$Branch.zip"

# 日誌
if (-not $LogPath -or [string]::IsNullOrWhiteSpace($LogPath)) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $LogPath = Join-Path $HomeDir ("bootstrap_{0}.log" -f $stamp)
}
try {
  if (-not (Get-Variable -Name global:TranscriptStarted -ErrorAction SilentlyContinue)) {
    Start-Transcript -Path $LogPath -Append | Out-Null
    $global:TranscriptStarted = $true
    Info ("日誌寫入：{0}" -f $LogPath)
  }
} catch { Warn ("Start-Transcript 失敗：{0}" -f $_.Exception.Message) }

# ===== 提權（WinPS 5.1 相容：ArgumentList 用「單一字串」，支援 irm|iex） =====
try {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Info "以管理員權限重新啟動 bootstrap.ps1…"

    # 若是從 irm|iex 執行，$PSCommandPath 為空 → 先下載自身到 TEMP
    $selfPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($selfPath)) {
      $selfPath = Join-Path $env:TEMP "bootstrap.ps1"
      Info "下載自身腳本到暫存：$selfPath"
      Invoke-WebRequest -UseBasicParsing -Uri $RawSelf -OutFile $selfPath
    }

    # 重要：-ArgumentList 使用「單一字串」，自行處理引號與空白（WinPS 5.1 的可靠作法）
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$selfPath`" -Branch `"$Branch`" -LogPath `"$LogPath`""
    if ($ApplyDotfiles) { $arg += " -ApplyDotfiles" }
    if ($PreferZip)     { $arg += " -PreferZip" }

    Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -Verb RunAs
    exit
  }
} catch { Warn ("提權檢查/重啟失敗：{0}" -f $_.Exception.Message) }

# 主流程
try {
  try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch {}
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null

  # --- 取得/更新 repo：Git 優先；失敗→ZIP 後援 ---
  $gotRepo = $false
  if (-not $PreferZip) {
    if (Has-Cmd "git") {
      try {
        if (-not (Test-Path $RepoPath)) {
          Info ("Git clone：{0} → {1}（{2}）" -f $RepoUrl, $RepoPath, $Branch)
          git clone --branch $Branch --depth 1 $RepoUrl $RepoPath
        } else {
          Info "Git update：$RepoPath"
          Push-Location $RepoPath
          git fetch origin $Branch --prune
          git checkout $Branch
          git pull --rebase origin $Branch
          Pop-Location
        }
        $gotRepo = $true
      } catch {
        Warn ("Git 取得失敗：{0}" -f $_.Exception.Message)
      }
    } else {
      Warn "未安裝 Git，改用 ZIP 模式。"
    }
  }

  if (-not $gotRepo) {
    $tmp = Join-Path $env:TEMP ("dotfiles_{0}" -f ([System.Guid]::NewGuid().ToString("N")))
    $zip = "$tmp.zip"
    $ext = "$tmp"
    Info ("下載 ZIP：{0}" -f $ZipUrl)
    Invoke-WebRequest -UseBasicParsing -Uri $ZipUrl -OutFile $zip
    Info ("解壓到：{0}" -f $ext)
    Expand-Archive -Path $zip -DestinationPath $ext -Force
    # GitHub zip 解壓通常為 dotfiles-<branch>
    $unz = Join-Path $ext ("dotfiles-{0}" -f $Branch)
    if (-not (Test-Path $unz)) {
      $dirs = Get-ChildItem $ext -Directory | Select-Object -First 1
      if ($dirs) { $unz = $dirs.FullName }
    }
    if (-not (Test-Path $unz)) { throw "ZIP 解壓後找不到 repo 內容。" }

    New-Item -ItemType Directory -Force -Path $RepoPath | Out-Null
    Info ("同步檔案到 {0}" -f $RepoPath)
    robocopy $unz $RepoPath /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
    $gotRepo = $true
    Ok "已透過 ZIP 取得 repo。"
  }

  # --- 執行子腳本 ---
  $InstallScript  = Join-Path $RepoPath "windows\scripts\install.ps1"
  $SettingsScript = Join-Path $RepoPath "windows\scripts\settings_install.ps1"
  if (-not (Test-Path $InstallScript))  { throw "找不到 $InstallScript" }
  if (-not (Test-Path $SettingsScript)) { throw "找不到 $SettingsScript" }

  Write-Host "`n=== [1/2] 執行 install.ps1 ===`n" -ForegroundColor Magenta
  & $InstallScript
  if ($LASTEXITCODE -ne 0) { throw "install.ps1 執行失敗（ExitCode=$LASTEXITCODE）" }

  Write-Host "`n=== [2/2] 執行 settings_install.ps1 ===`n" -ForegroundColor Magenta
  $settingsArgs = @('-DotfilesRepoPath', $RepoPath)
  if ($ApplyDotfiles) { $settingsArgs += '-ApplyDotfiles' }
  & $SettingsScript @settingsArgs
  if ($LASTEXITCODE -ne 0) { throw "settings_install.ps1 執行失敗（ExitCode=$LASTEXITCODE）" }

  Ok "`n✅ 完成！GlazeWM 與 Zebar 已設定自啟。建議登出/重開確認環境。"
}
catch {
  Write-Host "`n❌ 發生錯誤：" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  if ($_.ScriptStackTrace) {
    Write-Host "`nStackTrace:" -ForegroundColor DarkRed
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
  }
  Write-Host "`n日誌檔：$LogPath" -ForegroundColor Yellow
  Write-Host "`n按任意鍵關閉視窗…" -ForegroundColor Yellow
  $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
finally {
  try {
    if (Get-Variable -Name global:TranscriptStarted -ErrorAction SilentlyContinue) {
      Stop-Transcript | Out-Null
      Remove-Variable -Name global:TranscriptStarted -Scope Global -ErrorAction SilentlyContinue
    }
  } catch {}
}
