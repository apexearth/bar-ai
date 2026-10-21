@echo off
setlocal
title Install @NAME@ for Beyond All Reason
if not exist "%~dp0payload\install.ps1" (
  echo.
  echo  The installer files are missing next to this .bat.
  echo  Close this window, right-click the downloaded .zip, choose "Extract All...",
  echo  then double-click Install.bat inside the extracted folder.
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0payload\install.ps1" %*
set rc=%ERRORLEVEL%
echo.
pause
exit /b %rc%
