# Changelog

All notable changes to this package are documented here.

The project follows Semantic Versioning.

## 0.3.0

- Refactored the public Dart API for better clarity and production readiness.
- Adopted `very_good_analysis` for stricter linting and code quality standards.
- Enhanced API documentation across all public members.
- Improved CLI error handling and usage guidance.
- Hardened internal type safety and error handling in the Dart client.
- Reduced the public Dart surface to stable store-agnostic models, configuration, client contract, and client implementation.
- Removed public MethodChannel/testing implementation details.
- Unified Cafe Bazaar dynamic pricing into the normal purchase request API.
- Added explicit `storeNotInstalled`, `storeUnsupported`, `unsupportedPlatform`, and `featureUnavailable` error categories.
- Preserved native error diagnostics without leaking native SDK types through the public API.
- Kept undocumented native purchase-state values conservative instead of guessing provider semantics.
- Improved Poolakey connection error mapping so missing/unsupported Bazaar installations are distinguishable.
- Kept Bazaar and Myket native SDKs isolated at Android build time.
- Removed Gradle logic that mutated the consuming application project.
- Added a clean example app, store-aware CLI doctor/run/build flows, CI, security guidance, contribution docs, and release checks.
- Added package metadata suitable for GitHub and pub.dev.
- Hardened CLI project detection so a plugin root cannot be mistaken for a Flutter application even when a custom target is passed.
- Tightened the pub archive ignore rules to exclude generated state, maintainer tooling, CI files, and release evidence.

## 0.2.6

- Added one-time host JitPack setup guidance for Poolakey and Myket Billing Client.
- Improved CLI project-root detection and Android build-time store selection.

## 0.2.0

- Introduced a single-package build-time store isolation architecture.

## 0.1.0

- Initial internal prototype.
