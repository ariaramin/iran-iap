/// App stores currently supported by `iran_iap`.
enum IapStore {
  /// Cafe Bazaar.
  bazaar,

  /// Myket.
  myket,
}

/// Billing product type.
enum IapProductType {
  /// A one-time in-app product.
  inApp,

  /// A subscription product.
  subscription,
}

/// Normalized purchase state returned by a store.
enum IapPurchaseState {
  /// The purchase is active/purchased according to the store response.
  purchased,

  /// The store reported the purchase as refunded.
  refunded,

  /// The native SDK returned a state that `iran_iap` does not recognize.
  unknown,
}
