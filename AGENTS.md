# AGENTS.md

## Project
Two Flutter allowance apps for Haldia Dock Complex (Dart):
- `allowance_app_v2` — v2 (**the sole app going forward**, Drive sync since 2.0.38), package `com.allowance.allowance_app_v2`
- `allowance_app` — v1 (**FROZEN at 2.0.38 — final release, no further versions**), package `com.allowance.allowance_app`. Kept only as a migration vehicle; its in-app updater pushed 2.0.38 as the last update.
- `shared` — common Flutter package containing `models/`, `services/` (allowance_calculator, official_forms_service, claim_print_service, theme_store, sun_table, update_service), and `theme/` (modern_theme, app_theme).

UI screens (`lib/screens/`) and app entry (`lib/main.dart`) remain per-app. Domain model/service changes are edited **only once** in `shared/lib/` and automatically apply to both apps. Screen UI changes are mirrored in both apps.

**Do NOT rewrite in Kotlin/Jetpack Compose.** Assessed 2026-10-20: ~14.6k Dart + ~7.8k test lines, 4–6 FTE-weeks, PDF pixel-perfection hardest. Stay on Flutter.

## Shared Package (`shared/`)
Contains:
- `models/`: `claim_data.dart`, `master_data.dart`, `movement.dart`
- `services/`: `allowance_calculator.dart`, `official_forms_service.dart`, `claim_print_service.dart`, `theme_store.dart`, `sun_table.dart`
- `theme/`: `modern_theme.dart`, `app_theme.dart`
- Assets: `assets/fonts/` (Noto Sans Devanagari)

