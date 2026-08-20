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

  test(
    'payment URL is forwarded without requiring billing initialization',
    () async {
      _mockReady(
        messenger,
        onMethod: (call) async {
          if (call.method == 'openPaymentUrl') {
            expect(call.arguments, <String, Object?>{
              'paymentUrl':
                  'https://payments.example.test/checkout?session=one',
            });
          }
          return null;
        },
      );

      final iap = _client();
      await iap.openPaymentUrl(
        const IapUrlPaymentRequest(
          paymentUrl: ' https://payments.example.test/checkout?session=one ',
        ),
      );
    },
  );

  test(
    'payment URLs reject unsafe or malformed values before native calls',
    () async {
      var paymentCallCount = 0;
      _mockReady(
        messenger,
        onMethod: (call) async {
          if (call.method == 'openPaymentUrl') {
            paymentCallCount++;
          }
          return null;
        },
      );
      final iap = _client();
      for (final paymentUrl in const [
        '',
        'not a URL',
        'http://payments.example.test/checkout',
        'javascript:alert(1)',
        'https://user:password@payments.example.test/checkout',
      ]) {
        await expectLater(
          iap.openPaymentUrl(IapUrlPaymentRequest(paymentUrl: paymentUrl)),
          throwsA(isA<PaymentConfigurationException>()),
        );
      }

      expect(paymentCallCount, 0);
    },
  );

  test(
    'payment URLs support gateway-specific paths, queries, and fragments',
    () {
      for (final request in const [
        IapUrlPaymentRequest(
          paymentUrl: 'https://payments.example.test/checkout?session=one',
        ),
        IapUrlPaymentRequest(
          paymentUrl: 'https://merchant.example.test/pay/order/123#complete',
        ),
        IapUrlPaymentRequest(
          paymentUrl: 'https://gateway.example.test:8443/pay?state=one%2Ftwo',
        ),
      ]) {
        expect(request.validate, returnsNormally);
      }
    },
  );

  test('native payment URL failures use the stable error contract', () async {
    _mockReady(
      messenger,
      onMethod: (call) async {
        if (call.method == 'openPaymentUrl') {
          throw PlatformException(
            code: 'activityUnavailable',
            message: 'No browser is available',
          );
        }
        return null;
      },
    );
    final iap = _client();
    await expectLater(
      iap.openPaymentUrl(
        const IapUrlPaymentRequest(
          paymentUrl: 'https://payments.example.test/checkout?session=one',
        ),
      ),
      throwsA(
        isA<IapException>()
            .having(
              (error) => error.code,
              'code',
              IapErrorCode.activityUnavailable,
            )
            .having(
              (error) => error.message,
              'message',
              'No browser is available',
            ),
      ),
    );
  });

  test(
    'payment session forwards a validated URL and resolves its callback',
    () async {
      final calls = <String>[];
      _mockReady(
        messenger,
        onMethod: (call) async {
          calls.add(call.method);
          if (call.method == 'registerPaymentSession') {
            final arguments = call.arguments! as Map<Object?, Object?>;
            expect(arguments['expiresAt'], isA<int>());
          }
          return null;
        },
      );
      final iap = _client();
      final pending = iap.startPayment(
        const IapUrlPaymentRequest(
          paymentUrl: 'https://payments.example.test/checkout?session=one',
        ),
        callbackConfig: _callbackConfig(),
      );
      await Future<void>.delayed(Duration.zero);

      await _sendCallback(
        messenger,
        'myapp://payments/complete?state=state-0123456789abcdef&status=success&transaction_id=tx-1',
      );

      final result = await pending;
      expect(result.status, PaymentStatus.success);
      expect(result.transactionId, 'tx-1');
      expect(
        calls,
        containsAllInOrder(<String>[
          'registerPaymentSession',
          'consumePendingPaymentCallback',
          'openPaymentUrl',
          'clearPaymentSession',
        ]),
      );
    },
  );

  test(
    'payment session rejects concurrent starts and can be cancelled',
    () async {
      _mockReady(messenger);
      final iap = _client();
      final pending = iap.startPayment(
        const IapUrlPaymentRequest(paymentUrl: 'https://payments.example.test'),
        callbackConfig: _callbackConfig(),
      );

      await expectLater(
        iap.startPayment(
          const IapUrlPaymentRequest(
            paymentUrl: 'https://payments.example.test',
          ),
          callbackConfig: _callbackConfig(),
        ),
        throwsA(isA<PaymentInProgressException>()),
      );
      await iap.cancelPayment();
      expect((await pending).status, PaymentStatus.cancelled);
    },
  );

  test('native active session becomes a typed payment conflict', () async {
    _mockReady(
      messenger,
      onMethod: (call) async {
        if (call.method == 'registerPaymentSession') {
          throw PlatformException(
            code: 'operationInProgress',
            message: 'Another payment session is active.',
          );
        }
        return null;
      },
    );

    await expectLater(
      _client().startPayment(
        const IapUrlPaymentRequest(paymentUrl: 'https://payments.example.test'),
        callbackConfig: _callbackConfig(),
      ),
      throwsA(isA<PaymentInProgressException>()),
    );
  });

  test('callback contract rejects invalid returns', () {
    final config = _callbackConfig();
    for (final url in <String>[
      'myapp://payments/complete?state=wrong&status=success',
      'myapp://payments/other?state=state-0123456789abcdef&status=success',
      'myapp://payments/complete?state=state-0123456789abcdef&status=unknown',
      'myapp://payments/complete?state=state-0123456789abcdef&status=success&status=failed',
      'https://payments/complete?state=state-0123456789abcdef&status=success',
    ]) {
      expect(
        () => config.parseCallback(Uri.parse(url)),
        throwsA(isA<PaymentCallbackException>()),
      );
    }
  });

  test('callback contract supports configured callback values', () {
    const config = PaymentCallbackConfig(
      scheme: 'https',
      host: 'merchant.example.test',
      path: '/payment/complete',
      expectedState: 'state-0123456789abcdef',
      successValues: {'ok', 'paid'},
      failureValues: {'declined'},
      cancelValues: {'aborted'},
    );
    expect(
      config
          .parseCallback(
            Uri.parse(
              'https://merchant.example.test/payment/complete?state=state-0123456789abcdef&status=paid',
            ),
          )
          .status,
      PaymentStatus.success,
    );
    expect(
      config
          .parseCallback(
            Uri.parse(
              'https://merchant.example.test/payment/complete?state=state-0123456789abcdef&status=aborted',
            ),
          )
          .status,
      PaymentStatus.cancelled,
    );
  });

  test('payment recovery returns a verified persisted callback', () async {
    final config = _callbackConfig();
    _mockReady(
      messenger,
      onMethod: (call) async {
        if (call.method == 'recoverPaymentSession') {
          return <String, Object?>{
            'session': config.toMap(),
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
            'callbackUrl':
                'myapp://payments/complete?state=state-0123456789abcdef&status=failed',
          };
        }
        return null;
      },
    );

    final result = await _client().recoverPaymentResult();
    expect(result!.status, PaymentStatus.failed);
  });

  test('payment URLs cannot be opened after disposal', () async {
    _mockReady(messenger);
    final iap = _client();
    await iap.dispose();

    await expectLater(
      iap.openPaymentUrl(
        const IapUrlPaymentRequest(
          paymentUrl: 'https://payments.example.test/checkout?session=one',
        ),
      ),
      throwsA(
        isA<IapException>().having(
          (error) => error.code,
          'code',
          IapErrorCode.disposed,
        ),
      ),
    );
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

PaymentCallbackConfig _callbackConfig() => const PaymentCallbackConfig(
  scheme: 'myapp',
  host: 'payments',
  path: '/complete',
  expectedState: 'state-0123456789abcdef',
);

Future<void> _sendCallback(
  TestDefaultBinaryMessenger messenger,
  String url,
) => messenger.handlePlatformMessage(
  _channel.name,
  _channel.codec.encodeMethodCall(
    MethodCall('paymentCallback', <String, Object?>{'url': url}),
  ),
  null,
);
