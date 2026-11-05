@echo off
setlocal DisableDelayedExpansion
if not exist "%~dp0CodexPill.Launch.ps1" (
  echo CodexPill.Launch.ps1 est introuvable. Extrayez TOUT le ZIP dans un dossier.
  pause
  exit /b 1
)
if not exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
  echo Windows PowerShell est introuvable.
  pause
  exit /b 1
)
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CodexPill.Launch.ps1"
exit /b 0