App-specific services stay local:
- `allowance_app`: `lib/services/drive_service.dart`
- `allowance_app_v2`: `lib/services/drive_service.dart` (port of v1's + reconcile/migration additions; `local_store.dart` was DELETED in 2.0.38)

## Tooling
- Flutter: `C:\flutter\bin\flutter.bat` (run via call operator: `& "C:\flutter\bin\flutter.bat" ...`).
- adb: `C:\Users\way2m\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- Emulator: `Pixel_6_API_35`.
- Release Keystore: `android/app/release.jks` in both apps (alias `release`). Password is NOT recorded here — read it from `C:\keystore-backup\READ_ME.txt`. Keystore backup at `C:\keystore-backup\` (kept off the Desktop on purpose, so a OneDrive Desktop backup can never sweep it up).
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
- **Every release MUST bump BOTH** the `version:` in both `pubspec.yaml` files AND `static const _appVersion` in both `lib/main.dart` to the SAME version string (a stale `_appVersion` causes the in-app updater to re-prompt forever). v1 is frozen at 2.0.38 — if another dual release ever happens anyway, keep the rule.
- `_checkForUpdate`'s `appVariant` in `dashboard_screen.dart` must stay `'v1'` in `allowance_app` and `'v2'` in `allowance_app_v2`. Never mirror this line between apps.
- OAuth Android clients live in the same GCP project as web client `486404217110-vc0k0…` (v1's project — the `serverClientId` both apps use): `com.allowance.allowance_app_v2` with release SHA-1 `21:30:FA:16:8D:D7:83:EB:93:0F:CC:66:72:8C:54:69:EB:C3:18:02` and debug SHA-1 `D4:2D:F5:47:04:3A:79:45:1E:73:E7:FE:41:2E:81:9E:5B:74:FE:C3` (registered 2026-10-20; verified live). Missing/wrong entries surface as `ApiException: 10` (DEVELOPER_ERROR) AFTER the account picker — the picker itself is client-side and shows regardless.

## Verify
Run analyze + tests across all 3 packages:
- `shared`: `& "C:\flutter\bin\flutter.bat" analyze`
- `allowance_app`: `& "C:\flutter\bin\flutter.bat" analyze` && `& "C:\flutter\bin\flutter.bat" test`
- `allowance_app_v2`: `& "C:\flutter\bin\flutter.bat" analyze` && `& "C:\flutter\bin\flutter.bat" test`

Use the project `/verify` command.

## Dependency Pins (verified blockers — do NOT bump without testing)
- `flutter_form_builder` `^10.2.0` (11.x pulls `material_ui`/`cupertino_ui`, breaks `InputDecoration` types).
- `pdfx` `>=2.9.2 <2.11.0` (2.11.0 breaks Android build — plugin class renamed; `GeneratedPluginRegistrant` references the missing `io.scer.pdfx.PdfxPlugin`).
- `share_plus` `12.0.0` exact in all 3 pubspecs: **13.x broken on Android builds** — 13.3.0 fails `:share_plus:compileDebugKotlin` (unresolved `SharePlusPendingIntent`, regression from #3931) and 13.2.1 fails `:app:compileDebugJavaWithJavac` (`SharePlusPlugin` never compiled into app classpath).
- `file_picker` `11.0.3` exact: **13.1.0 needs `windows_file_picker 2.0.0` → `win32 ^6.3.0`, incompatible with `share_plus 12`'s `win32 ^5.5.3`, AND a `win32: ^6.4.0` override breaks `share_plus 12`'s Dart (`wReserved` getter removed from `OSVERSIONINFOEX`)**. Cannot coexist — keep both pinned; `pubspec.lock` is gitignored so `pub upgrade` does not show a conflict.
- Google stack in BOTH app pubspecs since 2.0.38, caret-constrained (`google_sign_in ^6.2.2`, `googleapis ^13.2.0`, `googleapis_auth ^1.6.0`, (`http ^1.2.2` pulled in)). Majors 7.2.0/17.0.0/2.3.4 are API-breaking; built against the 6.x surface — do not bump. (v1 Drive sync is personal-critical; v2 runs the identical service, and v1 is frozen anyway.)
- `dynamic_color` `^1.7.0` in both app pubspecs (resolves 1.9.0; 2.x is a different major and untested). Backs `ModernThemeId.modernDynamic` — `DynamicColorBuilder` in each `main.dart` feeds the wallpaper palette to `ModernThemeData.buildModern`, which falls back to the id's seed when the platform has none.
- Dashboard redesign deps (both app pubspecs only, never `shared`): `lucide_icons_flutter` `^3.1.22`, `figma_squircle` `^0.6.3`, `google_fonts` `^9.0.0`. **Do NOT use `lucide_icons` `0.257.0`** — it `extends IconData`, which is a final class on current Flutter, so every widget test fails to compile (`flutter analyze` still passes, so tests are the gate). Poppins via `google_fonts` is display-text only (hero/KPI/sun/headers); the global `fontFamily` stays `'Noto Sans Devanagari'`.
- Safe to upgrade via `flutter pub upgrade` (verified on Flutter 3.47.5): pdf, printing, image, mime, archive, dbus — analyzed + full test suites green after.

## Gotchas
- Devanagari UTF-8: PowerShell `Get-Content` misreads Devanagari bytes as ANSI. Read via `[System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes(<path>))`, or the Read tool.
- Emulator UI: dismiss keyboard (`adb shell input keyevent 4`) before tapping buttons; taps can otherwise land on keyboard keys.
- Android documents root (path_provider `getApplicationDocumentsDirectory()`) = `/data/user/0/<pkg>/app_flutter` (emulator-verified). The `files/` dir holds only support data (google_fonts `Poppins_700_*.ttf` cache, `profileInstalled` marker) — never plant month files there.
- Month filenames are UPPERCASE: `monthFileName` derives from UPPERCASE `monthNames` (e.g. `SEPTEMBER2026.json`), while `monthKeyFromFileName` is case-insensitive; test fixtures must use exactly the UPPERCASE names.
- Emulator data QA: `flutter run` on a fresh install can wipe app data — prefer `flutter build apk --debug` + `adb install -r`; use `pm clear` (keeps install) for controlled replants. `run-as` shell cannot write to the data root ("Read-only file system") though the app's own Dart code can write `app_flutter/`; plant fixtures via `run-as <pkg> sh -c "base64 -d /data/local/tmp/x.b64 > app_flutter/X.json"`.
- Spec doc: `C:\New folder\ADM ALLOWANCE NEW FORM.docx`.
- Session notes: `C:\Users\way2m\AppData\Local\Temp\opencode\SESSION_SUMMARY.md` — update with completed work.
- Git: root repo tracks all 3 packages (`shared`, `allowance_app`, `allowance_app_v2`). Always run tests before committing.
- The dashboard is the app's **root route**. `PopScope(canPop: false)` does not stop Android back from closing the app: `maybePop` reports nothing to pop, so `handlePopRoute` falls through to `SystemNavigator.pop()` (see `binding.dart`). Back therefore **flushes pending edits first** (`_flushPendingSave`: debounced 2s master auto-commit + `didChangeAppLifecycleState` pause flush, both apps; v1 additionally schedules a 30s-debounced Drive auto-upload when signed in) and then calls `SystemNavigator.pop()` itself — `Navigator.pop()` is a no-op there. There is no Save/Discard prompt anymore (removed when auto-save landed; pop-scope + month-change tests assert flush-and-exit). Tests must assert on a recorded `SystemChannels.platform` `SystemNavigator.pop` call, not on route removal.
- `FormBuilderState.value` is `{}` until `save()`/`saveAndValidate()` runs, so it cannot be used to diff a form against stored data. Unsaved-state tracking relies on `FormBuilder.onChanged` instead (`_onMasterChanged` arms the auto-commit; `_suppressDirty` around programmatic `patchValue`). Explicit Save still uses `saveAndValidate`; the auto-commit path stores raw values via `_masterFromForm()`.

## Document & Binary Handling (.docx, .pdf)
- Spec reference document: `C:\New folder\ADM ALLOWANCE NEW FORM.docx`.
- Never attempt to read raw `.docx` or `.pdf` files directly as binary.
- When referencing or reading the allowance specification document or any PDF:
  1. Use the `markitdown` MCP tool (or execute `python -W ignore -m markitdown "<path>"` via shell) to convert it to clean Markdown.
  2. Parse the extracted Markdown text to inspect allowance rates, rules, or form layouts.

## Architecture Guardrails
- **Shared First:** Any change to allowance calculations, movement models, official form generation, print services, or themes MUST be made in `shared/lib/` only. Never duplicate shared services into app-specific folders.
- **UI Parity:** Any change made to a screen in `allowance_app/lib/screens/` must be mirrored in `allowance_app_v2/lib/screens/` unless it specifically involves Google Drive sync or local-only persistence.
- **v1 vs v2 storage (permanently divergent — never homogenize):** since 2.0.38 both apps use the same `DriveService`-shaped storage API (`loadLocalBackup`/`listSavedMonths` → `Allowance App/<userKey>/` subfolder), but the two `dashboard_screen.dart` files intentionally differ in: import, `appVariant` line (`'v1'`/`'v2'`), month-storage call sites, and the Drive card + sign-in/reconcile flow. v2's dashboard is the canonical, device-verified implementation (fresh install → migrate-or-download, established → upload, both → timestamped reconcile with conflict backups); v1's is frozen with only the incident guard backported. Do not "modernize" one toward the other.
- **Data-loss invariants (apply to any future Drive code):** resolve month conflicts by timestamp and preserve the losing copy as an `<Month><Year> backup YYYY-MM-DD HHmm.json` file (invisible to `monthKeyFromFileName`); write the conflict backup BEFORE any destructive download/fetch; migrations and conflict handling copy, never move or delete; never bulk-upload months on an account whose Drive already holds real data.
- **Sequential Builds:** Never trigger concurrent Gradle builds. Always build one package at a time.
