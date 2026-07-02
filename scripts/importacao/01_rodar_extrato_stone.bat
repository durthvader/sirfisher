@echo off
chcp 65001 >nul
title Importar Extrato Stone
setlocal EnableDelayedExpansion

cd /d "%~dp0"

set "SCRIPT=01_importar_extrato_stone.py"
set "OLD=relatorio-stone-extrato-old"
set "DOWNLOADS=%USERPROFILE%\Downloads"
set "ACHOU=0"

for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyMMdd"') do set "DATAIMPORT=%%D"

if not exist "%SCRIPT%" (
    echo.
    echo ERRO: Script nao encontrado:
    echo "%SCRIPT%"
    echo Coloque este BAT na mesma pasta do arquivo Python.
    echo.
    pause
    exit /b 1
)

if not exist "%OLD%" (
    mkdir "%OLD%"
)

echo Procurando arquivos de extrato Stone em "%DOWNLOADS%"...
echo Padrao: "Comprovante de Extrato*.csv"
echo.

for %%F in ("%DOWNLOADS%\Comprovante de Extrato*.csv") do (
    if exist "%%~fF" (
        set "ACHOU=1"
        echo ============================================
        echo Importando: %%~nxF
        echo ============================================

        python "%SCRIPT%" "%%~fF"

        if !ERRORLEVEL! NEQ 0 (
            echo.
            echo ERRO ao importar: %%~nxF
            echo Arquivo NAO foi movido.
            echo Processo interrompido.
            pause
            exit /b 1
        )

        echo.
        echo Importacao OK. Movendo para "%OLD%"...
        move /Y "%%~fF" "%OLD%\%DATAIMPORT% - %%~nxF" >nul

        if !ERRORLEVEL! NEQ 0 (
            echo ERRO: Importou, mas nao conseguiu mover o arquivo: %%~nxF
            pause
            exit /b 1
        ) else (
            echo Arquivo movido com sucesso: %DATAIMPORT% - %%~nxF
        )

        echo.
    )
)

if "%ACHOU%"=="0" (
    echo Nenhum arquivo encontrado em "%DOWNLOADS%" com o padrao:
    echo "Comprovante de Extrato*.csv"
    echo.
    pause
    exit /b 1
)

echo ============================================
echo Processo finalizado.
echo ============================================
pause
