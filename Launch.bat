@echo off
rem Starts the editor without a console window (conhost --headless), preferring PowerShell 7.
cd /d "%~dp0"

where pwsh >nul 2>nul
if %errorlevel% equ 0 (
    start "" conhost.exe --headless pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0ContextMenuEditor.ps1"
) else (
    start "" conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0ContextMenuEditor.ps1"
)
exit
