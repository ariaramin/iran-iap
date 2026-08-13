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
- Added the project banner and expanded the README with complete setup, API, lifecycle, error-handling, and troubleshooting guidance.
- Corrected the Myket artifact scanner to detect Poolakey code without rejecting Bazaar service identifiers embedded by the Myket SDK itself.
- Fixed reconnection after a native billing disconnect and normalized malformed native payloads to `IapErrorCode.invalidResponse`.
- Rejected conflicting CLI store defines and enforced subscription capabilities for product queries.
- Made Bazaar error mapping resilient to code shrinking and fail in-flight Bazaar operations safely across Activity recreation.
- Included the runtime artifact verifier in the pub archive and disabled automatic tag publishing pending explicit release setup.
- Made CLI parsing directly testable, declared `--verbose`, validated positional operands, and centralized asynchronous exit-status handling.
- Fixed artifact verification from globally activated installs by resolving runtime assets through Dart's package configuration.
- Added example configuration regression coverage and excluded the generated Android registrant from the pub archive.
- Removed the pre-release publishing workflow; the first pub.dev release remains an explicit manual gate.

## 0.2.6

- Added one-time host JitPack setup guidance for Poolakey and Myket Billing Client.
- Improved CLI project-root detection and Android build-time store selection.

## 0.2.0

- Introduced a single-package build-time store isolation architecture.

## 0.1.0

- Initial internal prototype.
