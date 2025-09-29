
#!/usr/bin/env python3
"""
EDUCATIONAL SECURITY RESEARCH TOOL
===================================
This module is designed for cybersecurity education and authorized research only.
Unauthorized use is prohibited and may violate applicable laws.

Purpose: Demonstrate process analysis techniques for security research
Usage: Only in authorized lab environments with proper permissions
License: Educational use only - see LICENSE file
"""

import psutil
import ctypes
import sys
import os
from ctypes import wintypes
from typing import List, Dict, Optional

if not os.environ.get('SECURITY_RESEARCH_AUTH'):
    print("WARNING: This is educational security research software.")
    print("Use only in authorized environments with proper permissions.")
    print("Set SECURITY_RESEARCH_AUTH=1 to acknowledge authorized use.")
    if not input("Continue for educational purposes only? (yes/no): ").lower().startswith('y'):
        sys.exit(1)

class ProcessSelector:
    
    def __init__(self):
        self.kernel32 = ctypes.windll.kernel32
        self.ntdll = ctypes.windll.ntdll
        self.target_processes = []
        
    def get_process_integrity_level(self, pid: int) -> str:
        try:
            PROCESS_QUERY_INFORMATION = 0x0400
            handle = self.kernel32.OpenProcess(PROCESS_QUERY_INFORMATION, False, pid)
            if handle:
                self.kernel32.CloseHandle(handle)
                return "Medium"
            return "Unknown"
        except Exception:
            return "Unknown"
    
    def is_process_protected(self, pid: int) -> bool:
        try:
            process = psutil.Process(pid)
            protected_names = [
                'csrss.exe', 'winlogon.exe', 'services.exe', 
                'lsass.exe', 'wininit.exe', 'system'
            ]
            return process.name().lower() in protected_names
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            return True
    
    def get_process_architecture(self, pid: int) -> str:
        try:
            PROCESS_QUERY_INFORMATION = 0x0400
            handle = self.kernel32.OpenProcess(PROCESS_QUERY_INFORMATION, False, pid)
            if not handle:
                return "Unknown"
                
            is_wow64 = ctypes.c_bool()
            self.kernel32.IsWow64Process(handle, ctypes.byref(is_wow64))
            self.kernel32.CloseHandle(handle)
            
            return "32-bit" if is_wow64.value else "64-bit"
        except Exception:
            return "Unknown"
    
    def analyze_process_modules(self, pid: int) -> List[Dict]:
        modules = []
        try:
            process = psutil.Process(pid)
            for dll in process.memory_maps():
                if dll.path and dll.path.endswith('.dll'):
                    modules.append({
                        'name': dll.path.split('\\')[-1],
                        'path': dll.path,
                        'base_address': dll.addr,
                        'size': dll.perms
                    })
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
        return modules
    
    def calculate_injection_score(self, process_info: Dict) -> float:
        score = 0.0
        

        if not process_info['is_protected']:
            score += 30.0
            

        if process_info['integrity_level'] == 'Medium':
            score += 20.0
        elif process_info['integrity_level'] == 'High':
            score += 10.0
            

        if process_info['architecture'] == '64-bit':
            score += 15.0
        else:
            score += 5.0
            

        score += min(len(process_info['modules']) * 0.5, 15.0)
        

        memory_mb = process_info['memory_usage'] / (1024 * 1024)
        if 10 < memory_mb < 500:
            score += 10.0
        elif memory_mb >= 500:
            score += 5.0
            
        return score
    
    def get_target_processes(self, min_score: float = 50.0) -> List[Dict]:
        candidates = []
        
        for process in psutil.process_iter(['pid', 'name', 'memory_info']):
            try:
                pid = process.info['pid']
                if pid <= 4:
                    continue
                    
                process_info = {
                    'pid': pid,
                    'name': process.info['name'],
                    'memory_usage': process.info['memory_info'].rss,
                    'is_protected': self.is_process_protected(pid),
                    'integrity_level': self.get_process_integrity_level(pid),
                    'architecture': self.get_process_architecture(pid),
                    'modules': self.analyze_process_modules(pid)
                }
                

                score = self.calculate_injection_score(process_info)
                process_info['injection_score'] = score
                
                if score >= min_score:
                    candidates.append(process_info)
                    
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue
        

        candidates.sort(key=lambda x: x['injection_score'], reverse=True)
        return candidates
    
    def select_optimal_target(self) -> Optional[Dict]:
        candidates = self.get_target_processes()
        
        if not candidates:
            return None
            

        for candidate in candidates:

            preferred_names = [
                'notepad.exe', 'calc.exe', 'explorer.exe',
                'chrome.exe', 'firefox.exe', 'winword.exe'
            ]
            
            if candidate['name'].lower() in preferred_names:
                return candidate
        

        return candidates[0] if candidates else None
    
    def print_process_analysis(self):
        candidates = self.get_target_processes(min_score=30.0)
        
        print("Process Analysis for Injection Targets:")
        print("=" * 80)
        print(f"{'PID':<8} {'Name':<20} {'Arch':<8} {'Protected':<10} {'Score':<8} {'Memory':<10}")
        print("-" * 80)
        
        for proc in candidates[:15]:
            memory_mb = proc['memory_usage'] / (1024 * 1024)
            print(f"{proc['pid']:<8} {proc['name']:<20} {proc['architecture']:<8} "
                  f"{'Yes' if proc['is_protected'] else 'No':<10} "
                  f"{proc['injection_score']:<8.1f} {memory_mb:<10.1f}")

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--analysis':
        selector = ProcessSelector()
        selector.print_process_analysis()
    else:
        selector = ProcessSelector()
        target = selector.select_optimal_target()
        
        if target:
            print(f"Optimal target selected:")
            print(f"PID: {target['pid']}")
            print(f"Name: {target['name']}")
            print(f"Architecture: {target['architecture']}")
            print(f"Injection Score: {target['injection_score']:.1f}")
            print(f"Modules: {len(target['modules'])}")
        else:
            print("No suitable target process found")
            sys.exit(1)

if __name__ == "__main__":
    main()
