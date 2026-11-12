@echo off
::
:: Sync the Tizen Action Compiler schema data with the attached device's
:: tizen-action version. Thin wrapper around actionc-sync.ps1 (same directory).
::
:: Usage: actionc-sync [-Target VERSION] [-List] [-DataDir DIR] [-Offline] [-Quiet]
::
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0actionc-sync.ps1" %*
exit /b %ERRORLEVEL%
