# AGENTS.md

## Project
Two near-identical Flutter allowance apps (Dart). Changes are almost always mirrored in **both** apps.

- `allowance_app` — v1 (legacy), APK ~58MB
- `allowance_app_v2` — v2 (primary, used on the emulator), APK ~56MB, package `com.allowance.allowance_app_v2`

Each app holds its own copy of models, screens, services, and tests. When changing behavior, apply the same edit to `lib/` and the same test to `test/` in both apps unless told otherwise.

## Tooling
- Flutter: `C:\flutter\bin\flutter.bat` (run via call operator: `& "C:\flutter\bin\flutter.bat" ...`).
- adb: `C:\Users\way2m\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- Emulator: `Pixel_6_API_35`.
- APK output: `build\app\outputs\flutter-apk\app-release.apk` (per app).
- Verify PDFs with PyMuPDF: `python -X utf8 -c "import fitz; ..."`.

## Verify
Run analyze + tests in each app directory (`C:\Users\way2m\OneDrive\Documents\Default Project\<app>`):
- `& "C:\flutter\bin\flutter.bat" analyze`
- `& "C:\flutter\bin\flutter.bat" test`

Use the project `/verify` command.

## Gotchas
- v1 stores Devanagari as literal UTF-8 bytes; PowerShell `Get-Content` misreads it (ANSI). Always read/verify via `[System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes(<path>))`, or the Read tool.
- Emulator UI: dismiss the keyboard (`adb shell input keyevent 4`) before tapping buttons; taps can otherwise land on keyboard keys.
- The spec is `C:\New folder\ADM ALLOWANCE NEW FORM.docx`. Running session notes: `C:\Users\way2m\AppData\Local\Temp\opencode\SESSION_SUMMARY.md` — update it with each completed session so work can be resumed.
