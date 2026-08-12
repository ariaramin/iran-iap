# iran_iap

A small Flutter plugin for in-app purchases on **Cafe Bazaar** and **Myket** with one stable Dart dependency and build-time native SDK isolation.

The main goal is simple: keep the same `pubspec.yaml`, switch the target store at build time, and avoid shipping the other store's billing SDK in that APK/AAB.

## Features

- One Flutter dependency for Bazaar and Myket.
- Build-time store selection; no runtime `if` that bundles both native SDKs.
- In-app products and subscriptions.
- Product queries, owned-purchase queries, purchase flows, and consumption.
- User cancellation as a typed result instead of an exception.
- Stable Dart error taxonomy while preserving native diagnostics.
- Cafe Bazaar dynamic-price token support.
- Store capabilities exposed after initialization.
- Small dependency footprint: only the Flutter SDK on the Dart side.
- A CLI for store-aware `run` and `build` commands without editing `pubspec.yaml`.

## Supported stores and platforms

| Platform / Store | Support |
| --- | --- |
| Android + Cafe Bazaar | ✅ |
| Android + Myket | ✅ |
| iOS | ❌ |
| Web | ❌ |
| macOS | ❌ |
| Windows | ❌ |
| Linux | ❌ |

`iran_iap` is intentionally Android-only because Bazaar and Myket billing are Android store services.

## Requirements

- Flutter `>=3.44.0`
- Dart `>=3.12.0 <4.0.0`
- Android `minSdk 24`
- Java 17-compatible Android toolchain
- Cafe Bazaar or Myket installed on the test device for real billing flows

## Installation

```yaml
dependencies:
  iran_iap: ^0.3.0
```

Then run:

```bash
flutter pub get
```

You do **not** add Poolakey, `myket_iap`, or a second Flutter billing package to your app's `pubspec.yaml`.

## Quick start

### 1. One-time Android repository setup

Both native store SDKs are distributed through JitPack. Add JitPack once to the Android repositories used by your application.

For the common Flutter Gradle layout, add this to `android/build.gradle.kts`:

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://jitpack.io")
            content {
                includeGroup("com.github.cafebazaar.Poolakey")
                includeGroup("com.github.myketstore")
            }
        }
    }
}
```

If your project centralizes repositories in `android/settings.gradle.kts`, put the same JitPack repository inside `dependencyResolutionManagement.repositories` instead.

The repository declaration does not bundle either SDK. The selected build decides which native dependency is present.

### 2. Keep Myket manifest placeholders configured once

Myket Billing Client uses these host-app placeholders. They can stay in the app configuration for every build; they are only consumed when the Myket AAR is selected.

In `android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        manifestPlaceholders["marketApplicationId"] = "ir.mservices.market"
        manifestPlaceholders["marketBindAddress"] =
            "ir.mservices.market.InAppBillingService.BIND"
        manifestPlaceholders["marketPermission"] = "ir.mservices.market.BILLING"
    }
}
```

### 3. Use a Bazaar-compatible Activity host

Poolakey's current purchase flow uses Android's Activity Result API. The easiest Flutter host is `FlutterFragmentActivity`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

This setup can remain unchanged for Myket builds as well.

### 4. Create the client

```dart
import 'package:iran_iap/iran_iap.dart';

final iap = IranIap(
  config: const IranIapConfig(
    // Required for Myket. For Bazaar, only required for local verification.
    storePublicKey: myStorePublicKey,
  ),
);

await iap.initialize();
```

For a Bazaar build using backend verification, the config can be as small as:

```dart
final iap = IranIap();
await iap.initialize();
```

### 5. Run for one store

Cafe Bazaar:

```bash
dart run iran_iap run --store bazaar
```

Myket:

```bash
dart run iran_iap run \
  --store myket \
  --dart-define=IAP_PUBLIC_KEY=YOUR_MYKET_PUBLIC_KEY
```

The CLI does not edit your `pubspec.yaml`. It forwards the store to both Dart and Gradle for that build.

You can also use Flutter directly:

```bash
flutter run --dart-define=IRAN_IAP_STORE=bazaar
```

## Build commands

Bazaar APK:

```bash
dart run iran_iap build apk --store bazaar --release
```

Myket APK:

```bash
dart run iran_iap build apk --store myket --release
```

Myket app bundle:

```bash
dart run iran_iap build appbundle --store myket --release
```

The package's Android Gradle logic adds only the selected native SDK and only the selected Kotlin source set.

## Usage

### Query products

```dart
final products = await iap.queryProducts(
  {'premium_monthly', 'coins_100'},
  type: IapProductType.inApp,
);

for (final product in products) {
  print('${product.title}: ${product.price}');
}
```

### Purchase

```dart
final outcome = await iap.purchase(
  const IapPurchaseRequest(
    productId: 'premium_monthly',
    type: IapProductType.inApp,
    payload: 'user-123',
  ),
);

