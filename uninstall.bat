@echo off
::
:: Windows Batch uninstallation script for the Tizen Action Compiler.
:: Removes %USERPROFILE%\.action-tools and the environment setup added by install.bat.
::

setlocal enabledelayedexpansion

set "INSTALL_DIR=%USERPROFILE%\.action-tools"

echo === Uninstalling Tizen Action Compiler (Windows 64-bit) ===
echo Target directory: %INSTALL_DIR%

:: --- Remove installed files -----------------------------------------
echo [1/2] Removing installed binaries and schema data...

if exist "%INSTALL_DIR%" (
    rmdir /S /Q "%INSTALL_DIR%"
    echo Removed %INSTALL_DIR%.
) else (
    echo %INSTALL_DIR% not found; nothing to remove.
)

:: --- Remove persistent user environment variables -------------------
echo [2/2] Removing persistent user environment variables...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$InstallDir = [System.IO.Path]::Combine($env:USERPROFILE, '.action-tools');" ^
    "$UserPath = [Environment]::GetEnvironmentVariable('PATH', 'User');" ^
    "if ($UserPath -like '*\.action-tools*') {" ^
    "    $NewPath = ($UserPath -split ';' | Where-Object { $_ -and $_ -notlike '*\.action-tools*' }) -join ';';" ^
    "    [Environment]::SetEnvironmentVariable('PATH', $NewPath, 'User');" ^
    "    Write-Host 'Removed PATH entry from User environment.';" ^
    "} else {" ^
    "    Write-Host 'No PATH entry in User environment; skipping.';" ^
    "}" ^
    "[Environment]::SetEnvironmentVariable('ACTIONC_DATA_DIR', $null, 'User');" ^
    "[Environment]::SetEnvironmentVariable('ACTIONC_ACTION2TIDL', $null, 'User');" ^
    "[Environment]::SetEnvironmentVariable('ACTIONC_TIDLC', $null, 'User');"

echo ACTIONC environment variables removed.

echo.
echo =================================================================
echo  Uninstallation complete!
echo  Please restart your terminal or shell session to apply the changes.
echo =================================================================
pause
