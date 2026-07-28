@echo off
setlocal
title Infra Check - Diagnostico e Manutencao Segura

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo.
  echo Este utilitario precisa ser executado como Administrador.
  echo Clique com o botao direito no arquivo e escolha "Executar como administrador".
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\InfraCheck.ps1" -Mode Menu
if errorlevel 1 (
  echo.
  echo A execucao terminou com erro. Consulte a pasta logs para mais detalhes.
  pause
)

endlocal
