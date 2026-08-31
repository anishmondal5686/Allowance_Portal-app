# Allowance Portal

A Flutter app for claiming marine allowances of **Haldia Dock Complex** (Haldia, West Bengal, India).

## Apps

| App | Package | Purpose |
|-----|---------|---------|
| `allowance_app_v2` | `com.allowance.allowance_app_v2` | Current, distributed local-only app |
| `shared` | `allowance_shared` | Common package: models, services, and theming |

Domain logic (models, the allowance calculator, official-forms and claim-print services, theme, and in-app update service) lives **once** in `shared/lib/` and applies to the app. Screen UI and app entry point remain in the app.

## Features

- **Movement register** — entry of each ship movement (vessel, date/time, berth, length, beam, allowance types and navigation sub-types) with auto-detection for Berthing Pilots.
- **Allowance calculation** — `AllowanceCalculator` computes length, cold movement, night act, lock to approach jetty, night navigation, and night weightage for Dock/Berthing Pilots and Assistant Dock Masters, including:
  - **Acting-ADM duty**: movements on chosen acting dates are billed at ADM rates and shown in a separate "Acting ADM Allowances" section.
  - **Post-midnight shift attribution** for movements that start after midnight.
  - **Night-shift weightage** based on confirmed attendance and roster prediction.
- **Attendance & roster** — mark daily shifts (`N`/`E`/`M`/`OFF`), with future dates predicted from an off-day anchored rotation pattern.
- **Official forms** — print official PDFs (length & cold, night act & weightage, lock to approach jetty, night navigation) with per-designation footers (incl. Asst. Dock Master signature) and continuous serial numbering across pages.
- **Claim summary printout** — an Excel-style "Calculation Sheet of Marine Allowances" (ADM or DP/BP table, plus Acting ADM table when applicable) with a compact per-allowance `SUMMARY` line and `GRAND TOTAL`.
- **In-app updates** — checks GitHub releases on launch and installs the matching APK.
- **Theming** — modern theme with Noto Sans Devanagari font support.

## Releases

Prebuilt APKs are published as GitHub releases. The latest release includes `allowance_app_v2_RELEASE.apk`.

## Tech Stack

- Flutter / Dart
- `pdf` + `printing` for PDF generation and printing
- `path_provider`, `file_picker`, `share_plus` for files
- In-app update + install via a platform channel (`MainActivity.kt`)

## Project Structure

```
allowance_app_v2/    # app (local-only)
shared/              # shared models, services, theme, fonts
  lib/
    models/          # claim_data, master_data, movement
    services/        # allowance_calculator, official_forms_service,
                     # claim_print_service, theme_store, sun_table, update_service
    theme/           # modern_theme, app_theme
```

## Development

The app depends on `shared` via a path dependency, so domain/service changes are edited in `shared/` and apply automatically.

### Verify

```bash
cd shared && flutter analyze
cd allowance_app_v2 && flutter analyze && flutter test
```

### Build

```bash
flutter build apk --release --split-per-abi
```

> Run builds sequentially — parallel Gradle daemons collide.

`adb` at `platform-tools`; test AVD `Pixel_6_API_35`.
