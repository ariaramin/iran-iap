import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iran_iap/iran_iap.dart';

const _storeName = String.fromEnvironment('IRAN_IAP_STORE');
const _channel = MethodChannel('dev.iraniap/iran_iap');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (!const {'bazaar', 'myket'}.contains(_storeName)) {
    test(
      'store-specific suite requires IRAN_IAP_STORE',
      () {},
      skip: 'Run with --dart-define=IRAN_IAP_STORE=bazaar|myket.',
    );
    return;
  }

  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
  });

  test('initialize is idempotent and exposes capabilities', () async {
    var initializeCount = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'selectedStore') {
        return _storeName;
      }
      if (call.method == 'initialize') {
        initializeCount++;
        return <String, Object?>{
          'supportsSubscriptions': true,
          'supportsConsumption': true,
          'supportsDynamicPricing': _storeName == 'bazaar',
        };
      }
      return null;
    });

    final iap = _client();
    await Future.wait([iap.initialize(), iap.initialize()]);
    await iap.initialize();

    expect(initializeCount, 1);
    expect(iap.isInitialized, isTrue);
    expect(iap.capabilities.supportsSubscriptions, isTrue);
    expect(iap.capabilities.supportsConsumption, isTrue);
    expect(iap.capabilities.supportsDynamicPricing, _storeName == 'bazaar');
  });

  test('initialization can be retried after a native failure', () async {
    var initializeCount = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'selectedStore') {
        return _storeName;
      }
      if (call.method == 'initialize') {
        initializeCount++;
        if (initializeCount == 1) {
          throw PlatformException(
            code: 'serviceUnavailable',
            message: 'Temporary billing outage',
          );
        }
        return <String, Object?>{
          'supportsSubscriptions': true,
          'supportsConsumption': true,
          'supportsDynamicPricing': _storeName == 'bazaar',
        };
      }
      return null;
    });

    final iap = _client();
    await expectLater(
      iap.initialize(),
      throwsA(
        isA<IapException>().having(
          (error) => error.code,
          'code',
          IapErrorCode.serviceUnavailable,
        ),
      ),
    );

    expect(iap.isInitialized, isFalse);
    await iap.initialize();
    expect(initializeCount, 2);
    expect(iap.isInitialized, isTrue);
  });

  test('native disconnect invalidates local initialized state', () async {
    var initializeCount = 0;
    _mockReady(
      messenger,
      onMethod: (call) async {
        if (call.method == 'initialize') {
          initializeCount++;
          return _capabilities();
        }
        if (call.method == 'queryPurchases') {
          throw PlatformException(
            code: 'notInitialized',
            message: 'Billing connection was lost',
          );
        }
        return null;
      },
    );

    final iap = _client();
    await iap.initialize();
    expect(iap.isInitialized, isTrue);

    await expectLater(
      iap.queryPurchases(type: IapProductType.inApp),
      throwsA(
        isA<IapException>().having(
          (error) => error.code,
          'code',
          IapErrorCode.notInitialized,
        ),
      ),
    );

    expect(iap.isInitialized, isFalse);
    await iap.initialize();
    expect(initializeCount, 2);
    expect(iap.isInitialized, isTrue);
  });

  test('purchase cancellation is a typed outcome', () async {
    _mockReady(
      messenger,
      onMethod: (call) async {
        if (call.method == 'purchase') {
          return <String, Object?>{'status': 'cancelled'};
        }
        return null;
      },
    );

    final iap = _client();
    await iap.initialize();
    final outcome = await iap.purchase(
      const IapPurchaseRequest(
        productId: 'premium',
        type: IapProductType.inApp,
      ),
    );

    expect(outcome, isA<PurchaseCancelled>());
  });

  test('native diagnostics survive stable error mapping', () async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'selectedStore') {
        return _storeName;
      }
      if (call.method == 'initialize') {
        throw PlatformException(
          code: 'storeNotInstalled',
          message: 'Store is missing',
          details: <String, Object?>{
            'nativeCode': 404,
            'nativeMessage': 'native detail',
            'nativeExceptionType': 'vendor.StoreNotFoundException',
          },
        );
      }
      return null;
    });

    final iap = _client();
    await expectLater(
      iap.initialize(),
      throwsA(
        isA<IapException>()
            .having(
              (error) => error.code,
              'code',
              IapErrorCode.storeNotInstalled,
            )
            .having((error) => error.nativeCode, 'nativeCode', 404)
            .having(
              (error) => error.nativeExceptionType,
              'nativeExceptionType',
              'vendor.StoreNotFoundException',
            ),
      ),
    );
  });

  test('blank product ids fail before native query', () async {
    _mockReady(messenger);
    final iap = _client();
    await iap.initialize();

    await expectLater(
      iap.queryProducts({' '}, type: IapProductType.inApp),
      throwsArgumentError,
    );
  });

  test('unsupported subscription query fails before native query', () async {
    var queryCount = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'selectedStore') {
        return _storeName;
      }
      if (call.method == 'initialize') {
        return _capabilities(subscriptions: false);
      }
      if (call.method == 'queryProducts') {
        queryCount++;
      }
      return null;
    });

    final iap = _client();
    await iap.initialize();

    await expectLater(
      iap.queryProducts({'premium'}, type: IapProductType.subscription),
      throwsA(
        isA<IapException>().having(
          (error) => error.code,
          'code',
          IapErrorCode.subscriptionUnavailable,
        ),
      ),
    );
    expect(queryCount, 0);
  });

  test('malformed native product becomes invalidResponse', () async {
    _mockReady(
      messenger,
      onMethod: (call) async {
        if (call.method == 'queryProducts') {
          return <Object?>[
            <String, Object?>{'id': 42},
          ];
        }
        return null;
      },
    );
    final iap = _client();
    await iap.initialize();

    await expectLater(
      iap.queryProducts({'premium'}, type: IapProductType.inApp),
      throwsA(
        isA<IapException>().having(
          (error) => error.code,
          'code',
          IapErrorCode.invalidResponse,
        ),
      ),
    );
  });

  test('overlapping billing operations are rejected', () async {
    final firstQuery = Completer<List<Object?>>();
    _mockReady(
      messenger,
      onMethod: (call) async {
        if (call.method == 'queryProducts') {
          return firstQuery.future;
        }
        return null;
      },
    );

    final iap = _client();
    await iap.initialize();

    final pending = iap.queryProducts({'one'}, type: IapProductType.inApp);
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      iap.queryProducts({'two'}, type: IapProductType.inApp),
      throwsA(
        isA<IapException>().having(
          (error) => error.code,
          'code',
          IapErrorCode.operationInProgress,
        ),
      ),
    );

    firstQuery.complete(const <Object?>[]);
    await pending;
  });

  test('a purchase from another store cannot be consumed', () async {
    _mockReady(messenger);
    final iap = _client();
    await iap.initialize();

    const otherStore = _storeName == 'bazaar'
        ? IapStore.myket
        : IapStore.bazaar;
    final purchase = IapPurchase(
      store: otherStore,
      productId: 'coins',
      type: IapProductType.inApp,
      token: 'token',
      state: IapPurchaseState.purchased,
      purchaseTime: DateTime.fromMillisecondsSinceEpoch(1),
    );

    await expectLater(iap.consume(purchase), throwsArgumentError);
  });

  test(
    'dynamic price token is rejected by Myket before native purchase',
    () async {
      if (_storeName != 'myket') {
        return;
      }
      _mockReady(messenger);
      final iap = _client();
      await iap.initialize();

      await expectLater(
        iap.purchase(
          const IapPurchaseRequest(
            productId: 'coins',
            type: IapProductType.inApp,
            dynamicPriceToken: 'dynamic-token',
          ),
        ),
        throwsA(
          isA<IapException>().having(
            (error) => error.code,
            'code',
            IapErrorCode.featureUnavailable,
          ),
        ),
      );
    },
  );

  test('dispose is idempotent and prevents reuse', () async {
    var disposeCount = 0;
    _mockReady(
      messenger,
      onMethod: (call) async {
        if (call.method == 'dispose') {
          disposeCount++;
        }
        return null;
      },
    );

    final iap = _client();
    await iap.initialize();
    await iap.dispose();
    await iap.dispose();

    expect(disposeCount, 1);
    expect(iap.isInitialized, isFalse);
    await expectLater(
      iap.initialize(),
      throwsA(
        isA<IapException>().having(
          (error) => error.code,
          'code',
          IapErrorCode.disposed,
        ),
      ),
    );
  });

  test('store-specific configuration is validated', () async {
    _mockReady(messenger);

    final iap = _storeName == 'myket'
        ? IranIap()
        : IranIap(
            config: const IranIapConfig(
              bazaarSecurityMode: BazaarSecurityMode.localVerification,
            ),
          );

    await expectLater(iap.initialize(), throwsArgumentError);
  });

  test('legacy numeric refunded state is normalized', () {
    expect(IapPurchaseState.fromWire(2), IapPurchaseState.refunded);
  });
}

IranIap _client() {
  if (_storeName == 'myket') {
    return IranIap(
      config: const IranIapConfig(storePublicKey: 'public-test-key'),
    );
  }
  return IranIap();
}

void _mockReady(
  TestDefaultBinaryMessenger messenger, {
  Future<Object?> Function(MethodCall call)? onMethod,
}) {
  messenger.setMockMethodCallHandler(_channel, (call) async {
    if (call.method == 'selectedStore') {
      return _storeName;
    }
    final customResponse = await onMethod?.call(call);
    if (customResponse != null) {
      return customResponse;
    }
    if (call.method == 'initialize') {
      return _capabilities();
    }
    return null;
  });
}

Map<String, Object?> _capabilities({bool subscriptions = true}) =>
    <String, Object?>{
      'supportsSubscriptions': subscriptions,
      'supportsConsumption': true,
      'supportsDynamicPricing': _storeName == 'bazaar',
    };
