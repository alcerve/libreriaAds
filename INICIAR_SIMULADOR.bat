@echo off
rem ============================================================================
rem  INICIAR_SIMULADOR.bat
rem  Compila el simulador Flutter (modo release) y, si todo va bien, lo abre.
rem  Flujo: localizar Flutter -> compilar -> (si ok) abrir el ejecutable.
rem ============================================================================

rem --- Codificacion UTF-8 para que se vean bien las tildes y enies -------------
chcp 65001 >nul

rem --- Titulo de la ventana de la consola --------------------------------------
title Simulador ADS (compilar y abrir)

rem --- Ruta del proyecto Flutter ------------------------------------------------
rem     %~dp0 = carpeta donde esta este .bat (asi funciona desde cualquier sitio)
set "PROYECTO=%~dp0simulador_flutter"

rem --- Ruta del ejecutable que produce el build de Flutter ----------------------
set "EXE=%PROYECTO%\build\windows\x64\runner\Release\simulador_ads.exe"

rem --- Localizar Flutter --------------------------------------------------------
rem 1) Por defecto asumimos que "flutter" esta en el PATH del sistema.
set "FLUTTER_CMD=flutter"
rem 2) Comprobamos si existe en el PATH (where pone errorlevel=1 si no lo encuentra).
where flutter >nul 2>nul
rem 3) Si no esta en el PATH, usamos la ruta absoluta de la instalacion.
if errorlevel 1 set "FLUTTER_CMD=C:\Users\alcer\Documents\Flutter\flutter\bin\flutter.bat"

rem --- Cabecera visual en la consola -------------------------------------------
echo.
echo ============================================
echo  Compilando el simulador (modo release)...
echo ============================================
echo.

rem --- Entrar en la carpeta del proyecto ----------------------------------------
rem     /d permite cambiar tambien de unidad (por ejemplo de C: a D:).
cd /d "%PROYECTO%"

rem --- Compilar la aplicacion ---------------------------------------------------
rem     call: ejecuta flutter (que es otro .bat) y luego VUELVE a este script.
rem     Sin "call", este script terminaria en cuanto flutter acabase.
call %FLUTTER_CMD% build windows --release

rem --- Si la compilacion fallo (errorlevel >= 1), avisar y salir ---------------
if errorlevel 1 (
    echo.
    echo [ERROR] Fallo la compilacion. Revisa los mensajes de arriba.
    pause
    exit /b 1
)

rem --- Si llego hasta aqui, compilo bien: abrir el simulador -------------------
echo.
echo Compilacion correcta. Abriendo el simulador...
start "" "%EXE%"

rem --- Terminar devolviendo codigo 0 (exito) ------------------------------------
exit /b 0
