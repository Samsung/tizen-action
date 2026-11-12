@echo off
::
:: Windows Batch installation script for the Tizen Action Compiler.
:: Copies actionc.exe, action2tidl.exe, tidlc.exe, and actionc-sync to %USERPROFILE%\.action-tools
:: The schema data is not shipped with the compiler: actionc-sync fetches it at the end.
::

setlocal enabledelayedexpansion

set "INSTALL_DIR=%USERPROFILE%\.action-tools"

echo === Installing Tizen Action Compiler (Windows 64-bit) ===
echo Target directory: %INSTALL_DIR%

:: --- Create directories and copy files -----------------------------
echo [1/3] Copying binaries and version info...

if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
)

copy /Y "%~dp0bin\windows\*.exe" "%INSTALL_DIR%\" >nul
copy /Y "%~dp0actionc-sync.bat" "%INSTALL_DIR%\" >nul
copy /Y "%~dp0actionc-sync.ps1" "%INSTALL_DIR%\" >nul
copy /Y "%~dp0data-repo.conf" "%INSTALL_DIR%\" >nul
copy /Y "%~dp0VERSION" "%INSTALL_DIR%\" >nul
copy /Y "%~dp0REQUIREMENTS" "%INSTALL_DIR%\" >nul
copy /Y "%~dp0LICENSE" "%INSTALL_DIR%\" >nul

echo Binaries and version info copied.

:: --- Setup Environment Variables persistently via inline powershell ---
echo [2/3] Setting up persistent user environment variables...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$InstallDir = [System.IO.Path]::Combine($env:USERPROFILE, '.action-tools');" ^
    "$DataDir = [System.IO.Path]::Combine($InstallDir, 'data');" ^
    "$UserPath = [Environment]::GetEnvironmentVariable('PATH', 'User');" ^
    "if ($UserPath -notlike '*\.action-tools*') {" ^
    "    [Environment]::SetEnvironmentVariable('PATH', $InstallDir + ';' + $UserPath, 'User');" ^
    "    Write-Host 'Appending PATH setup to User environment...';" ^
    "} else {" ^
    "    Write-Host 'PATH setup already exists in User environment.';" ^
    "}" ^
    "[Environment]::SetEnvironmentVariable('ACTIONC_DATA_DIR', $DataDir, 'User');" ^
    "[Environment]::SetEnvironmentVariable('ACTIONC_ACTION2TIDL', [System.IO.Path]::Combine($InstallDir, 'action2tidl.exe'), 'User');" ^
    "[Environment]::SetEnvironmentVariable('ACTIONC_TIDLC', [System.IO.Path]::Combine($InstallDir, 'tidlc.exe'), 'User');"

echo ACTIONC environment variables set successfully.

:: --- Fetch the schema data -----------------------------------------
:: The schemas are not part of the compiler; actionc-sync fetches the set
:: matching the attached device's tizen-action from the data repository. Best
:: effort: without a device, network, or matching version the install still
:: succeeds, but actionc has nothing to compile until actionc-sync has run
:: (data from an earlier install, if any, is left in place).
echo [3/3] Fetching schema data for the attached device's tizen-action...
call "%INSTALL_DIR%\actionc-sync.bat"
if errorlevel 1 (
    echo warning: schema data not fetched; actionc needs it. Run 'actionc-sync' once a device is attached
    echo          ^(or set DATA_VERSION in %INSTALL_DIR%\data-repo.conf to build without a device^).
)

echo.
echo =================================================================
echo  Installation complete!
echo  Please restart your terminal or shell session to apply the changes.
echo.
echo  Schema data follows the attached device's tizen-action; re-run
echo  'actionc-sync' after switching devices or after a device update.
echo =================================================================
pause
