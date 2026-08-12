# Contributing

Thanks for helping improve `iran_iap`.

## Setup

Use Flutter 3.44 or newer, then from the repository root:

```bash
flutter pub get
```

The example app lives in `example/` and depends on the package with `path: ../`.

## Before opening a pull request

Run:

```bash
dart format .
flutter analyze
flutter test --dart-define=IRAN_IAP_STORE=bazaar
flutter test --dart-define=IRAN_IAP_STORE=myket
python3 tool/check_isolation.py
python3 -m unittest tool.test_verify_android_artifact
flutter pub publish --dry-run
```

For Android changes, also build both store variants:

```bash
cd example
flutter build apk --debug --dart-define=IRAN_IAP_STORE=bazaar
flutter build apk --debug --dart-define=IRAN_IAP_STORE=myket
```

## Pull requests

Please keep changes focused. Public API changes should include Dartdoc, tests, and a changelog entry. Native billing changes should preserve the central invariant: a Bazaar artifact must not contain Myket billing code, and a Myket artifact must not contain Poolakey/Bazaar billing code.

Do not commit store private keys, production secrets, personal `local.properties`, build outputs, or IDE caches.
