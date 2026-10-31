@echo off
chcp 65001 >nul
title Simulador ADS (compilar y abrir)

set "PROYECTO=%~dp0simulador_flutter"
set "EXE=%PROYECTO%\build\windows\x64\runner\Release\simulador_ads.exe"

rem Localizar Flutter: primero en el PATH, si no en la ruta habitual.
set "FLUTTER_CMD=flutter"
where flutter >nul 2>nul
if errorlevel 1 set "FLUTTER_CMD=C:\Users\alcer\Documents\Flutter\flutter\bin\flutter.bat"

echo.
echo ============================================
echo  Compilando el simulador (modo release)...
echo ============================================
echo.

cd /d "%PROYECTO%"
call %FLUTTER_CMD% build windows --release
if errorlevel 1 (
    echo.
    echo [ERROR] Fallo la compilacion. Revisa los mensajes de arriba.
    pause
    exit /b 1
)

echo.
echo Compilacion correcta. Abriendo el simulador...
start "" "%EXE%"
exit /b 0
