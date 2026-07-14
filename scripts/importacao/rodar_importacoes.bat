@echo off
chcp 65001 >nul
title Importar (Stone extrato/vendas/recebiveis, BB, BS Cash)
setlocal EnableDelayedExpansion

cd /d "%~dp0"

set "SCRIPT=importar.py"
set "DOWNLOADS=%USERPROFILE%\Downloads"
set "TOTAL_IMPORTADOS=0"

if not exist "%SCRIPT%" (
    echo.
    echo ERRO: Script nao encontrado:
    echo "%SCRIPT%"
    echo Coloque este BAT na mesma pasta do arquivo Python.
    echo.
    pause
    exit /b 1
)

for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyMMdd"') do set "DATAIMPORT=%%D"

echo Procurando arquivos conhecidos em "%DOWNLOADS%"...
echo.

rem === Extrato Stone ===
set "ACHOU_PADRAO=0"
if not exist "relatorio-stone-extrato-old" mkdir "relatorio-stone-extrato-old"
for %%F in ("%DOWNLOADS%\Comprovante de Extrato*.csv") do (
    if exist "%%~fF" (
        set "ACHOU_PADRAO=1"
        set /a TOTAL_IMPORTADOS+=1
        echo ============================================
        echo Importando [Extrato Stone]: %%~nxF
        echo ============================================
        python "%SCRIPT%" "%%~fF"
        if !ERRORLEVEL! NEQ 0 (
            echo.
            echo ERRO ao importar: %%~nxF
            echo Arquivo NAO foi movido. Processo interrompido.
            pause
            exit /b 1
        )
        echo.
        echo Importacao OK. Movendo para "relatorio-stone-extrato-old"...
        move /Y "%%~fF" "relatorio-stone-extrato-old\%DATAIMPORT% - %%~nxF" >nul
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
if "%ACHOU_PADRAO%"=="0" (
    echo Nenhum arquivo [Extrato Stone] encontrado ^(padrao: Comprovante de Extrato*.csv^). Pulando.
    echo.
)

rem === Recebiveis Stone ===
set "ACHOU_PADRAO=0"
if not exist "relatorio-stone-recebimentos-old" mkdir "relatorio-stone-recebimentos-old"
for %%F in ("%DOWNLOADS%\relatorio-recebimentos-*.csv") do (
    if exist "%%~fF" (
        set "ACHOU_PADRAO=1"
        set /a TOTAL_IMPORTADOS+=1
        echo ============================================
        echo Importando [Recebiveis Stone]: %%~nxF
        echo ============================================
        python "%SCRIPT%" "%%~fF"
        if !ERRORLEVEL! NEQ 0 (
            echo.
            echo ERRO ao importar: %%~nxF
            echo Arquivo NAO foi movido. Processo interrompido.
            pause
            exit /b 1
        )
        echo.
        echo Importacao OK. Movendo para "relatorio-stone-recebimentos-old"...
        move /Y "%%~fF" "relatorio-stone-recebimentos-old\%DATAIMPORT% - %%~nxF" >nul
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
if "%ACHOU_PADRAO%"=="0" (
    echo Nenhum arquivo [Recebiveis Stone] encontrado ^(padrao: relatorio-recebimentos-*.csv^). Pulando.
    echo.
)

rem === Extrato BB ===
set "ACHOU_PADRAO=0"
if not exist "relatorio-bb-extrato-old" mkdir "relatorio-bb-extrato-old"
for %%F in ("%DOWNLOADS%\Extrato conta corrente - ??????.csv") do (
    if exist "%%~fF" (
        set "ACHOU_PADRAO=1"
        set /a TOTAL_IMPORTADOS+=1
        echo ============================================
        echo Importando [Extrato BB]: %%~nxF
        echo ============================================
        python "%SCRIPT%" "%%~fF"
        if !ERRORLEVEL! NEQ 0 (
            echo.
            echo ERRO ao importar: %%~nxF
            echo Arquivo NAO foi movido. Processo interrompido.
            pause
            exit /b 1
        )
        echo.
        echo Importacao OK. Movendo para "relatorio-bb-extrato-old"...
        move /Y "%%~fF" "relatorio-bb-extrato-old\%DATAIMPORT% - %%~nxF" >nul
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
if "%ACHOU_PADRAO%"=="0" (
    echo Nenhum arquivo [Extrato BB] encontrado ^(padrao: Extrato conta corrente - ??????.csv^). Pulando.
    echo.
)

rem === Extrato BS Cash ===
set "ACHOU_PADRAO=0"
if not exist "relatorio-bs-cash-old" mkdir "relatorio-bs-cash-old"
for %%F in ("%DOWNLOADS%\resultado_consulta*.csv") do (
    if exist "%%~fF" (
        set "ACHOU_PADRAO=1"
        set /a TOTAL_IMPORTADOS+=1
        echo ============================================
        echo Importando [Extrato BS Cash]: %%~nxF
        echo ============================================
        python "%SCRIPT%" "%%~fF"
        if !ERRORLEVEL! NEQ 0 (
            echo.
            echo ERRO ao importar: %%~nxF
            echo Arquivo NAO foi movido. Processo interrompido.
            pause
            exit /b 1
        )
        echo.
        echo Importacao OK. Movendo para "relatorio-bs-cash-old"...
        move /Y "%%~fF" "relatorio-bs-cash-old\%DATAIMPORT% - %%~nxF" >nul
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
if "%ACHOU_PADRAO%"=="0" (
    echo Nenhum arquivo [Extrato BS Cash] encontrado ^(padrao: resultado_consulta*.csv^). Pulando.
    echo.
)

rem === Vendas Stone (nome do arquivo e um UUID v4) ===
set "ACHOU_PADRAO=0"
if not exist "relatorio-stone-vendas-old" mkdir "relatorio-stone-vendas-old"
for /f "delims=" %%F in ('powershell -NoProfile -Command "Get-ChildItem -Path %DOWNLOADS% -File -Filter *.csv | Where-Object { $_.Name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\.csv$' } | Sort-Object Name | ForEach-Object { $_.FullName }"') do (
    set "ACHOU_PADRAO=1"
    set /a TOTAL_IMPORTADOS+=1
    echo ============================================
    echo Importando [Vendas Stone]: %%~nxF
    echo ============================================
    python "%SCRIPT%" "%%F"
    if !ERRORLEVEL! NEQ 0 (
        echo.
        echo ERRO ao importar: %%~nxF
        echo Arquivo NAO foi movido. Processo interrompido.
        pause
        exit /b 1
    )
    echo.
    echo Importacao OK. Movendo para "relatorio-stone-vendas-old"...
    move /Y "%%F" "relatorio-stone-vendas-old\%DATAIMPORT% - %%~nxF" >nul
    if !ERRORLEVEL! NEQ 0 (
        echo ERRO: Importou, mas nao conseguiu mover o arquivo: %%~nxF
        pause
        exit /b 1
    ) else (
        echo Arquivo movido com sucesso: %DATAIMPORT% - %%~nxF
    )
    echo.
)
if "%ACHOU_PADRAO%"=="0" (
    echo Nenhum arquivo [Vendas Stone] encontrado ^(padrao UUID v4^). Pulando.
    echo.
)

echo ============================================
if "%TOTAL_IMPORTADOS%"=="0" (
    echo Nenhum arquivo encontrado em "%DOWNLOADS%" para os padroes conhecidos.
) else (
    echo Processo finalizado. Total de arquivos importados: %TOTAL_IMPORTADOS%
)
echo ============================================
pause
exit /b 0
