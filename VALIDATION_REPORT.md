# Validation report — iran_iap 0.3.0

This report separates checks executed in the preparation environment from checks that require a Flutter/Android toolchain, pub.dev credentials, or real store devices.

## Executed successfully here

```text
python3 tool/check_isolation.py
PASS — source/dependency isolation

python3 -m unittest tool.test_verify_android_artifact
PASS — 2 synthetic APK/AAB scanner tests

Python XML parse
PASS — Android manifests/resources parsed

Python YAML parse
PASS — pubspec and GitHub workflow YAML parsed

python3 -m compileall -q tool
PASS — maintainer Python tooling compiles

Repository/security hygiene scan
PASS — no private-key blocks, keystores, build caches, or provider Flutter dependencies detected.
(Note: Machine-specific local.properties and generated Flutter metadata were removed and are now git-ignored).
```

The final ZIP is also integrity-tested and SHA-256 hashed after packaging.

## Configured in CI, but not executable in this preparation container

The container does not include Flutter or Dart CLI binaries. These gates are therefore intentionally **not claimed as passed locally**:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
dart doc --output=doc/api
flutter test --dart-define=IRAN_IAP_STORE=bazaar
flutter test --dart-define=IRAN_IAP_STORE=myket
cd example && flutter build apk --debug --dart-define=IRAN_IAP_STORE=bazaar
cd example && flutter build apk --debug --dart-define=IRAN_IAP_STORE=myket
flutter pub publish --dry-run
```

GitHub Actions runs these checks on Flutter 3.44.7, including both Android provider builds and post-build artifact isolation scans.

## Manual release gates

Real billing transactions require suitable Android devices with the target store installed, signed in, and configured with test products/accounts. The first pub.dev publish also requires maintainer credentials and confirmation of the intended GitHub repository/name. See `docs/RELEASE_CHECKLIST.md`.
