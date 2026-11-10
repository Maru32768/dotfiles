@echo off
rem Lets cmd, and so mise tasks on Windows, find bws-run.ps1. See bws-run.ps1.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0bws-run.ps1" %*
exit /b %ERRORLEVEL%
