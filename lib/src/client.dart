import 'package:flutter/services.dart' as services;
import 'package:iran_iap/src/capabilities.dart';
import 'package:iran_iap/src/config.dart';
import 'package:iran_iap/src/error.dart';
import 'package:iran_iap/src/product.dart';
import 'package:iran_iap/src/purchase.dart';
import 'package:iran_iap/src/purchase_outcome.dart';
import 'package:iran_iap/src/store.dart';
import 'package:meta/meta.dart';

/// Store-agnostic billing contract used by application code and
/// dependency injection.
abstract interface class IranIapClient {
  /// Store selected for the current Flutter build.
  IapStore get store;

  /// Whether [initialize] completed and the native connection is still usable.
  bool get isInitialized;

  /// Capabilities reported during the latest successful initialization.
  IapCapabilities get capabilities;

  /// Connects to the selected store billing service.
  ///
  /// Calling this method repeatedly after a successful initialization is safe.
  /// Concurrent initialization requests share the same in-flight operation.
  ///
  /// Throws [IapException] for configuration, store availability, or platform
  /// failures. A client that has been [dispose]d cannot be initialized again.
  Future<void> initialize();

  /// Queries metadata for [productIds].
  ///
  /// An empty set returns an empty list without invoking the native SDK.
  /// Throws [ArgumentError] when any identifier is blank and [IapException]
  /// when the client is not initialized or the store query fails.
  @useResult
  Future<List<IapProduct>> queryProducts(
    Set<String> productIds, {
    required IapProductType type,
  });

  /// Starts a purchase or subscription flow.
  ///
  /// A user cancellation returns [PurchaseCancelled]. Operational failures
  /// throw [IapException]. Only one asynchronous billing operation can run at a
  /// time; overlapping calls fail with [IapErrorCode.operationInProgress].
  @useResult
  Future<PurchaseOutcome> purchase(IapPurchaseRequest request);

  /// Returns currently owned purchases for [type].
  @useResult
  Future<List<IapPurchase>> queryPurchases({required IapProductType type});

  /// Consumes a previously verified in-app purchase.
  ///
  /// Verify and persist the entitlement on a trusted backend before consuming
  /// valuable purchases. Subscriptions cannot be consumed.
  Future<void> consume(IapPurchase purchase);

  /// Disconnects native billing resources.
  ///
  /// Calling this more than once is safe. Create a new client if billing is
  /// needed again after disposal.
  Future<void> dispose();
}

/// Default `iran_iap` billing client.
///
/// The concrete native implementation is selected at build time with
/// `IRAN_IAP_STORE=bazaar` or `IRAN_IAP_STORE=myket`. Prefer the bundled CLI:
/// `dart run iran_iap run --store bazaar` and
/// `dart run iran_iap build apk --store myket --release`.
final class IranIap implements IranIapClient {
  /// Creates a billing client for the store selected in this build.
  ///
  /// This constructor throws [StateError] when the application was compiled
  /// without a valid `IRAN_IAP_STORE` value. Use the package CLI or Flutter's
  /// `--dart-define=IRAN_IAP_STORE=...` option.
  IranIap({this.config = const IranIapConfig()})
    : _store = _selectedBuildStore(),
      _channel = const services.MethodChannel(_channelName);

  static const String _channelName = 'dev.iraniap/iran_iap';

  /// Configuration applied when [initialize] first connects.
  final IranIapConfig config;

  final IapStore _store;
  final services.MethodChannel _channel;

  bool _initialized = false;
  bool _disposed = false;
  bool _operationInProgress = false;
  Future<void>? _initialization;
  IapCapabilities _capabilities = const IapCapabilities();

  @override
  IapStore get store => _store;

  @override
  bool get isInitialized => _initialized && !_disposed;

  @override
  IapCapabilities get capabilities => _capabilities;

