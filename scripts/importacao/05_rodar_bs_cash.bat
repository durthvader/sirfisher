@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

cd /d "%~dp0"

set "SCRIPT=05_importar_bs_cash.py"
set "OLD=relatorio-bs-cash-old"
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

echo Procurando arquivos da conta BS Cash em "%DOWNLOADS%"...
echo Padrao: "resultado_consulta*.csv"
echo.

for %%F in ("%DOWNLOADS%\resultado_consulta*.csv") do (
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
    echo "resultado_consulta*.csv"
    echo.
    pause
    exit /b 1
)

echo ========================================
echo Finalizado.
pause
exit /b 0
