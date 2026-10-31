@echo off
chcp 65001 >nul
title Cliente C# ADS
rem Conecta el cliente C# al simulador (puerto 40000).
cd /d "%~dp0LibC#\examples\AdsExample"
dotnet run -- 40000
pause
