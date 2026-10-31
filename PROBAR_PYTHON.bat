@echo off
chcp 65001 >nul
title Cliente Python ADS
rem Conecta el cliente Python al simulador (puerto 40000).
cd /d "%~dp0LibPhithon"
python examples\verify_simulator.py 40000
pause
