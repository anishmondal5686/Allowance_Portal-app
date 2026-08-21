# AGENTS.md

## Project
Two Flutter allowance apps for Haldia Dock Complex (Dart):
- `allowance_app` — v1 (legacy, Google Drive sync enabled), package `com.allowance.allowance_app`
- `allowance_app_v2` — v2 (primary, local-only), package `com.allowance.allowance_app_v2`
- `shared` — common Flutter package containing `models/`, `services/` (allowance_calculator, official_forms_service, claim_print_service, theme_store, sun_table), and `theme/` (modern_theme, app_theme).

UI screens (`lib/screens/`) and app entry (`lib/main.dart`) remain per-app. Domain model/service changes are edited **only once** in `shared/lib/` and automatically apply to both apps. Screen UI changes are mirrored in both apps.

## Shared Package (`shared/`)
Contains:
- `models/`: `claim_data.dart`, `master_data.dart`, `movement.dart`
- `services/`: `allowance_calculator.dart`, `official_forms_service.dart`, `claim_print_service.dart`, `theme_store.dart`, `sun_table.dart`
- `theme/`: `modern_theme.dart`, `app_theme.dart`
- Assets: `assets/fonts/` (Noto Sans Devanagari)

App-specific services stay local:
- `allowance_app`: `lib/services/drive_service.dart`
- `allowance_app_v2`: `lib/services/local_store.dart`

## Tooling
- Flutter: `C:\flutter\bin\flutter.bat` (run via call operator: `& "C:\flutter\bin\flutter.bat" ...`).
- adb: `C:\Users\way2m\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- Emulator: `Pixel_6_API_35`.
- Release Keystore: `android/app/release.jks` in both apps (alias `release`, pass `Allowance@2026`). Keystore backup at `Desktop\allowance_apks\keystore\`.
- APK output: `build\app\outputs\flutter-apk\app-release.apk` (or `--split-per-abi` → `app-arm64-v8a-release.apk`).
- Verify PDFs with PyMuPDF: `python -X utf8 -c "import fitz; ..."`.

## Build Commands
Run builds sequentially (Gradle daemons collide if run in parallel):
- `& "C:\flutter\bin\flutter.bat" build apk --release --split-per-abi`

## Verify
Run analyze + tests across all 3 packages:
- `shared`: `& "C:\flutter\bin\flutter.bat" analyze`
- `allowance_app`: `& "C:\flutter\bin\flutter.bat" analyze` && `& "C:\flutter\bin\flutter.bat" test`
- `allowance_app_v2`: `& "C:\flutter\bin\flutter.bat" analyze` && `& "C:\flutter\bin\flutter.bat" test`

Use the project `/verify` command.

## Gotchas
- Devanagari UTF-8: PowerShell `Get-Content` misreads Devanagari bytes as ANSI. Read via `[System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes(<path>))`, or the Read tool.
- Emulator UI: dismiss keyboard (`adb shell input keyevent 4`) before tapping buttons; taps can otherwise land on keyboard keys.
- Spec doc: `C:\New folder\ADM ALLOWANCE NEW FORM.docx`.
- Session notes: `C:\Users\way2m\AppData\Local\Temp\opencode\SESSION_SUMMARY.md` — update with completed work.
- Git: root repo tracks all 3 packages (`shared`, `allowance_app`, `allowance_app_v2`). Always run tests before committing.
