@echo off
title WhatsApp Gateway Server
echo ========================================================
echo Starting WhatsApp Bot Gateway (Baileys)...
echo ========================================================
cd /d "%~dp0whatsapp_server"

echo Checking if port 3000 is in use...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }" >nul 2>&1

where node >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Node.js is not installed or not found in system PATH.
    echo Please install Node.js from https://nodejs.org/
    echo.
    pause
    exit /b 1
)

echo Starting Node Gateway server on port 3000...
node server.js
pause
