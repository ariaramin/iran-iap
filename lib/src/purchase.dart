import 'package:iran_iap/src/store.dart';
import 'package:meta/meta.dart';

/// Input for a purchase or subscription flow.
@immutable
final class IapPurchaseRequest {
  /// Creates a purchase request.
  ///
  /// [payload] is passed through to the selected store when supported and can
  /// be used to correlate a purchase with backend state. Do not put secrets in
  /// it because it can be stored in store purchase data.
  ///
  /// [dynamicPriceToken] is Cafe Bazaar-specific. Passing it to a Myket build
  /// throws `IapException` with `featureUnavailable` before opening a flow.
  const IapPurchaseRequest({
    required this.productId,
    required this.type,
    this.payload,
    this.dynamicPriceToken,
  });

  /// Product/SKU identifier configured in the target store console.
  final String productId;

  /// Whether the request targets an in-app product or subscription.
  final IapProductType type;

  /// Optional developer payload passed through to the store SDK.
  final String? payload;

  /// Optional Cafe Bazaar dynamic-price token.
  final String? dynamicPriceToken;
}

/// Normalized purchase evidence returned by a store.
///
/// The purchase token/receipt should be verified by a trusted backend before
/// granting valuable entitlements. Avoid logging [rawReceipt], [signature], or
/// [token] in production logs.
@immutable
final class IapPurchase {
  /// Creates normalized purchase evidence.
  IapPurchase({
    required this.store,
    required this.productId,
    required this.type,
    required this.token,
    required this.state,
    required this.purchaseTime,
    this.orderId,
    this.payload,
    this.packageName,
    this.rawReceipt,
    this.signature,
  }) {
    if (productId.trim().isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'Must not be empty.');
    }
    if (token.trim().isEmpty) {
      throw ArgumentError.value(token, 'token', 'Must not be empty.');
    }
  }

  /// Store that issued this purchase.
  final IapStore store;

  /// Product/SKU identifier.
  final String productId;

  /// Product type associated with this purchase.
  final IapProductType type;

  /// Store purchase token.
  final String token;

  /// Store order identifier when the native SDK provides one.
  final String? orderId;

  /// Developer payload returned by the store, when available.
  final String? payload;

  /// Android package name recorded in the purchase, when available.
  final String? packageName;

  /// Normalized purchase state.
  final IapPurchaseState state;

  /// Purchase timestamp reported by the store.
  final DateTime purchaseTime;

  /// Opaque native receipt JSON when exposed by the store SDK.
  final String? rawReceipt;

  /// Native signature paired with [rawReceipt], when exposed by the store SDK.
  final String? signature;

  @override
  String toString() =>
      'IapPurchase('
      'store: $store, productId: $productId, type: $type, state: $state, '
      'purchaseTime: $purchaseTime)';
}
