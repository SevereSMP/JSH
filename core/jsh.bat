@echo off
rem jsh - JSON toolkit for cmd. Keep jsh.ps1 in the same folder as this file.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0jsh.ps1" %*
exit /b %ERRORLEVEL%
