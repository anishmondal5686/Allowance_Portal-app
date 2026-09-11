# AGENTS.md

## Project
Two Flutter allowance apps for Haldia Dock Complex (Dart):
- `allowance_app` — v1 (legacy, Google Drive sync enabled), package `com.allowance.allowance_app`
- `allowance_app_v2` — v2 (primary, local-only), package `com.allowance.allowance_app_v2`
- `shared` — common Flutter package containing `models/`, `services/` (allowance_calculator, official_forms_service, claim_print_service, theme_store, sun_table, update_service), and `theme/` (modern_theme, app_theme).

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

## Release Rules (CRITICAL: in-app updater depends on asset names)
- `UpdateService.selectAssetsForVariant` matches assets by name:
  - v1 APK must start `allowance_app_v1_` (e.g. `allowance_app_v1_2.0.25-arm64-v8a_RELEASE.apk`)
  - v2 APK must start `allowance_app_v2_` (e.g. `allowance_app_v2_2.0.25-arm64-v8a_RELEASE.apk`)
  - v1 names must NEVER contain the substring `v2` (old installed apps filter by `contains('v1')`/`contains('v2')`)
- Never use a v1 asset name like `allowance_app_v2.0.XX-apk` — it contains `v2` and lacks `v1`, breaking in-app update for both apps.
- **Every release MUST bump BOTH** the `version:` in both `pubspec.yaml` files AND `static const _appVersion` in both `lib/main.dart` to the SAME version string (a stale `_appVersion` causes the in-app updater to re-prompt forever).
- `_checkForUpdate`'s `appVariant` in `dashboard_screen.dart` must stay `'v1'` in `allowance_app` and `'v2'` in `allowance_app_v2`. Never mirror this line between apps.

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

## Document & Binary Handling (.docx, .pdf)
- Spec reference document: `C:\New folder\ADM ALLOWANCE NEW FORM.docx`.
- Never attempt to read raw `.docx` or `.pdf` files directly as binary.
- When referencing or reading the allowance specification document or any PDF:
  1. Use the `markitdown` MCP tool (or execute `python -W ignore -m markitdown "<path>"` via shell) to convert it to clean Markdown.
  2. Parse the extracted Markdown text to inspect allowance rates, rules, or form layouts.

## Architecture Guardrails
- **Shared First:** Any change to allowance calculations, movement models, official form generation, print services, or themes MUST be made in `shared/lib/` only. Never duplicate shared services into app-specific folders.
- **UI Parity:** Any change made to a screen in `allowance_app/lib/screens/` must be mirrored in `allowance_app_v2/lib/screens/` unless it specifically involves Google Drive sync or local-only persistence.
- **v1 vs v2 storage (DO NOT "ALIGN"):** v1's dashboard month history reads/writes `DriveService` (`loadLocalBackup`/`listSavedMonths` → `Allowance App/<userKey>/` subfolder) and shows the Drive Sync card; v2 uses `LocalStore` (documents root) and has no Drive UI. These divergences are intentional — restoring "byte-identical except import" parity here is what broke v1's green ticks. The `dashboard_screen.dart` files legitimately differ in: import, `appVariant` line, `driveService` vs `localStore` param, month-storage calls, and the Drive Sync card.
- **Sequential Builds:** Never trigger concurrent Gradle builds. Always build one package at a time.
