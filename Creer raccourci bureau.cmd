@echo off
setlocal DisableDelayedExpansion
if not exist "%~dp0CodexPill.Shortcut.ps1" (
  echo CodexPill.Shortcut.ps1 est introuvable. Extrayez TOUT le ZIP dans un dossier.
  pause
  exit /b 1
)
if not exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
  echo Windows PowerShell est introuvable.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0CodexPill.Shortcut.ps1"
exit /b %errorlevel%
