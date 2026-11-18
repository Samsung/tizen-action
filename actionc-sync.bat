@echo off
::
:: Sync the Tizen Action Compiler schema data with the data repository (latest
:: published tizen-action version, or the pinned one). Thin wrapper around actionc-sync.ps1 (same directory).
::
:: Usage: actionc-sync [-Target VERSION] [-List] [-DataDir DIR] [-Offline] [-Quiet]
::
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0actionc-sync.ps1" %*
exit /b %ERRORLEVEL%
