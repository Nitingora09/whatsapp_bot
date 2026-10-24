@echo off
title WhatsApp Gateway Server
echo ========================================================
echo Starting WhatsApp Bot Gateway (Baileys)...
echo ========================================================
cd /d "%~dp0whatsapp_server"

for /f "tokens=5" %%a in ('netstat -aon ^| findstr :3000 ^| findstr LISTENING') do (
    echo Freeing port 3000 (PID %%a)...
    taskkill /F /PID %%a >nul 2>&1
)

node server.js
pause
