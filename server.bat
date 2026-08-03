@echo off
rem Starts the LTD game server (ws://:8765) and the web-build server (http://:8080),
rem each in its own console window so you can watch both logs.
cd /d "%~dp0server"
start "LTD Game Server (port 8765)" cmd /k node server.js
start "LTD Web Server (port 8080)" cmd /k node serve-web.js
