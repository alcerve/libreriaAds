@echo off
chcp 65001 >nul
title Simulador ADS (grafico)
rem Abre el simulador grafico. El servidor arranca solo en el puerto 40000.
start "" "%~dp0simulador_flutter\build\windows\x64\runner\Release\simulador_ads.exe"
