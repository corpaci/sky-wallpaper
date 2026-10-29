@echo off
rem Double-click to install the sky wallpaper. It asks for your town.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
