---
description: Run flutter analyze and flutter test on both allowance apps.
---

Run `flutter analyze` and `flutter test` in both apps and report the results.

Work directories:
- v1: `C:\Users\way2m\OneDrive\Documents\Default Project\allowance_app`
- v2: `C:\Users\way2m\OneDrive\Documents\Default Project\allowance_app_v2`

Use the call operator with the full Flutter path:
`& "C:\flutter\bin\flutter.bat" analyze` and `& "C:\flutter\bin\flutter.bat" test`.

Run `analyze` in both apps first (in parallel), then `test` in both apps.

Report for each app:
- analyze result (clean or list of issues)
- test result (`All tests passed!` + the pass count, or failures)

If `$ARGUMENTS` is non-empty, apply it as a scope:
- `v1` — only run in `allowance_app`
- `v2` — only run in `allowance_app_v2`
- otherwise — pass it through to `flutter test` (e.g. a test file path like `test/allowance_calculator_test.dart`) in both apps.

Fix nothing — verify only and report results.
