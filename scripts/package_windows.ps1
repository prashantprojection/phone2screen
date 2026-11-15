[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$Version = '0.5.0'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PubspecPath = Join-Path $RepoRoot 'pubspec.yaml'
$IssPath = Join-Path $RepoRoot 'windows\packaging\phone2screen.iss'
$WebcamScriptPath = Join-Path $RepoRoot 'scripts\setup_windows_webcam.ps1'
$ReleaseDir = Join-Path $RepoRoot 'build\windows\x64\runner\Release'
$DistDir = Join-Path $RepoRoot 'dist'

function Read-PubspecVersion {
    if (Test-Path -LiteralPath $PubspecPath) {
        foreach ($line in (Get-Content -LiteralPath $PubspecPath)) {
            if ($line -match '^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
                return $Matches[1]
            }
        }
    }
    return $null
}

function Find-InnoSetupCompiler {
    $cmd = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'))
    }
    $candidates.Add('C:\Program Files (x86)\Inno Setup 6\ISCC.exe')
    $candidates.Add('C:\Program Files\Inno Setup 6\ISCC.exe')
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Write-Sha256File {
    param([string]$TargetFile)
    $hash = (Get-FileHash -LiteralPath $TargetFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $leaf = Split-Path -Leaf $TargetFile
    $checksumPath = "$TargetFile.sha256"
    "$hash  $leaf" | Set-Content -LiteralPath $checksumPath -Encoding Ascii
    Write-Output "Wrote SHA256: $checksumPath ($hash)"
}

$ResolvedVersion = if ($PSBoundParameters.ContainsKey('Version') -and -not [string]::IsNullOrWhiteSpace($Version)) {
    $Version.Trim()
} else {
    $pubVersion = Read-PubspecVersion
    if ($pubVersion) { $pubVersion } else { $Version.Trim() }
}
Write-Output "Packaging Phone2Screen v$ResolvedVersion for Windows x64..."

if (-not $SkipBuild) {
    Write-Output 'Running flutter build windows --release...'
    Push-Location $RepoRoot
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build windows --release failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}

$ExePath = Join-Path $ReleaseDir 'phone2screen.exe'
$VcamDllPath = Join-Path $ReleaseDir 'p2s_vcam.dll'
if (-not (Test-Path -LiteralPath $ExePath)) {
    throw "Missing Release binary: $ExePath. Run without -SkipBuild first."
}
if (-not (Test-Path -LiteralPath $VcamDllPath)) {
    throw "Missing Virtual Camera DLL: $VcamDllPath. Run without -SkipBuild first."
}
if (-not (Test-Path -LiteralPath $WebcamScriptPath)) {
    throw "Missing setup script: $WebcamScriptPath."
}

New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

$BundleName = "Phone2Screen-v$ResolvedVersion-Windows-x64"
$StageDir = Join-Path $DistDir $BundleName
if (Test-Path -LiteralPath $StageDir) {
    Remove-Item -LiteralPath $StageDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

Copy-Item -Path (Join-Path $ReleaseDir '*') -Destination $StageDir -Recurse -Force
Get-ChildItem -LiteralPath $StageDir -File |
    Where-Object { $_.Extension -in @('.pdb', '.exp', '.lib') } |
    Remove-Item -Force
Copy-Item -LiteralPath $WebcamScriptPath -Destination (Join-Path $StageDir 'setup_windows_webcam.ps1') -Force

$ZipPath = Join-Path $DistDir "$BundleName.zip"
if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}
Compress-Archive -Path (Join-Path $StageDir '*') -DestinationPath $ZipPath -CompressionLevel Optimal -Force
Write-Output "Created portable bundle: $ZipPath"
Write-Sha256File -TargetFile $ZipPath

$IsccPath = Find-InnoSetupCompiler
if ($IsccPath) {
    if (-not (Test-Path -LiteralPath $IssPath)) {
        throw "Missing Inno Setup script: $IssPath."
    }
    $SetupBaseName = "Phone2Screen-Setup-v$ResolvedVersion"
    Write-Output "Building installer with $IsccPath..."
    & $IsccPath "/DAppVersion=$ResolvedVersion" "/O$DistDir" "/F$SetupBaseName" $IssPath
    if ($LASTEXITCODE -ne 0) {
        throw "ISCC.exe failed with exit code $LASTEXITCODE."
    }
    $SetupExePath = Join-Path $DistDir "$SetupBaseName.exe"
    if (Test-Path -LiteralPath $SetupExePath) {
        Write-Output "Created installer: $SetupExePath"
        Write-Sha256File -TargetFile $SetupExePath
    }
} else {
    Write-Output 'Inno Setup 6 (ISCC.exe) not found on PATH or standard install paths; skipped .exe installer build.'
}