switch (outcome) {
  case PurchaseCompleted(:final purchase):
    // Send purchase evidence to your backend and verify it before granting
    // valuable entitlements.
    print('Purchase token: ${purchase.token}');

  case PurchaseCancelled():
    // Normal user action; no exception is thrown.
    print('Purchase cancelled');
}
```

### Subscriptions

```dart
if (iap.capabilities.supportsSubscriptions) {
  final outcome = await iap.purchase(
    const IapPurchaseRequest(
      productId: 'premium_monthly',
      type: IapProductType.subscription,
    ),
  );
}
```

### Owned purchases

```dart
final purchases = await iap.queryPurchases(
  type: IapProductType.inApp,
);
```

### Consume a verified consumable

```dart
// 1. Verify the purchase and persist the entitlement on your backend.
// 2. Only then consume it when your business flow requires consumption.
await iap.consume(purchase);
```

### Cafe Bazaar dynamic price tokens

Dynamic pricing is provider-specific but remains inside the common purchase API:

```dart
if (iap.capabilities.supportsDynamicPricing) {
  final outcome = await iap.purchase(
    const IapPurchaseRequest(
      productId: 'coins_100',
      type: IapProductType.inApp,
      dynamicPriceToken: 'TOKEN_FROM_YOUR_TRUSTED_FLOW',
    ),
  );
}
```

Passing a dynamic-price token to a Myket build throws `IapErrorCode.featureUnavailable` before opening the native purchase flow.

## Available APIs

The public surface is intentionally small:

- `IranIap` — default client implementation.
- `IranIapClient` — store-agnostic interface for DI/mocking in applications.
- `IranIapConfig` — initialization configuration.
- `queryProducts(...)` — fetch product metadata.
- `purchase(...)` — purchase/subscription flow.
- `queryPurchases(...)` — fetch currently owned purchases.
- `consume(...)` — consume verified in-app purchases.
- `dispose()` — release native billing resources.

Types from Poolakey and Myket Billing Client are not exposed in the Dart API.

## Handling errors

Operational failures throw `IapException`:

```dart
try {
  await iap.initialize();
} on IapException catch (error) {
  switch (error.code) {
    case IapErrorCode.storeNotInstalled:
      // Ask the user to install the target store.
      break;
    case IapErrorCode.storeUnsupported:
    case IapErrorCode.serviceUnavailable:
      // The installed store/billing service cannot currently serve the flow.
      break;
    case IapErrorCode.configuration:
      // Fix app/package configuration.
      break;
    default:
      // Log diagnostics and show an appropriate retry/error UI.
      break;
  }
}
```

`nativeCode`, `nativeMessage`, and `nativeExceptionType` are preserved when available. Use them for diagnostics; keep business logic on the stable `IapErrorCode` values.

User cancellation is **not** an exception. It returns `PurchaseCancelled`.

## Security

A client-side "purchase succeeded" callback is not a sufficient authorization boundary for valuable digital entitlements.

Recommended flow:

1. Receive purchase evidence from `iran_iap`.
2. Send it to your backend over an authenticated connection.
3. Verify the purchase against the store/vendor verification flow you trust.
4. Persist an idempotent entitlement/transaction record server-side.
5. Grant the entitlement.
6. Consume consumables only after the server-side state is safely persisted.

Never put private keys, backend API secrets, or privileged credentials in Dart code or `--dart-define` values shipped to users.

## Example

A runnable Android example is included in [`example/`](example/).

From the repository root:

```bash
dart run iran_iap run --store bazaar
```

Or:

```bash
dart run iran_iap run \
  --store myket \
  --dart-define=IAP_PUBLIC_KEY=YOUR_MYKET_PUBLIC_KEY
```

For real transactions, install the selected store on the device, sign in, configure matching product IDs in the store console, and use the application/package identity registered for testing.

## Troubleshooting

### `storeNotInstalled`

The selected store app is not installed or cannot be discovered on the device. Billing tests are more reliable on a physical Android device with the target store installed and signed in.

### Bazaar initialization cannot connect

`storeNotInstalled` means Cafe Bazaar is not installed/discoverable. `storeUnsupported` means the installed Bazaar billing API is incompatible. Other connection failures preserve `nativeExceptionType`/`nativeMessage` for diagnostics and can surface as `serviceUnavailable`, `notInitialized`, or `platform` depending on the upstream failure.

### Poolakey or Myket dependency cannot be resolved

Make sure the host Android project has the one-time JitPack repository setup shown above.

### `activityUnavailable` on Bazaar purchases

Use `FlutterFragmentActivity` (or another Android Activity implementing `ActivityResultRegistryOwner`) as the Flutter host activity.

### `No iran_iap store is selected`

Use the CLI:

```bash
dart run iran_iap run --store bazaar
```

or pass a matching Flutter define:

```bash
flutter run --dart-define=IRAN_IAP_STORE=bazaar
```

A hot restart cannot change compile-time store selection; stop and rebuild the app.

### Myket initialization reports a configuration error

Pass the Myket public RSA verification key to `IranIapConfig.storePublicKey`. Do not pass a private key or backend secret.

## Limitations

- Android only.
- Cafe Bazaar and Myket only in the current release.
- Store SDK behavior can depend on the installed store app version, account state, product-console configuration, and test eligibility.
- The package normalizes client billing operations; it does not replace backend receipt verification or entitlement storage.
- JitPack and Myket manifest placeholders require one-time host Android configuration.

## Versioning

`iran_iap` follows Semantic Versioning. The package is intentionally below `1.0.0` while the public API receives real-world feedback from multiple production apps. Breaking public API changes during the `0.x` period will be documented clearly in `CHANGELOG.md` and migration notes.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and quality checks.

For security-sensitive reports, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

`iran_iap` is available under the MIT License. See [LICENSE](LICENSE).

Native store SDKs remain separate upstream dependencies. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
