@echo off
rem Lets cmd, and so mise tasks on Windows, find op-run.ps1. See op-run.ps1.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0op-run.ps1" %*
exit /b %ERRORLEVEL%
