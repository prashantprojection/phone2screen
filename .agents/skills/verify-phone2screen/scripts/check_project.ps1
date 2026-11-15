param(
    [string[]]$TargetDirs = @('lib', 'test')
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$MaxLines = 350
$Violations = [System.Collections.Generic.List[string]]::new()

$ExpandedDirs = $TargetDirs | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

# Resolve target directories relative to repository root
$DartFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($RelDir in $ExpandedDirs) {
    $FullDir = Join-Path $RepoRoot $RelDir
    if (Test-Path -LiteralPath $FullDir) {
        $Found = Get-ChildItem -LiteralPath $FullDir -Recurse -File -Filter '*.dart'
        foreach ($File in $Found) {
            $DartFiles.Add($File)
        }
    } else {
        $Violations.Add("[MISSING DIR] $RelDir does not exist")
    }
}

if ($DartFiles.Count -eq 0) {
    $Violations.Add("[NO FILES] No .dart files found under: $($ExpandedDirs -join ', ')")
}

$ForbiddenCodeGenPattern = '\b(build_runner|freezed|json_serializable|riverpod_annotation)\b'
$GeneratedPartPattern = "part\s+['""][^'""]+\.g\.dart['""]"
$ForbiddenImportPattern = "^\s*import\s+['""]package:(flutter/material\.dart|flutter_screenutil\b)"

foreach ($File in $DartFiles) {
    $RelPath = $File.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')
    $Lines = @(Get-Content -LiteralPath $File.FullName)

    # 1) Max 350 lines per Dart file
    if ($Lines.Count -gt $MaxLines) {
        $Violations.Add("[LOC > $MaxLines] $RelPath has $($Lines.Count) lines")
    }

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $LineNo = $i + 1
        $Line = $Lines[$i]

        # 2) Forbidden imports: package:flutter/material.dart or package:flutter_screenutil
        if ($Line -match $ForbiddenImportPattern) {
            $Violations.Add("[FORBIDDEN IMPORT] ${RelPath}:$LineNo -> $($Line.Trim())")
        }

        # 3) Forbidden code-gen references or *.g.dart parts
        if ($Line -match $ForbiddenCodeGenPattern -or $Line -match $GeneratedPartPattern) {
            $Violations.Add("[FORBIDDEN CODEGEN] ${RelPath}:$LineNo -> $($Line.Trim())")
        }
    }
}

# 3b) Check pubspec.yaml for forbidden code-gen or flutter_screenutil packages
$PubspecPath = Join-Path $RepoRoot 'pubspec.yaml'
if (Test-Path -LiteralPath $PubspecPath) {
    $PubLines = @(Get-Content -LiteralPath $PubspecPath)
    for ($i = 0; $i -lt $PubLines.Count; $i++) {
        $LineNo = $i + 1
        $Line = $PubLines[$i]
        $CodeOnly = ($Line -split '#', 2)[0]
        if ($CodeOnly -match $ForbiddenCodeGenPattern -or $CodeOnly -match $GeneratedPartPattern) {
            $Violations.Add("[FORBIDDEN CODEGEN] pubspec.yaml:$LineNo -> $($Line.Trim())")
        }
    }
}

if ($Violations.Count -gt 0) {
    Write-Host "check_project.ps1 FAILED with $($Violations.Count) violation(s):" -ForegroundColor Red
    foreach ($V in $Violations) {
        Write-Host "  - $V" -ForegroundColor Red
    }
    exit 1
}

Write-Host "check_project.ps1 PASSED ($($DartFiles.Count) Dart file(s) checked)." -ForegroundColor Green
exit 0
