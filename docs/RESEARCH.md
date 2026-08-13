# Research notes

These notes record the upstream assumptions used by `iran_iap` 0.3.0 so future maintainers can re-check them during upgrades.

## Flutter and Dart

- The package is an Android Flutter plugin with a Dart API connected to Kotlin by a platform channel.
- The stable plugin class stays under the conventional `android/src/main/kotlin/...` path expected by Flutter tooling.
- Engine-specific state belongs to the plugin instance and is cleaned up on engine detachment.
- Package publication should be preceded by a pub dry run and review of README, changelog, license, metadata, and published contents.

## Cafe Bazaar

- Native integration: Poolakey.
- Pinned native version: `2.2.0`.
- Artifact: `com.github.cafebazaar.Poolakey:poolakey:2.2.0`.
- Distribution repository: JitPack.
- Purchase flow uses an Activity Result registry; the example uses `FlutterFragmentActivity`.
- Poolakey exposes concrete connection/purchase exception types. The adapter maps known types to stable Dart errors and preserves the native exception name/message.

## Myket

- Native integration: Myket Billing Client.
- Pinned native version: `1.19`.
- Artifact: `com.github.myketstore:myket-billing-client:1.19`.
- Distribution repository: JitPack.
- Myket's helper permits one asynchronous billing operation at a time, so the common Dart/native layer serializes billing operations by rejecting overlaps.
- The Billing Client AAR uses store manifest placeholders supplied by the host application.
- Version 1.19 embeds Cafe Bazaar service package strings for its own compatibility logic. Artifact isolation therefore checks for Poolakey package/classes rather than treating those service-name strings as evidence that Poolakey was bundled.
- In upstream 1.19, the three-argument inventory implementation passes `moreItemSkus` to the subscription SKU-details query instead of `moreSubsSkus`. `iran_iap` deliberately uses the public two-argument async inventory API and filters returned `SkuDetails` by type, avoiding reflection or a fork.
- The upstream repository currently has no root `LICENSE` file visible on its default branch. Individual inherited Google IAB source files contain Apache-2.0 headers, but the maintainer must still confirm Myket's current vendor/distribution terms before first public publication.

## Upgrade policy

When changing either native SDK version:

1. Read the upstream changelog/source before editing the version.
2. Re-check manifest requirements, package names, callbacks, error codes, purchase states, and lifecycle behavior.
3. Build both store variants.
4. Run the cross-store artifact scanner.
5. Test real purchase/cancellation/restore/consume/subscription flows on physical devices.
6. Update `THIRD_PARTY_NOTICES.md`, README requirements, and this research record when upstream licensing/setup changes.
