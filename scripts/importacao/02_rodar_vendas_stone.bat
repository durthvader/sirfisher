@echo off
chcp 65001 >nul
title Importar Vendas Stone
setlocal EnableDelayedExpansion

cd /d "%~dp0"

set "SCRIPT=02_importar_vendas_stone.py"
set "OLD=relatorio-stone-vendas-old"
set "DOWNLOADS=%USERPROFILE%\Downloads"
set "ACHOU=0"

for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyMMdd"') do set "DATAIMPORT=%%D"

if not exist "%SCRIPT%" (
    echo ERRO: Script %SCRIPT% nao encontrado.
    echo Coloque este BAT na mesma pasta do arquivo Python.
    echo.
    pause
    exit /b 1
)

if not exist "%OLD%" (
    mkdir "%OLD%"
)

echo Procurando arquivos CSV cujo nome seja UUID v4 em "%DOWNLOADS%"...
echo.

for /f "delims=" %%F in ('powershell -NoProfile -Command "Get-ChildItem -Path %DOWNLOADS% -File -Filter *.csv | Where-Object { $_.Name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\.csv$' } | Sort-Object Name | ForEach-Object { $_.FullName }"') do (
    set "ACHOU=1"

    echo ============================================
    echo Importando: %%~nxF
    echo ============================================

    python "%SCRIPT%" "%%F"

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
    move /Y "%%F" "%OLD%\%DATAIMPORT% - %%~nxF" >nul

    if !ERRORLEVEL! NEQ 0 (
        echo.
        echo ERRO: Importou, mas nao conseguiu mover o arquivo: %%~nxF
        echo Verifique se a pasta "%OLD%" existe e se o arquivo nao esta aberto.
        pause
        exit /b 1
    ) else (
        echo Arquivo movido com sucesso: %DATAIMPORT% - %%~nxF
    )

    echo.
)

if "%ACHOU%"=="0" (
    echo Nenhum arquivo encontrado no padrao UUID v4 em "%DOWNLOADS%":
    echo xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx.csv
    echo.
    pause
    exit /b 1
)

echo ============================================
echo Processo finalizado.
echo ============================================
pause
