#================================================================
#  MT5 全EA一括バックテスト - PowerShell版
#  機能: 10構成 × 4期間 = 40テストを順次実行、結果をCSV集計
#
#  使い方:
#    1. $MT5Path を自分のMT5インストール先に変更
#    2. PowerShell で実行: .\run_all_backtests.ps1
#    3. -Model パラメータでティックモデル変更可能
#       0 = Every tick (最高精度、最も遅い)
#       1 = 1 minute OHLC (推奨バランス)
#       2 = Open prices only (最速、精度低)
#================================================================

param(
    [string]$MT5Path = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [int]$Model = 0,
    [int]$Deposit = 10000,
    [int]$Leverage = 100,
    [string]$Symbol = "XAUUSD",
    [string]$Period = "D1"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDir = Join-Path $ScriptDir "reports"
$IniDir = Join-Path $ScriptDir "ini"
$SetDir = Join-Path $ScriptDir "sets"

# フォルダ作成
@($ReportDir, $IniDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null }
}

# MT5 存在チェック
if (-not (Test-Path $MT5Path)) {
    Write-Error "MT5が見つかりません: $MT5Path`n-MT5Path パラメータでパスを指定してください"
    exit 1
}

# テスト構成定義
$TestConfigs = @(
    # TrendFollow EA
    @{ EA = "experts\GOLD_TrendFollow_Pyramid"; Set = "VariantJ";     Label = "Variant-J" }
    @{ EA = "experts\GOLD_TrendFollow_Pyramid"; Set = "VariantK";     Label = "Variant-K" }
    @{ EA = "experts\GOLD_TrendFollow_Pyramid"; Set = "TF_FP_ATR";    Label = "TF-FP(ATR)" }
    @{ EA = "experts\GOLD_TrendFollow_Pyramid"; Set = "TF_FP_Swing";  Label = "TF-FP(Swing)" }
    @{ EA = "experts\GOLD_TrendFollow_Pyramid"; Set = "TF_FP_Pct";    Label = "TF-FP(Pct)" }
    @{ EA = "experts\GOLD_TrendFollow_Pyramid"; Set = "TF_FP_Fixed";  Label = "TF-FP(Fixed)" }
    @{ EA = "experts\GOLD_TrendFollow_Pyramid"; Set = "TF_MP_ATR";    Label = "TF-MP(ATR)" }
    @{ EA = "experts\GOLD_TrendFollow_Pyramid"; Set = "TF_MP_Swing";  Label = "TF-MP(Swing)" }
    # NanpinMartin EA
    @{ EA = "experts\GOLD_NanpinMartin";        Set = "NM_S20";       Label = "NM-S20" }
    @{ EA = "experts\GOLD_NanpinMartin";        Set = "NM_R50";       Label = "NM-R50" }
)

# テスト期間定義
$TestPeriods = @(
    @{ Name = "Full";  From = "2008.01.01"; To = "2026.09.11" }
    @{ Name = "IS1";   From = "2008.01.01"; To = "2015.12.31" }
    @{ Name = "IS2";   From = "2016.01.01"; To = "2019.12.31" }
    @{ Name = "OOS";   From = "2020.01.01"; To = "2026.09.11" }
)

# モデル名マッピング
$ModelNames = @{ 0 = "Every tick"; 1 = "1 minute OHLC"; 2 = "Open prices only" }

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  MT5 Batch Backtest - $($TestConfigs.Count) configs x $($TestPeriods.Count) periods"
Write-Host "  Model: $($ModelNames[$Model])"
Write-Host "  Symbol: $Symbol  Period: $Period  Deposit: $Deposit  Leverage: 1:$Leverage"
Write-Host "  Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "================================================================" -ForegroundColor Cyan

$TotalTests = $TestConfigs.Count * $TestPeriods.Count
$CurrentTest = 0
$Results = @()

foreach ($config in $TestConfigs) {
    foreach ($period in $TestPeriods) {
        $CurrentTest++
        $TestName = "$($config.Set)_$($period.Name)"
        $ReportFile = Join-Path $ReportDir "$TestName.html"
        $IniFile = Join-Path $IniDir "$TestName.ini"

        # INI生成
        $IniContent = @"
[Tester]
Expert=$($config.EA)
Symbol=$Symbol
Period=$Period
Optimization=0
Model=$Model
FromDate=$($period.From)
ToDate=$($period.To)
Report=$ReportFile
ReplaceReport=1
ShutdownTerminal=1
Deposit=$Deposit
Currency=USD
Leverage=$Leverage
ExpertParameters=backtest\sets\$($config.Set).set
Visual=0
"@
        Set-Content -Path $IniFile -Value $IniContent -Encoding UTF8

        # 進捗表示
        $Pct = [math]::Round(($CurrentTest / $TotalTests) * 100)
        Write-Host "[$CurrentTest/$TotalTests] ($Pct%) $($config.Label) - $($period.Name) " -NoNewline -ForegroundColor Yellow

        # MT5実行
        $StartTime = Get-Date
        $process = Start-Process -FilePath $MT5Path -ArgumentList "/config:`"$IniFile`"" -PassThru
        $process.WaitForExit(600000)  # 10分タイムアウト

        if (-not $process.HasExited) {
            Write-Host "TIMEOUT" -ForegroundColor Red
            $process.Kill()
        }

        $ElapsedSec = [math]::Round(((Get-Date) - $StartTime).TotalSeconds, 1)

        # レポート存在チェック
        if (Test-Path $ReportFile) {
            Write-Host "OK (${ElapsedSec}s)" -ForegroundColor Green
            $Results += [PSCustomObject]@{
                Config   = $config.Label
                Period   = $period.Name
                Report   = $ReportFile
                Status   = "OK"
                Duration = $ElapsedSec
            }
        }
        else {
            Write-Host "NO REPORT (${ElapsedSec}s)" -ForegroundColor Red
            $Results += [PSCustomObject]@{
                Config   = $config.Label
                Period   = $period.Name
                Report   = ""
                Status   = "FAILED"
                Duration = $ElapsedSec
            }
        }
    }
}

# 結果サマリー
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "  Successful: $(($Results | Where-Object Status -eq 'OK').Count) / $TotalTests"
Write-Host "================================================================" -ForegroundColor Cyan

# CSV出力
$CsvFile = Join-Path $ReportDir "batch_summary.csv"
$Results | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
Write-Host "Summary saved to: $CsvFile"

# テーブル表示
$Results | Format-Table -AutoSize

Write-Host ""
Write-Host "HTML reports in: $ReportDir" -ForegroundColor Green
Write-Host "To view: open each .html in a browser for detailed MT5 stats."
