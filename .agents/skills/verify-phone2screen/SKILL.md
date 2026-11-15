---
name: verify-phone2screen
description: Verification runbook for Phone2Screen v0.3 with PowerShell checks for the <350-line file cap (.dart/.kt/.cpp/.h), banned Flutter Material/Cupertino/private-window imports and codegen packages, flutter analyze, flutter test, and flutter build windows --debug (including StudioBridge Win32 C++).
---

# Verify Phone2Screen (v0.3)

Run all steps from the workspace root (`d:\personal projects\phone2screen`) in Windows PowerShell. Never inspect, scan, or modify files outside this directory (test temporary files MUST reside under `.dart_tool/test_tmp_*` inside the workspace and be removed in `addTearDown`).

## Gate 1: File Size Cap (`< 350` Lines for `.dart`, `.kt`, `.cpp` & `.h`)

Every `.dart` file in `lib/` and `test/`, every `.kt` file in `android/app/src/main/kotlin/`, and every `.cpp`/`.h` file in `windows/runner/` MUST be strictly under 350 lines (`>= 350` fails):

```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/verify-phone2screen/scripts/check_project.ps1
$oversized = Get-ChildItem lib, test, android\app\src\main\kotlin, windows\runner -Recurse -Include *.dart,*.kt,*.cpp,*.h -ErrorAction SilentlyContinue |
  ForEach-Object {
    $lines = [System.IO.File]::ReadAllLines($_.FullName).Length
    if ($lines -ge 350) { "$($_.FullName): $lines lines" }
  }
if ($oversized) { $oversized; exit 1 } else { "PASS: all .dart/.kt/.cpp/.h files < 350 lines" }
```

## Gate 2: Banned Import & Zero-Codegen Scan

Confirm zero occurrences of `package:flutter/material.dart`, `package:flutter/cupertino.dart`, `package:flutter/src/widgets/_window.dart`, `flutter_screenutil`, `Directory.systemTemp`, generated parts (`*.g.dart` / `*.freezed.dart`), or codegen packages (`build_runner`, `freezed`, `json_serializable`, `riverpod_generator`, `riverpod_annotation`, `mockito`, `pigeon`):

```powershell
$badDart = Get-ChildItem lib, test -Recurse -Filter *.dart -ErrorAction SilentlyContinue |
  Select-String -Pattern 'package:flutter/(material|cupertino)\.dart|package:flutter/src/widgets/_window\.dart|flutter_screenutil|Directory\.systemTemp|part\s+.*\.(g|freezed)\.dart'
$badPub = Select-String -Path pubspec.yaml `
  -Pattern 'build_runner|freezed|json_serializable|riverpod_generator|riverpod_annotation|mockito|pigeon|flutter_screenutil'
if ($badDart -or $badPub) {
  $badDart | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
  $badPub  | ForEach-Object { "pubspec.yaml:$($_.LineNumber): $($_.Line.Trim())" }
  exit 1
} else {
  "PASS: no banned imports, private window APIs, systemTemp, or codegen dependencies"
}
```

## Gate 3: Dependency Sync & Static Analysis

Ensure dependencies resolve and static analysis finishes with zero errors, warnings, or lint infos:

```powershell
flutter pub get
flutter analyze --fatal-infos
```

## Gate 4: Unit & Widget Tests

Run the full handwritten unit, loopback HTTP/WS, OBS WebSocket v5, USB bridge, audio/Windows studio, multi-cam, and widget test suite (including `v3_win_usb_audio_test.dart` and `v3_streamer_pro_test.dart`):

```powershell
flutter test
```

## Gate 5: Windows Desktop Build Check

Verify the Windows desktop multi-window receiver and native Win32 C++ `StudioBridge` (`/W4 /WX`, `_HAS_EXCEPTIONS=0`, DirectShow/WaveOut) compile cleanly in debug mode (`build\windows\x64\runner\Debug\phone2screen.exe`):

```powershell
flutter build windows --debug
```

## Pass Criteria

Report PASS only when all 5 gates exit `0`:
1. Zero `.dart`, `.kt`, `.cpp`, or `.h` files `>= 350` lines.
2. Zero banned imports, private window imports, `Directory.systemTemp` usage, or codegen dependencies.
3. `flutter pub get` and `flutter analyze --fatal-infos` print `No issues found!`.
4. `flutter test` passes 100% of tests with zero overflow errors or pending timers.
5. `flutter build windows --debug` produces `build\windows\x64\runner\Debug\phone2screen.exe`.
