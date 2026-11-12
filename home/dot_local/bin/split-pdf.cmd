@echo off
rem Windows has no shebang: run split-pdf (a uv script) through uv. See split-pdf.
uv run --quiet --script "%~dp0split-pdf" %*
exit /b %ERRORLEVEL%
