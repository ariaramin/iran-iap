# Validation report — iran_iap 0.3.0

## Automated checks

The release-preparation pass executed successfully with Flutter 3.44.2,
Dart 3.12.2, and pana 0.23.18:

```text
dart format --output=none --set-exit-if-changed .
PASS — no formatting changes required

flutter analyze
PASS — no issues found

flutter test
PASS — 7 CLI tests; store-specific suite skipped with explicit guidance

flutter test --dart-define=IRAN_IAP_STORE=bazaar
PASS — 21 tests

flutter test --dart-define=IRAN_IAP_STORE=myket
PASS — 21 tests

example: flutter test --dart-define=IRAN_IAP_STORE=myket
PASS — configuration regression test

dart doc --output=doc/api
PASS — 100% documented public API (96/96), 0 warnings, 0 errors

python3 tool/check_isolation.py
PASS — source/dependency isolation

python3 -m unittest tool.test_verify_android_artifact
PASS — 7 artifact-scanner tests

example: flutter build apk --debug --dart-define=IRAN_IAP_STORE=bazaar
PASS — APK built and artifact isolation scan passed

example: flutter build apk --debug --dart-define=IRAN_IAP_STORE=myket
PASS — APK built and artifact isolation scan passed

isolated global activation: iran_iap verify
PASS — packaged verifier resolved outside the source directory

dart pub publish --dry-run (clean payload copy)
PASS — 0 warnings, 1 MB compressed archive

pana 0.23.18
150/160 — all documentation, platform, analysis, and dependency points pass.
The remaining 10 repository points require committing and pushing this prepared
pubspec so the remote `main` branch no longer contains the old underscore URL.
```

## Manual release gates

Real billing transactions require physical Android devices with the target
store installed, signed in, and configured with test products/accounts. Before
publishing:

- run purchase, cancellation, restore, consumption, subscription, and lifecycle
  checks against both stores;
- verify real purchase evidence through the intended backend;
- confirm the GitHub repository and pub.dev package name;
- confirm current Myket Billing Client vendor/license terms;
- configure the pub.dev publisher and publish manually.

See [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) for the full release
gate list.
