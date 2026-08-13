# Release checklist

## API and repository

- [x] Public API reviewed and implementation details hidden from the main library export.
- [x] No project-specific DI, feature, or core imports.
- [x] README, changelog, license, security, and contribution docs present.
- [x] Example is a standalone Android Flutter app using `path: ../`.
- [x] CI validates formatting, analysis, Dart tests, both Android store builds, artifact isolation, and publish dry run.
- [x] No generated caches/build outputs in the prepared archive.
- [x] Runtime Dart dependencies are limited to Flutter, `args`, and `meta`.
- [x] Static XML/YAML parsing, Python tooling compilation, source-isolation checks, and synthetic artifact-scanner tests pass in the preparation environment.
- [x] Publish ignore surface excludes generated state, maintainer tooling, CI metadata, and release evidence.

## Native validation before 1.0.0

- [ ] Bazaar initialization on a physical device with Bazaar installed and signed in.
- [ ] Bazaar in-app purchase, cancellation, owned-query, consume, subscription, and rotation/lifecycle flow.
- [ ] Myket initialization on a physical device with Myket installed and signed in.
- [ ] Myket in-app purchase, cancellation, owned-query, consume, and subscription flow.
- [ ] Backend verification tested against real sandbox/test purchase evidence for both stores.
- [ ] Release APK/AAB scanner run for both store variants.

## Publication

- [x] Confirm `https://github.com/ariaramin/iran-iap` is the intended public repository.
- [ ] Commit and push the prepared pubspec before the final pana run so repository metadata matches the release archive.
- [ ] Confirm the `iran_iap` name is still available on pub.dev immediately before the first publish.
- [ ] Confirm current Myket Billing Client vendor/license terms for the intended public integration.
- [ ] Run `dart format .`.
- [ ] Run `flutter analyze`.
- [ ] Run both `flutter test --dart-define=...` commands.
- [ ] Run both example Android builds.
- [ ] Run `flutter pub publish --dry-run` and inspect the exact archive file list.
- [ ] Publish the first version manually with `flutter pub publish`.
- [ ] After the first version exists on pub.dev, configure trusted publishing and add an explicitly reviewed tag workflow if desired.
