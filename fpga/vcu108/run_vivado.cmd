@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_vivado.ps1" %*
exit /b %ERRORLEVEL%
