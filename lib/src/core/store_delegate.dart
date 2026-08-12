import 'package:iran_iap/src/core/config.dart';
import 'package:iran_iap/src/core/error.dart';
import 'package:iran_iap/src/core/store.dart';
import 'package:iran_iap/src/models/purchase.dart';

/// Internal delegate that encapsulates store-specific behavior.
abstract interface class StoreDelegate {
  /// Validates [config] for this store.
  void validateConfig(IranIapConfig config);

  /// Returns arguments for the native `initialize` call.
  Map<String, Object?> platformConfigArguments(IranIapConfig config);

  /// Validates a purchase request before sending it to the native SDK.
  void validatePurchaseRequest(IapPurchaseRequest request);

  /// Executes the native `consume` operation.
  Future<void> consume({
    required IapPurchase purchase,
    required Future<T?> Function<T>(String method, [Object? arguments]) invoke,
  });
}

/// Delegate for Cafe Bazaar (Poolakey).
final class BazaarDelegate implements StoreDelegate {
  /// Creates a Bazaar delegate.
  const BazaarDelegate();

  @override
  void validateConfig(IranIapConfig config) {
    final normalizedKey = config.storePublicKey?.trim();
    if (config.bazaarSecurityMode == BazaarSecurityMode.localVerification &&
        (normalizedKey == null || normalizedKey.isEmpty)) {
      throw ArgumentError(
        'storePublicKey is required when Bazaar local verification is '
        'enabled.',
      );
    }
  }

  @override
  Map<String, Object?> platformConfigArguments(IranIapConfig config) {
    return <String, Object?>{
      'securityMode': config.bazaarSecurityMode.name,
      'rsaPublicKey': config.storePublicKey,
      'supportSubscriptions': config.enableSubscriptions,
    };
  }

  @override
  void validatePurchaseRequest(IapPurchaseRequest request) {
    // Bazaar supports dynamicPriceToken, no extra validation needed here.
  }

  @override
  Future<void> consume({
    required IapPurchase purchase,
    required Future<T?> Function<T>(String method, [Object? arguments]) invoke,
  }) {
    return invoke<void>('consume', <String, Object?>{
      'token': purchase.token,
    });
  }
}

/// Delegate for Myket.
final class MyketDelegate implements StoreDelegate {
  /// Creates a Myket delegate.
  const MyketDelegate();

  @override
  void validateConfig(IranIapConfig config) {
    final normalizedKey = config.storePublicKey?.trim();
    if (normalizedKey == null || normalizedKey.isEmpty) {
      throw ArgumentError('storePublicKey is required for Myket billing.');
    }
  }

  @override
  Map<String, Object?> platformConfigArguments(IranIapConfig config) {
    return <String, Object?>{'publicKey': config.storePublicKey};
  }

  @override
  void validatePurchaseRequest(IapPurchaseRequest request) {
    if (request.dynamicPriceToken != null) {
      throw IapException(
        code: IapErrorCode.featureUnavailable,
        store: IapStore.myket,
        message: 'Dynamic-price tokens are only available for Cafe Bazaar.',
      );
    }
  }

  @override
  Future<void> consume({
    required IapPurchase purchase,
    required Future<T?> Function<T>(String method, [Object? arguments]) invoke,
  }) {
    if (purchase.rawReceipt == null || purchase.signature == null) {
      throw ArgumentError(
        'Myket consumption requires rawReceipt and signature.',
      );
    }
    return invoke<void>('consume', <String, Object?>{
      'type': purchase.type.wireName,
      'rawReceipt': purchase.rawReceipt,
      'signature': purchase.signature,
    });
  }
}