  @override
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(_stateError(IapErrorCode.disposed));
    }
    if (_initialized) {
      return Future<void>.value();
    }
    return _initialization ??= _initializeOnce().whenComplete(() {
      if (!_initialized) {
        _initialization = null;
      }
    });
  }

  Future<void> _initializeOnce() async {
    _validateConfig();
    final nativeStore = await _invoke<String>('selectedStore');
    if (nativeStore != store.name) {
      throw IapException(
        code: IapErrorCode.configuration,
        store: store,
        message:
            'Dart selected ${store.name}, but the Android build '
            'contains ${nativeStore ?? 'no'} billing implementation.',
      );
    }

    final raw = await _invoke<Map<Object?, Object?>>(
      'initialize',
      _platformConfigArguments(),
    );
    final map = _asStringMap(raw, 'capabilities');
    _capabilities = IapCapabilities(
      supportsSubscriptions: map['supportsSubscriptions'] as bool? ?? false,
      supportsConsumption: map['supportsConsumption'] as bool? ?? false,
      supportsDynamicPricing: map['supportsDynamicPricing'] as bool? ?? false,
    );
    _initialized = true;
  }

  @override
  Future<List<IapProduct>> queryProducts(
    Set<String> productIds, {
    required IapProductType type,
  }) async {
    _ensureReady();
    _ensureTypeSupported(type);
    if (productIds.isEmpty) {
      return const <IapProduct>[];
    }
    _validateIds(productIds);

    return _guard(() async {
      final raw =
          await _invoke<List<Object?>>('queryProducts', <String, Object?>{
            'productIds': productIds.toList(growable: false),
            'type': _productTypeWireName(type),
          });
      return (raw ?? const <Object?>[])
          .map(_decodeProduct)
          .toList(growable: false);
    });
  }

  @override
  Future<PurchaseOutcome> purchase(IapPurchaseRequest request) async {
    _ensureReady();
    _validatePurchaseRequest(request);
    _ensureTypeSupported(request.type);

    if (request.dynamicPriceToken != null && store != IapStore.bazaar) {
      throw IapException(
        code: IapErrorCode.featureUnavailable,
        store: store,
        message: 'Dynamic-price tokens are only available for Cafe Bazaar.',
      );
    }

    return _guard(() async {
      final raw =
          await _invoke<Map<Object?, Object?>>('purchase', <String, Object?>{
            'productId': request.productId,
            'type': _productTypeWireName(request.type),
            'payload': request.payload,
            'dynamicPriceToken': request.dynamicPriceToken,
          });
      final map = _asStringMap(raw, 'purchase');
      return switch (map['status']) {
        'completed' => PurchaseCompleted(
          _decodePurchase(map['purchase'], request.type),
        ),
        'cancelled' => const PurchaseCancelled(),
        _ => throw _invalidResponse(
          'Unknown purchase status: ${map['status']}',
        ),
      };
    });
  }

  @override
  Future<List<IapPurchase>> queryPurchases({
    required IapProductType type,
  }) async {
    _ensureReady();
    _ensureTypeSupported(type);

    return _guard(() async {
      final raw = await _invoke<List<Object?>>(
        'queryPurchases',
        <String, Object?>{'type': _productTypeWireName(type)},
      );
      return (raw ?? const <Object?>[])
          .map((value) => _decodePurchase(value, type))
          .toList(growable: false);
    });
  }

  @override
  Future<void> consume(IapPurchase purchase) async {
    _ensureReady();
    if (purchase.store != store) {
      throw ArgumentError(
        'Cannot consume a ${purchase.store.name} purchase with ${store.name}.',
      );
    }
    if (purchase.type != IapProductType.inApp) {
      throw ArgumentError('Subscriptions cannot be consumed.');
    }

    await _guard(() {
      if (store == IapStore.myket) {
        if (purchase.rawReceipt == null || purchase.signature == null) {
          throw ArgumentError(
            'Myket consumption requires rawReceipt and signature.',
          );
        }
        return _invoke<void>('consume', <String, Object?>{
          'type': _productTypeWireName(purchase.type),
          'rawReceipt': purchase.rawReceipt,
          'signature': purchase.signature,
        });
      }
      return _invoke<void>('consume', <String, Object?>{
        'token': purchase.token,
      });
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await _invoke<void>('dispose');
    _initialized = false;
    _disposed = true;
    _initialization = null;
    _capabilities = const IapCapabilities();
  }

  void _validateConfig() {
    final normalizedKey = config.storePublicKey?.trim();
    switch (store) {
      case IapStore.bazaar:
        if (config.bazaarSecurityMode == BazaarSecurityMode.localVerification &&
            (normalizedKey == null || normalizedKey.isEmpty)) {
          throw ArgumentError(
            'storePublicKey is required when Bazaar local verification is '
            'enabled.',
          );
        }
      case IapStore.myket:
        if (normalizedKey == null || normalizedKey.isEmpty) {
          throw ArgumentError('storePublicKey is required for Myket billing.');
        }
    }
  }

  Map<String, Object?> _platformConfigArguments() => switch (store) {
    IapStore.bazaar => <String, Object?>{
      'securityMode': config.bazaarSecurityMode.name,
      'rsaPublicKey': config.storePublicKey,
      'supportSubscriptions': config.enableSubscriptions,
    },
    IapStore.myket => <String, Object?>{'publicKey': config.storePublicKey},
  };

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on services.PlatformException catch (error) {
      throw _fromPlatform(error);
    } on services.MissingPluginException catch (error) {
      throw IapException(
        code: IapErrorCode.unsupportedPlatform,
        store: store,
        message: 'iran_iap is unavailable on this platform.',
        nativeMessage: error.message,
        nativeExceptionType: 'MissingPluginException',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (_operationInProgress) {
      throw _stateError(IapErrorCode.operationInProgress);
    }
    _operationInProgress = true;
    try {
      return await action();
    } finally {
      _operationInProgress = false;
    }
  }

  void _ensureReady() {
    if (_disposed) {
      throw _stateError(IapErrorCode.disposed);
    }
    if (!_initialized) {
      throw _stateError(IapErrorCode.notInitialized);
    }
  }

  void _ensureTypeSupported(IapProductType type) {
    if (type == IapProductType.subscription &&
        !_capabilities.supportsSubscriptions) {
      throw _stateError(IapErrorCode.subscriptionUnavailable);
    }
  }

  IapException _stateError(IapErrorCode code) => IapException(
    code: code,
    store: store,
    message: switch (code) {
      IapErrorCode.disposed => 'Billing client has been disposed.',
      IapErrorCode.notInitialized =>
        'Call initialize() before billing operations.',
      IapErrorCode.operationInProgress =>
        'Another billing operation is already in progress.',
      IapErrorCode.subscriptionUnavailable =>
        'Subscriptions are unavailable for this store/configuration.',
      _ => 'Invalid billing client state.',
    },
  );

  IapException _fromPlatform(services.PlatformException error) {
    final details = _decodePlatformDetails(error.details);
    final code = _errorCode(error.code);
    if (code == IapErrorCode.notInitialized) {
      _initialized = false;
      _initialization = null;
    }
    return IapException(
      code: code,
      store: store,
      message: error.message ?? '${store.name} billing operation failed.',
      nativeCode: details['nativeCode'],
      nativeMessage: details['nativeMessage']?.toString(),
      nativeExceptionType: details['nativeExceptionType']?.toString(),
      details: details,
    );
  }

  IapErrorCode _errorCode(String value) {
    for (final code in IapErrorCode.values) {
      if (code.name == value) {
        return code;
      }
    }
    return IapErrorCode.unknown;
  }

  IapProduct _decodeProduct(Object? value) {
    final map = _asStringMap(value, 'product');
    try {
      return IapProduct(
        id: map['id']! as String,
        type: _productTypeFromWire(map['type']! as String),
        title: map['title'] as String? ?? '',
        description: map['description'] as String? ?? '',
        price: map['price'] as String? ?? '',
      );
    } on Object catch (error) {
      throw _invalidResponse('Malformed product payload: $error');
    }
  }

  IapPurchase _decodePurchase(Object? value, IapProductType type) {
    final map = _asStringMap(value, 'purchase');
    try {
      final stateValue = map['state'];
      final state = switch (stateValue) {
        'purchased' || 0 => IapPurchaseState.purchased,
        'refunded' => IapPurchaseState.refunded,
        _ => IapPurchaseState.unknown,
      };
      return IapPurchase(
        store: store,
        productId: map['productId']! as String,
        type: type,
        token: map['token']! as String,
        orderId: map['orderId'] as String?,
        payload: map['payload'] as String?,
        packageName: map['packageName'] as String?,
        state: state,
        purchaseTime: DateTime.fromMillisecondsSinceEpoch(
          map['purchaseTime']! as int,
        ),
        rawReceipt: map['rawReceipt'] as String?,
        signature: map['signature'] as String?,
      );
    } on Object catch (error) {
      throw _invalidResponse('Malformed purchase payload: $error');
    }
  }

  Map<String, Object?> _asStringMap(Object? value, String label) {
    if (value is! Map) {
      throw _invalidResponse('Expected $label map.');
    }
    try {
      return Map<String, Object?>.from(value);
    } on Object catch (error) {
      throw _invalidResponse('Malformed $label map: $error');
    }
  }

  Map<String, Object?> _decodePlatformDetails(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    try {
      return Map<String, Object?>.from(value);
    } on Object {
      return <String, Object?>{'rawDetails': value.toString()};
    }
  }

  IapException _invalidResponse(String message) => IapException(
    code: IapErrorCode.invalidResponse,
    store: store,
    message: message,
  );

  static void _validateIds(Set<String> ids) {
    if (ids.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(
        ids,
        'productIds',
        'Product IDs must not be blank.',
      );
    }
  }

  static void _validatePurchaseRequest(IapPurchaseRequest request) {
    if (request.productId.trim().isEmpty) {
      throw ArgumentError.value(
        request.productId,
        'productId',
        'Must not be empty.',
      );
    }
    final token = request.dynamicPriceToken;
    if (token != null && token.trim().isEmpty) {
      throw ArgumentError.value(
        token,
        'dynamicPriceToken',
        'Must not be empty when provided.',
      );
    }
  }
}

/// Retrieves the store selected for the current build via `--dart-define`.
IapStore _selectedBuildStore() {
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

String _productTypeWireName(IapProductType type) => switch (type) {
  IapProductType.inApp => 'inapp',
  IapProductType.subscription => 'subs',
};

IapProductType _productTypeFromWire(String value) => switch (value) {
  'inapp' => IapProductType.inApp,
  'subs' => IapProductType.subscription,
  _ => throw FormatException('Unknown product type: $value'),
};
