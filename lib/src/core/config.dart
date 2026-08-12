import 'package:meta/meta.dart';

/// Client-side signature checking mode for Cafe Bazaar purchases.
enum BazaarSecurityMode {
  /// Do not perform the RSA check in the client.
  ///
  /// Use this when purchase verification and entitlement decisions happen on a
  /// trusted backend. This is the default because client-side checks alone must
  /// not be treated as an authorization boundary.
  serverVerification,

  /// Ask Poolakey to perform local RSA signature verification.
  ///
  /// [IranIapConfig.storePublicKey] must be provided when this mode is used.
  localVerification,
}

/// Configuration shared by the selected store implementation.
@immutable
final class IranIapConfig {
  /// Creates billing configuration.
  ///
  /// [storePublicKey] is required for Myket. For Cafe Bazaar it is only needed
  /// when [bazaarSecurityMode] is [BazaarSecurityMode.localVerification].
  ///
  /// [enableSubscriptions] controls whether the Bazaar connection is created
  /// with subscription support enabled. Myket reports subscription capability
  /// from its billing service at runtime.
  const IranIapConfig({
    this.storePublicKey,
    this.bazaarSecurityMode = BazaarSecurityMode.serverVerification,
    this.enableSubscriptions = true,
  });

  /// Store-provided RSA public key used for signature verification.
  ///
  /// This is a public verification key, not a server secret. Never place
  /// private keys, API secrets, or backend credentials in a Flutter binary.
  final String? storePublicKey;

  /// Cafe Bazaar local signature verification strategy.
  final BazaarSecurityMode bazaarSecurityMode;

  /// Whether Cafe Bazaar subscription support should be requested.
  final bool enableSubscriptions;
}
