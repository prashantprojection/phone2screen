---
name: verify-phone2screen
description: Verification runbook for Phone2Screen v0.1 with PowerShell checks for the <350-line file cap, banned Flutter Material/Cupertino imports and codegen packages, flutter analyze, flutter test, and flutter build windows --debug.
---

# Verify Phone2Screen

Run all steps from the workspace root (`d:\personal projects\phone2screen`) in Windows PowerShell. Never inspect or modify files outside this directory.

## 1. File Size Cap (`< 350` Lines for `.dart` & `.kt`)

Every `.dart` file in `lib/` and `test/`, plus every `.kt` file in `android/app/src/main/kotlin/`, MUST be strictly under 350 lines:

```powershell
$oversized = Get-ChildItem lib, test, android\app\src\main\kotlin -Recurse -Include *.dart,*.kt -ErrorAction SilentlyContinue |
  ForEach-Object {
    $lines = [System.IO.File]::ReadAllLines($_.FullName).Length
    if ($lines -ge 350) { "$($_.FullName): $lines lines" }
  }
if ($oversized) { $oversized; exit 1 } else { "PASS: all .dart/.kt files < 350 lines" }
```

## 2. Deprecated Import & Zero-Codegen Gate

Confirm zero occurrences of `package:flutter/material.dart`, `package:flutter/cupertino.dart`, `flutter_screenutil`, generated parts (`*.g.dart` / `*.freezed.dart`), or codegen packages (`build_runner`, `freezed`, `json_serializable`, `riverpod_generator`, `mockito`, `pigeon`):

```powershell
$badDart = Get-ChildItem lib, test -Recurse -Filter *.dart -ErrorAction SilentlyContinue |
  Select-String -Pattern 'package:flutter/(material|cupertino)\.dart|flutter_screenutil|part\s+.*\.(g|freezed)\.dart'
$badPub = Select-String -Path pubspec.yaml `
  -Pattern 'build_runner|freezed|json_serializable|riverpod_generator|mockito|pigeon|flutter_screenutil'
if ($badDart -or $badPub) {
  $badDart | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
  $badPub  | ForEach-Object { "pubspec.yaml:$($_.LineNumber): $($_.Line.Trim())" }
  exit 1
} else {
  "PASS: no banned imports or codegen dependencies"
}
```

## 3. Dependency Sync & Static Analysis

Ensure dependencies resolve and static analysis finishes with zero errors, warnings, or lint infos:

```powershell
flutter pub get
flutter analyze --fatal-infos
```

## 4. Unit & Widget Tests

Run the full handwritten test suite:

```powershell
flutter test
```

## 5. Windows Desktop Build Check

Verify the Windows desktop receiver compiles cleanly in debug mode:

```powershell
flutter build windows --debug
```

## 6. Pass Criteria

Report PASS only when all 5 gates exit `0`:
1. Zero `.dart` or `.kt` files `>= 350` lines.
2. Zero banned imports or codegen dependencies.
3. `flutter analyze --fatal-infos` prints `No issues found!`.
4. `flutter test` passes all tests without skipped/relaxed assertions.
5. `flutter build windows --debug` succeeds.
