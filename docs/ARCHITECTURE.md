# Architecture

## Goal

`iran_iap` keeps one Flutter dependency in the application while guaranteeing that store-specific native billing code is selected at Android build time rather than at Dart runtime.

## Build isolation

```text
Flutter app
   |
   +-- iran_iap Dart API
           |
           +-- IRAN_IAP_STORE=bazaar
           |      +-- android/src/bazaar
           |      +-- Poolakey 2.2.0
           |
           +-- IRAN_IAP_STORE=myket
                  +-- android/src/myket
                  +-- Myket Billing Client 1.19
```

The stable Flutter plugin entry point remains in `android/src/main`. Gradle adds exactly one provider source directory and one provider dependency. `android/src/stub` exists only to keep IDE/Gradle sync predictable when no store was selected; runtime initialization then fails with a configuration error instead of silently selecting a store.

## Dart API boundary

Application code only sees `IranIapClient`, `IranIap`, normalized models, capabilities, outcomes, and `IapException`. Poolakey and Myket SDK types never cross the platform channel.

Cancellation is data (`PurchaseCancelled`), while operational failures are exceptions (`IapException`). Native response details are diagnostic metadata, not the stable business-logic contract.

## Lifecycle

Each Flutter engine receives its own plugin instance. Native connections and operation state live on that instance and are released when the engine detaches or `dispose()` is called.

Only one non-initialization asynchronous billing operation can run at once. This protects the Myket helper's async-operation constraint and gives both stores consistent behavior.

## Host configuration

The package deliberately does not mutate the consuming application's Gradle model. JitPack and Myket manifest placeholders are explicit one-time host settings documented in the README. This avoids fragile cross-project Gradle hooks and remains compatible with centralized repository policies.

## Security boundary

The client returns purchase evidence; it does not grant entitlements. Production apps should verify and persist purchases on a trusted backend before granting valuable access or consuming a consumable.
