[CmdletBinding()]
param(
    [ValidateSet('Register', 'Unregister', 'Status')]
    [string]$Action = 'Register',
    [string]$DllPath = '',
    [switch]$AddFirewallRules
)

$ErrorActionPreference = 'Stop'

$VcamClsid = '{D8E4A2F1-7B3C-4E9A-9C1D-5F2A8B6E4C10}'
$DsVideoInputCat = '{860BB310-5D01-11D0-BD3B-00A0C911CE86}'
$ClsidKey = "HKCU:\Software\Classes\CLSID\$VcamClsid"
$InprocKey = "$ClsidKey\InprocServer32"
$DsInstanceKey = "HKCU:\Software\Classes\CLSID\$DsVideoInputCat\Instance\$VcamClsid"
$FwUdpRule = 'Phone2Screen LAN Discovery UDP 41234'
$FwTcpRule = 'Phone2Screen Signaling TCP 8080-8443'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-VCamDllPath {
    param([string]$ExplicitPath)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath) {
            return (Resolve-Path -LiteralPath $ExplicitPath).Path
        }
        return $ExplicitPath
    }
    $candidates = @(
        (Join-Path $PSScriptRoot 'p2s_vcam.dll'),
        (Join-Path $RepoRoot 'build\windows\x64\runner\Release\p2s_vcam.dll'),
        (Join-Path $RepoRoot 'build\windows\x64\runner\Debug\p2s_vcam.dll')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Invoke-RegSvr32 {
    param([string[]]$Arguments)
    $regsvr = Join-Path $env:SystemRoot 'System32\regsvr32.exe'
    $proc = Start-Process -FilePath $regsvr -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    return $proc.ExitCode
}

function Add-Phone2ScreenFirewallRules {
    if (-not (Test-IsAdmin)) {
        Write-Output 'Note: -AddFirewallRules requires an elevated (Administrator) PowerShell session. Re-run as Administrator to configure Windows Firewall rules (UDP 41234, TCP 8080-8083, 8443).'
        return
    }
    Remove-NetFirewallRule -DisplayName $FwUdpRule, $FwTcpRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $FwUdpRule -Direction Inbound -Action Allow -Protocol UDP -LocalPort '41234' -Profile @('Private', 'Domain') | Out-Null
    New-NetFirewallRule -DisplayName $FwTcpRule -Direction Inbound -Action Allow -Protocol TCP -LocalPort @('8080-8083', '8443') -Profile @('Private', 'Domain') | Out-Null
    Write-Output "Added Windows Firewall rules: '$FwUdpRule' and '$FwTcpRule'."
}

function Remove-Phone2ScreenFirewallRules {
    if (-not (Test-IsAdmin)) {
        try {
            $existing = Get-NetFirewallRule -DisplayName $FwUdpRule, $FwTcpRule -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Output 'Note: Existing Phone2Screen Windows Firewall rules were kept because this session is not elevated.'
            }
        } catch {
            # Ignore if NetSecurity module is unavailable in current shell.
        }
        return
    }
    Remove-NetFirewallRule -DisplayName $FwUdpRule, $FwTcpRule -ErrorAction SilentlyContinue
    Write-Output 'Removed Phone2Screen Windows Firewall rules (if present).'
}

function Show-VCamStatus {
    $clsidExists = Test-Path -LiteralPath $ClsidKey
    $dsExists = Test-Path -LiteralPath $DsInstanceKey
    $inproc = ''
    if (Test-Path -LiteralPath $InprocKey) {
        $inproc = [string](Get-Item -LiteralPath $InprocKey).GetValue('')
    }
    $existsOnDisk = (-not [string]::IsNullOrWhiteSpace($inproc)) -and (Test-Path -LiteralPath $inproc)
    $registered = $clsidExists -and $dsExists -and $existsOnDisk

    Write-Output "FriendlyName: Phone2Screen Camera"
    Write-Output "Registered: $registered"
    Write-Output "InprocServer32: $(if ($inproc) { $inproc } else { '<not set>' })"
    Write-Output "ExistsOnDisk: $existsOnDisk"
    Write-Output "DirectShowInstance: $dsExists"
}

switch ($Action) {
    'Register' {
        $resolvedDll = Resolve-VCamDllPath -ExplicitPath $DllPath
        if (-not $resolvedDll -or -not (Test-Path -LiteralPath $resolvedDll)) {
            throw "Could not locate p2s_vcam.dll. Build Windows runner or pass -DllPath <path-to-p2s_vcam.dll>."
        }
        $exitCode = Invoke-RegSvr32 -Arguments @('/s', "`"$resolvedDll`"")
        if ($exitCode -ne 0) {
            throw "regsvr32.exe /s failed with exit code $exitCode for $resolvedDll"
        }
        if (-not (Test-Path -LiteralPath $ClsidKey)) {
            throw "Registration check failed: expected key $ClsidKey was not created."
        }
        Write-Output "Registered 'Phone2Screen Camera' (HKCU) -> $resolvedDll"
        if ($AddFirewallRules) {
            Add-Phone2ScreenFirewallRules
        }
        Show-VCamStatus
    }
    'Unregister' {
        $resolvedDll = Resolve-VCamDllPath -ExplicitPath $DllPath
        if ($resolvedDll -and (Test-Path -LiteralPath $resolvedDll)) {
            $exitCode = Invoke-RegSvr32 -Arguments @('/u', '/s', "`"$resolvedDll`"")
            if ($exitCode -ne 0) {
                Write-Warning "regsvr32.exe /u /s exited with code $exitCode; cleaning HKCU keys directly."
            }
        }
        foreach ($key in @($DsInstanceKey, $ClsidKey)) {
            if (Test-Path -LiteralPath $key) {
                Remove-Item -LiteralPath $key -Recurse -Force
            }
        }
        Write-Output "Unregistered 'Phone2Screen Camera' from HKCU."
        Remove-Phone2ScreenFirewallRules
    }
    'Status' {
        Show-VCamStatus
    }
}
