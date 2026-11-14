@echo off
rem Windows has no shebang: run usage-log (a uv script) through uv. See usage-log.
uv run --quiet --script "%~dp0usage-log" %*
exit /b %ERRORLEVEL%
