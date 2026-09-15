@echo off
REM ================================================================
REM  MT5 全EA一括バックテスト実行スクリプト
REM  使い方:
REM    1. MT5_PATH を自分のMT5インストール先に変更
REM    2. このファイルを experts/ と同じ階層に配置
REM    3. 管理者権限で実行
REM ================================================================

REM === 設定 ===
set MT5_PATH=C:\Program Files\MetaTrader 5\terminal64.exe
set DATA_PATH=%APPDATA%\MetaQuotes\Terminal
set SCRIPT_DIR=%~dp0
set REPORT_DIR=%SCRIPT_DIR%reports
set INI_DIR=%SCRIPT_DIR%ini

REM レポートフォルダ作成
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"
if not exist "%INI_DIR%" mkdir "%INI_DIR%"

echo ================================================================
echo  MT5 Batch Backtest - 10 EA Configurations
echo  Start: %date% %time%
echo ================================================================

REM === テスト期間定義 ===
REM Full: 2008.01.01 - 2026.09.11
REM IS1:  2008.01.01 - 2015.12.31
REM IS2:  2016.01.01 - 2019.12.31
REM OOS:  2020.01.01 - 2026.09.11

REM === TrendFollow系 (8構成) ===
set TF_EA=experts\GOLD_TrendFollow_Pyramid
set TF_SETS=VariantJ VariantK TF_FP_ATR TF_FP_Swing TF_FP_Pct TF_FP_Fixed TF_MP_ATR TF_MP_Swing

for %%S in (%TF_SETS%) do (
    echo.
    echo ------ %%S (Full Period) ------
    call :run_test "%TF_EA%" "%%S" "2008.01.01" "2026.09.11" "%%S_Full"

    echo ------ %%S (IS 2008-2015) ------
    call :run_test "%TF_EA%" "%%S" "2008.01.01" "2015.12.31" "%%S_IS1"

    echo ------ %%S (IS 2016-2019) ------
    call :run_test "%TF_EA%" "%%S" "2016.01.01" "2019.12.31" "%%S_IS2"

    echo ------ %%S (OOS 2020-2026) ------
    call :run_test "%TF_EA%" "%%S" "2020.01.01" "2026.09.11" "%%S_OOS"
)

REM === NanpinMartin系 (2構成) ===
set NM_EA=experts\GOLD_NanpinMartin
set NM_SETS=NM_S20 NM_R50

for %%S in (%NM_SETS%) do (
    echo.
    echo ------ %%S (Full Period) ------
    call :run_test "%NM_EA%" "%%S" "2008.01.01" "2026.09.11" "%%S_Full"

    echo ------ %%S (IS 2008-2015) ------
    call :run_test "%NM_EA%" "%%S" "2008.01.01" "2015.12.31" "%%S_IS1"

    echo ------ %%S (IS 2016-2019) ------
    call :run_test "%NM_EA%" "%%S" "2016.01.01" "2019.12.31" "%%S_IS2"

    echo ------ %%S (OOS 2020-2026) ------
    call :run_test "%NM_EA%" "%%S" "2020.01.01" "2026.09.11" "%%S_OOS"
)

echo.
echo ================================================================
echo  All backtests completed: %date% %time%
echo  Reports saved to: %REPORT_DIR%
echo ================================================================
pause
goto :eof

REM ================================================================
REM  サブルーチン: 単一バックテスト実行
REM  引数: %1=EA名, %2=setファイル名, %3=開始日, %4=終了日, %5=レポート名
REM ================================================================
:run_test
set EA_NAME=%~1
set SET_NAME=%~2
set FROM_DATE=%~3
set TO_DATE=%~4
set REPORT_NAME=%~5

REM INIファイル生成
set INI_FILE=%INI_DIR%\%REPORT_NAME%.ini
(
echo [Tester]
echo Expert=%EA_NAME%
echo Symbol=XAUUSD
echo Period=D1
echo Optimization=0
echo Model=0
echo FromDate=%FROM_DATE%
echo ToDate=%TO_DATE%
echo Report=%REPORT_DIR%\%REPORT_NAME%.html
echo ReplaceReport=1
echo ShutdownTerminal=1
echo Deposit=10000
echo Currency=USD
echo Leverage=100
echo ExpertParameters=backtest\sets\%SET_NAME%.set
echo Visual=0
) > "%INI_FILE%"

echo   Running: %REPORT_NAME% ...
"%MT5_PATH%" /config:"%INI_FILE%"

REM MT5が完全に終了するのを待つ
:wait_loop
tasklist /FI "IMAGENAME eq terminal64.exe" 2>NUL | find /I /N "terminal64.exe">NUL
if "%ERRORLEVEL%"=="0" (
    timeout /t 5 /nobreak >NUL
    goto wait_loop
)

echo   Done: %REPORT_NAME%
goto :eof
