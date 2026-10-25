@echo off
rem Spusti lokalni DNS forwarder pro Apex / EA Javelin (viz apex-dns-forwarder.ps1). Okno nech otevrene, dokud hrajes.
cd /d "%~dp0"
where pwsh >nul 2>&1 && (pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0apex-dns-forwarder.ps1") || (powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apex-dns-forwarder.ps1")
