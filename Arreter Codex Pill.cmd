@echo off
setlocal DisableDelayedExpansion
if not exist "%~dp0CodexPill.Control.ps1" (
  echo CodexPill.Control.ps1 est introuvable. Extrayez TOUT le ZIP.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "%~dp0CodexPill.Control.ps1" -Action Stop
set "_codexpill_exit=%errorlevel%"
if not "%_codexpill_exit%"=="0" pause
exit /b %_codexpill_exit%
