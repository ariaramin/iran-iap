import 'package:flutter/services.dart' as services;
import 'package:iran_iap/src/core/config.dart';
import 'package:iran_iap/src/core/error.dart';
import 'package:iran_iap/src/core/store.dart';
import 'package:iran_iap/src/core/store_delegate.dart';
import 'package:iran_iap/src/models/capabilities.dart';
import 'package:iran_iap/src/models/product.dart';
import 'package:iran_iap/src/models/purchase.dart';
import 'package:iran_iap/src/models/purchase_outcome.dart';
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
  /// Throws [ArgumentError] for invalid configuration and [IapException] for
  /// store availability or platform failures. A client that has been
  /// [dispose]d cannot be initialized again.
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
/// `dart run iran_iap build apk --store myket -- --release`.
final class IranIap implements IranIapClient {
  /// Creates a billing client for the store selected in this build.
  ///
  /// This constructor throws [StateError] when the application was compiled
  /// without a valid `IRAN_IAP_STORE` value. Use the package CLI or Flutter's
  /// `--dart-define=IRAN_IAP_STORE=...` option.
  ///
  /// [channel] is the [services.MethodChannel] used for platform interop.
  /// Primarily used for testing; default is `dev.iraniap/iran_iap`.
  IranIap({
    this.config = const IranIapConfig(),
    services.MethodChannel? channel,
  }) : _store = IapStore.current,
       _delegate = _createDelegate(IapStore.current),
       _channel = channel ?? const services.MethodChannel(_channelName);

  static const String _channelName = 'dev.iraniap/iran_iap';

  /// Configuration applied when [initialize] first connects.
  final IranIapConfig config;

  final IapStore _store;
  final services.MethodChannel _channel;
  final StoreDelegate _delegate;

  _BillingState _state = _BillingState.ready;
  Future<void>? _initialization;
  IapCapabilities _capabilities = const IapCapabilities();

  @override
  IapStore get store => _store;

  @override
  bool get isInitialized => _state == _BillingState.initialized;

  @override
  IapCapabilities get capabilities => _capabilities;

  @override
  Future<void> initialize() async {
    if (_state == _BillingState.disposed) {
      throw _stateError(IapErrorCode.disposed);
    }
    if (_state == _BillingState.initialized) {
      return;
    }
    return _initialization ??= _initializeOnce().whenComplete(() {
      if (!isInitialized) {
        _initialization = null;
      }
    });
  }

  Future<void> _initializeOnce() async {
    _delegate.validateConfig(config);
    final nativeStore = await _invoke<String>('selectedStore');
    if (nativeStore != store.name) {
      throw IapException(
        code: IapErrorCode.configuration,
        store: store,
        message:
            'Dart selected ${store.name}, but Android build '
            'contains ${nativeStore ?? 'no'} implementation.',
      );
    }

    final raw = await _invoke<Map<Object?, Object?>>(
      'initialize',
      _delegate.platformConfigArguments(config),
    );
    _capabilities = _decode(
      () => IapCapabilities.fromMap(_asStringMap(raw, 'capabilities')),
    );
    _state = _BillingState.initialized;
  }

  @override
  Future<List<IapProduct>> queryProducts(
    Set<String> productIds, {
    required IapProductType type,
  }) async {
    _ensureReady();
    if (productIds.isEmpty) return const [];
    _validateIds(productIds);
    _ensureTypeSupported(type);

    return _guard(() async {
      final raw = await _invoke<List<Object?>>('queryProducts', {
        'productIds': productIds.toList(growable: false),
        'type': type.wireName,
      });
      return _decode(
        () => (raw ?? const [])
            .map((v) => IapProduct.fromMap(_asStringMap(v, 'product')))
            .toList(growable: false),
      );
    });
  }

  @override
  Future<PurchaseOutcome> purchase(IapPurchaseRequest request) async {
    _ensureReady();
    request.validate();
    _delegate.validatePurchaseRequest(request);
    _ensureTypeSupported(request.type);

    return _guard(() async {
      final raw = await _invoke<Map<Object?, Object?>>('purchase', {
        'productId': request.productId,
        'type': request.type.wireName,
        'payload': request.payload,
        'dynamicPriceToken': request.dynamicPriceToken,
      });
      return _decode(() {
        final map = _asStringMap(raw, 'purchase');
        return switch (map['status']) {
          'completed' => PurchaseCompleted(
            IapPurchase.fromMap(
              map: _asStringMap(map['purchase'], 'purchase'),
              type: request.type,
              store: store,
            ),
          ),
          'cancelled' => const PurchaseCancelled(),
          _ => throw _invalidResponse(
            'Unknown purchase status: ${map['status']}',
          ),
        };
      });
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
        {'type': type.wireName},
      );
      return _decode(
        () => (raw ?? const [])
            .map(
              (v) => IapPurchase.fromMap(
                map: _asStringMap(v, 'purchase'),
                type: type,
                store: store,
              ),
            )
            .toList(growable: false),
      );
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

    await _guard(() => _delegate.consume(purchase: purchase, invoke: _invoke));
  }

  @override
  Future<void> dispose() async {
    if (_state == _BillingState.disposed) return;
    await _invoke<void>('dispose');
    _state = _BillingState.disposed;
    _initialization = null;
    _capabilities = const IapCapabilities();
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on services.PlatformException catch (e) {
      final error = IapException.fromPlatform(exception: e, store: store);
      if (error.code == IapErrorCode.notInitialized) {
        _state = _BillingState.ready;
        _initialization = null;
      }
      throw error;
    } on services.MissingPluginException catch (e) {
      throw IapException(
        code: IapErrorCode.unsupportedPlatform,
        store: store,
        message: 'iran_iap is unavailable on this platform.',
        nativeMessage: e.message,
        nativeExceptionType: 'MissingPluginException',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (_state == _BillingState.busy) {
      throw _stateError(IapErrorCode.operationInProgress);
    }
    final previous = _state;
    _state = _BillingState.busy;
    try {
      return await action();
    } finally {
      if (_state == _BillingState.busy) {
        _state = previous;
      }
    }
  }

  void _ensureReady() {
    if (_state == _BillingState.disposed) {
      throw _stateError(IapErrorCode.disposed);
    }
    if (_state == _BillingState.ready) {
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
      IapErrorCode.notInitialized => 'Call initialize() before operations.',
      IapErrorCode.operationInProgress => 'Billing operation in progress.',
      IapErrorCode.subscriptionUnavailable => 'Subscriptions unavailable.',
      _ => 'Invalid billing client state.',
    },
  );

  Map<String, Object?> _asStringMap(Object? value, String label) {
    if (value is! Map) throw _invalidResponse('Expected $label map.');
    return Map<String, Object?>.from(value);
  }

  IapException _invalidResponse(String message) => IapException(
    code: IapErrorCode.invalidResponse,
    store: store,
    message: message,
  );

  T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on IapException {
      rethrow;
    } on Object catch (error) {
      throw _invalidResponse('Malformed native response: $error');
    }
  }

  static void _validateIds(Set<String> ids) {
    if (ids.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(ids, 'productIds', 'IDs must not be blank.');
    }
  }

  static StoreDelegate _createDelegate(IapStore store) => switch (store) {
    IapStore.bazaar => const BazaarDelegate(),
    IapStore.myket => const MyketDelegate(),
  };
}

enum _BillingState { ready, initialized, busy, disposed }
