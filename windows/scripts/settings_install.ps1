<# windows/scripts/settings_install.ps1
用法：
  .\settings_install.ps1 -DotfilesRepoPath "C:\Users\你\dev\dotfiles" -ApplyDotfiles
效果：
  - 將 %USERPROFILE%\.glzr\glazewm → 指到 repo 的 windows\settings\glazewm
  - 建立 Task Scheduler：登入時自啟 glazewm.exe（Highest）
  - 重啟 GlazeWM（由 config 的 startup_commands 啟動 Zebar）
#>
param(
  [Parameter(Mandatory=$true)][string]$DotfilesRepoPath,
  [switch]$ApplyDotfiles
)

$ErrorActionPreference = 'Stop'
function Info($m){ Write-Host "INFO  $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "WARN  $m" -ForegroundColor Yellow }
function Ok($m){ Write-Host "OK    $m" -ForegroundColor Green }

$HOME         = $env:USERPROFILE
$GlazeCfgDir  = Join-Path $HOME ".glzr\glazewm"                             # 工具預設讀取
$RepoGlazeDir = Join-Path $DotfilesRepoPath "windows\settings\glazewm"      # 來源（新佈局）

# 建立 Junction（若目標為實體資料夾，先備份）
function New-DirJunction($LinkPath, $TargetPath) {
  if (Test-Path $LinkPath -PathType Container -and -not (Get-Item $LinkPath).LinkType) {
    $bk = "$LinkPath.bak_{0:yyyyMMdd_HHmmss}" -f (Get-Date)
    Warn "目標為實體資料夾，先備份到：$bk"
    Move-Item $LinkPath $bk
  }
  if (Test-Path $LinkPath) { Remove-Item $LinkPath -Force -Recurse }
  New-Item -ItemType Directory -Force -Path (Split-Path $LinkPath) | Out-Null
  Info "建立 Junction：`"$LinkPath`" -> `"$TargetPath`""
  New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath | Out-Null
}

# 建立登入自啟 GlazeWM（最高權限）
function Ensure-GlazeWM-Autostart {
  $taskName = "GlazeWM AutoStart"
  $glazeExe = (Get-Command glazewm.exe -ErrorAction SilentlyContinue).Source
  if (-not $glazeExe) { Warn "找不到 glazewm.exe，略過建立自啟任務。"; return }
  $Action    = New-ScheduledTaskAction -Execute $glazeExe
  $Trigger   = New-ScheduledTaskTrigger -AtLogOn
  $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
  Register-ScheduledTask -TaskName $taskName -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null
  Ok "Task Scheduler 自啟設定完成。"
}

# 1) 套用 dotfiles：把 windows/settings/glazewm → %USERPROFILE%\.glzr\glazewm
if ($ApplyDotfiles) {
  if (-not (Test-Path $RepoGlazeDir)) {
    Warn "找不到 $RepoGlazeDir，請確認 repo 內 windows\settings\glazewm 是否存在。"
  } else {
    New-DirJunction -LinkPath $GlazeCfgDir -TargetPath $RepoGlazeDir
  }
} else {
  Info "未帶 -ApplyDotfiles，略過建立 junction。"
}

# 2) 確保登入自啟 GlazeWM
Ensure-GlazeWM-Autostart

# 3) Reload GlazeWM（若已在跑則重啟）
$glazeProc = Get-Process -Name "glazewm" -ErrorAction SilentlyContinue
if ($glazeProc) {
  Info "重啟 GlazeWM 以套用最新設定…"
  Stop-Process -Id $glazeProc.Id -Force
  Start-Sleep -Seconds 1
}
$glazeExe = (Get-Command glazewm.exe -ErrorAction SilentlyContinue).Source
if ($glazeExe) {
  Start-Process $glazeExe
  Ok "GlazeWM 已啟動（Zebar 將由 config 的 startup_commands 帶起）。"
} else {
  Warn "找不到 glazewm.exe，請確認已安裝。"
}

Ok "設定安裝腳本完成。"
exit 0
