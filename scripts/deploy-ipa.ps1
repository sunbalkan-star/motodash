# CI でビルドされた IPA を取得し、Sideloadly を操作して接続中の iPhone にインストールする。
#   pwsh scripts/deploy-ipa.ps1            # main の最新ビルド(実行中なら完了まで待つ)
#   pwsh scripts/deploy-ipa.ps1 -RunId 123 # 指定ラン
#   pwsh scripts/deploy-ipa.ps1 -DownloadOnly
# 前提: gh ログイン済み / Sideloadly に Apple ID 保存済み / iPhone を USB(または Wi-Fi 同期)で接続
param(
    [long]$RunId,
    [switch]$DownloadOnly,
    [int]$DeviceTimeoutSec = 90,
    [int]$InstallTimeoutSec = 600
)
$ErrorActionPreference = 'Stop'
$repo = 'sunbalkan-star/motodash'
$sideloadly = Join-Path $env:LOCALAPPDATA 'Sideloadly\sideloadly.exe'
$outRoot = Join-Path $env:USERPROFILE 'Downloads\MotoDash-builds'

# ---- 1. ビルド取得 ----
if (-not $RunId) {
    $run = gh run list -R $repo --workflow build.yml --branch main --limit 1 --json databaseId,number,status,conclusion,headSha | ConvertFrom-Json | Select-Object -First 1
    if (-not $run) { throw 'ビルドが見つかりません' }
    $RunId = $run.databaseId
}
$run = gh run view $RunId -R $repo --json number,status,conclusion,headSha | ConvertFrom-Json
if ($run.status -ne 'completed') {
    Write-Host "ビルド #$($run.number) の完了を待っています…"
    gh run watch $RunId -R $repo --exit-status --interval 20 | Out-Null
    $run = gh run view $RunId -R $repo --json number,status,conclusion,headSha | ConvertFrom-Json
}
if ($run.conclusion -ne 'success') { throw "ビルド #$($run.number) は $($run.conclusion) です" }

$dir = Join-Path $outRoot $run.number
$ipa = Get-ChildItem $dir -Filter *.ipa -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ipa) {
    gh run download $RunId -R $repo -n MotoDash-unsigned-ipa -D $dir
    $ipa = Get-ChildItem $dir -Filter *.ipa | Select-Object -First 1
}
Write-Host "IPA: $($ipa.FullName)  (#$($run.number) $($run.headSha.Substring(0,7)))"
if ($DownloadOnly) { exit 0 }

# ---- 2. Sideloadly 操作(UI Automation) ----
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$AE = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]
$True_ = [System.Windows.Automation.Condition]::TrueCondition

function Get-Windows {
    $ids = @(Get-Process sideloadly -ErrorAction SilentlyContinue | ForEach-Object Id)
    if (-not $ids) { return @() }
    @($AE::RootElement.FindAll($Scope::Children, $True_) | Where-Object { $ids -contains $_.Current.ProcessId })
}
function Get-Main { Get-Windows | Where-Object { $_.Current.Name -like 'Sideloadly*' } | Select-Object -First 1 }
function Get-Texts($el) {
    @($el.FindAll($Scope::Descendants, $True_) | Where-Object {
        $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Text' -and $_.Current.Name } | ForEach-Object { $_.Current.Name })
}
function Get-Devices($main) {
    $combo = $main.FindAll($Scope::Descendants, $True_) | Where-Object {
        $_.Current.ControlType.ProgrammaticName -eq 'ControlType.ComboBox' -and $_.Current.Name -eq 'iDevice:' } | Select-Object -First 1
    if (-not $combo) { return @() }
    @($combo.FindAll($Scope::Descendants, $True_) | Where-Object {
        $_.Current.ControlType.ProgrammaticName -eq 'ControlType.ListItem' -and $_.Current.Name -and $_.Current.Name -notmatch '^<' } | ForEach-Object { $_.Current.Name })
}

# 前回の状態を持ち越さないよう起動し直し、IPA は引数で読み込ませる
Get-Process sideloadly -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2
Start-Process $sideloadly -ArgumentList "`"$($ipa.FullName)`""
$deadline = (Get-Date).AddSeconds(30)
while (-not ($main = Get-Main)) { if ((Get-Date) -gt $deadline) { throw 'Sideloadly が起動しません' }; Start-Sleep 1 }
Start-Sleep 3

$deadline = (Get-Date).AddSeconds($DeviceTimeoutSec)
while (-not ($devices = Get-Devices $main)) {
    if ((Get-Date) -gt $deadline) { throw 'iPhone が見つかりません(USB 接続・ロック解除・「このコンピュータを信頼」を確認)' }
    Start-Sleep 2
}
Write-Host "端末: $($devices[0])"

$start = $main.FindAll($Scope::Descendants, $True_) | Where-Object {
    $_.Current.ControlType.ProgrammaticName -eq 'ControlType.Button' -and $_.Current.Name -eq 'Start' } | Select-Object -First 1
if (-not $start) { throw 'Start ボタンが見つかりません' }
$before = Get-Texts $main
$start.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-Host 'インストール開始'

# 進行状況を表示しつつ完了 / 失敗 / ダイアログ(パスワード・2FA 等)を待つ
$seen = @{}; $before | ForEach-Object { $seen[$_] = 1 }
$deadline = (Get-Date).AddSeconds($InstallTimeoutSec)
while ($true) {
    if ((Get-Date) -gt $deadline) { throw 'インストールがタイムアウトしました' }
    $main = Get-Main
    if (-not $main) { throw 'Sideloadly が終了しました' }
    $texts = Get-Texts $main
    foreach ($t in $texts) { if (-not $seen[$t]) { $seen[$t] = 1; Write-Host "  $t" } }
    $joined = $texts -join "`n"
    if ($joined -match '(?im)^\s*Done\.?\s*$') { Write-Host '完了'; break }
    if ($joined -match '(?i)guru meditation|error|failed') { throw "Sideloadly がエラーを返しました: $(($texts | Select-String -Pattern 'error|failed|guru' -SimpleMatch:$false | Select-Object -First 1))" }
    $dialogs = Get-Windows | Where-Object { $_.Current.Name -notlike 'Sideloadly*' }
    foreach ($d in $dialogs) {
        $msg = (@($d.Current.Name) + (Get-Texts $d)) -join ' / '
        if (-not $seen["dlg:$msg"]) { $seen["dlg:$msg"] = 1; Write-Host "ダイアログ: $msg" }
    }
    if ($dialogs) { throw 'Sideloadly が入力を求めています。画面で操作してください' }
    Start-Sleep 2
}
