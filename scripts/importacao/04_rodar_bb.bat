@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

cd /d "%~dp0"

set "SCRIPT=04_importar_bb.py"
set "OLD=relatorio-bb-extrato-old"
set "DOWNLOADS=%USERPROFILE%\Downloads"
set "ENCONTROU=0"

for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyMMdd"') do set "DATAIMPORT=%%D"

if not exist "%SCRIPT%" (
    echo ERRO: Script nao encontrado:
    echo "%SCRIPT%"
    echo.
    pause
    exit /b 1
)

if not exist "%OLD%" (
    mkdir "%OLD%"
)

echo Procurando arquivos do Banco do Brasil em "%DOWNLOADS%"...
echo Padrao: "Extrato conta corrente - ??????.csv"
echo.

for %%F in ("%DOWNLOADS%\Extrato conta corrente - ??????.csv") do (
    if exist "%%~fF" (
        set "ENCONTROU=1"

        echo ========================================
        echo Arquivo encontrado:
        echo "%%~nxF"
        echo.

        echo Importando no banco...
        python "%SCRIPT%" "%%~fF"

        if !ERRORLEVEL! NEQ 0 (
            echo.
            echo ERRO: Falha na importacao. Arquivo NAO foi movido.
            echo Processo interrompido.
            pause
            exit /b 1
        )

        echo.
        echo Importacao OK. Movendo arquivo para "%OLD%"...
        move /Y "%%~fF" "%OLD%\%DATAIMPORT% - %%~nxF" >nul

        if !ERRORLEVEL! NEQ 0 (
            echo ERRO: Importou, mas nao conseguiu mover o arquivo.
            pause
            exit /b 1
        ) else (
            echo Arquivo movido com sucesso.
        )

        echo.
    )
)

if "%ENCONTROU%"=="0" (
    echo ERRO: Nenhum arquivo encontrado em "%DOWNLOADS%" no padrao:
    echo "Extrato conta corrente - ??????.csv"
    echo.
    pause
    exit /b 1
)

echo ========================================
echo Finalizado.
pause
exit /b 0
