/// App stores currently supported by `iran_iap`.
enum IapStore {
  /// Cafe Bazaar.
  bazaar,

  /// Myket.
  myket;

  /// Retrieves the store selected for the current build via `--dart-define`.
  ///
  /// Throws [StateError] if `IRAN_IAP_STORE` environment variable is missing
  /// or invalid.
  static IapStore get current {
    const storeName = String.fromEnvironment('IRAN_IAP_STORE');
    return switch (storeName) {
      'bazaar' => IapStore.bazaar,
      'myket' => IapStore.myket,
      _ => throw StateError(
        'No iran_iap store is selected. \n\n'
        'How to fix:\n'
        '1. Use the bundled CLI: `dart run iran_iap run --store '
        'bazaar|myket` \n'
        '2. Or pass the define manually: `flutter run '
        '--dart-define=IRAN_IAP_STORE=bazaar|myket` \n\n'
        'A hot restart cannot change compile-time store selection; stop and '
        'rebuild the app.',
      ),
    };
  }
}

/// Billing product type.
enum IapProductType {
  /// A one-time in-app product.
  inApp,

  /// A subscription product.
  subscription;

  /// Parses a wire name into a [IapProductType].
  static IapProductType fromWire(String value) => switch (value) {
    'inapp' => IapProductType.inApp,
    'subs' => IapProductType.subscription,
    _ => throw FormatException('Unknown product type: $value'),
  };

  /// Returns the wire name for this product type.
  String get wireName => switch (this) {
    IapProductType.inApp => 'inapp',
    IapProductType.subscription => 'subs',
  };
}

/// Normalized purchase state returned by a store.
enum IapPurchaseState {
  /// The purchase is active/purchased according to the store response.
  purchased,

  /// The store reported the purchase as refunded.
  refunded,

  /// The native SDK returned a state that `iran_iap` does not recognize.
  unknown;

  /// Parses a wire value into a [IapPurchaseState].
  static IapPurchaseState fromWire(Object? value) => switch (value) {
    'purchased' || 0 => IapPurchaseState.purchased,
    'refunded' => IapPurchaseState.refunded,
    _ => IapPurchaseState.unknown,
  };
}
