@echo off
rem Serves PLaMo 3 Translate on http://127.0.0.1:8077 with llama.cpp. See docs/tools.md.
rem Usage: plamo-server [2b^|8b]. 8b fills almost all of an 8 GB GPU. The first run downloads the model.
rem CORS defaults to every origin, which would let any web page in a browser read the answers.
setlocal
set "size=%~1"
if "%size%"=="" set "size=2b"
mise exec -- llama-server -hf pfnet/plamo-3-translate-%size%-GGUF:Q4_K_M -c 16384 -np 3 -kvu --host 127.0.0.1 --port 8077 --cors-origins localhost --no-cors-credentials --alias plamo-3-translate --jinja --no-prefill-assistant
exit /b %ERRORLEVEL%
