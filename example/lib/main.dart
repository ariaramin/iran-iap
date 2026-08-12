import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iran_iap/iran_iap.dart';

const _selectedStoreName = String.fromEnvironment('IRAN_IAP_STORE');
const _publicKey = String.fromEnvironment('IAP_PUBLIC_KEY');

/// Runs the `iran_iap` example application.
void main() {
  runApp(const _ExampleApp());
}

class _ExampleApp extends StatefulWidget {
  const _ExampleApp();

  @override
  State<_ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<_ExampleApp> {
  late final IranIapClient _iap;
  final _productIdController = TextEditingController(text: 'premium_monthly');

  IapProductType _type = IapProductType.inApp;
  IapPurchase? _lastPurchase;
  String _status = 'Ready to initialize';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _iap = IranIap(
      config: IranIapConfig(
        storePublicKey: _publicKey.isEmpty ? null : _publicKey,
      ),
    );
  }

  Future<void> _initialize() async {
    await _run(() async {
      await _iap.initialize();
      return 'Initialized ${_iap.store.name}. '
          'Subscriptions: ${_iap.capabilities.supportsSubscriptions}';
    });
  }

  Future<void> _queryProduct() async {
    await _run(() async {
      final id = _productIdController.text.trim();
      final products = await _iap.queryProducts({id}, type: _type);
      if (products.isEmpty) {
        return 'No product returned for `$id`.';
      }
      final product = products.first;
      return '${product.title}\n${product.price}\n${product.description}';
    });
  }

  Future<void> _purchase() async {
    await _run(() async {
      final outcome = await _iap.purchase(
        IapPurchaseRequest(
          productId: _productIdController.text.trim(),
          type: _type,
          payload: 'iran_iap_example',
        ),
      );
      return switch (outcome) {
        PurchaseCompleted(:final purchase) => _rememberPurchase(purchase),
        PurchaseCancelled() => 'Purchase cancelled by the user.',
      };
    });
  }

  Future<void> _queryPurchases() async {
    await _run(() async {
      final purchases = await _iap.queryPurchases(type: _type);
      if (purchases.isEmpty) {
        return 'No owned ${_type.name} purchases returned.';
      }
      _lastPurchase = purchases.first;
      return 'Owned purchases: ${purchases.length}\n'
          'First: ${purchases.first.productId}';
    });
  }

  Future<void> _consumeLast() async {
    await _run(() async {
      final purchase = _lastPurchase;
      if (purchase == null) {
        return 'No purchase is available to consume.';
      }
      if (purchase.type != IapProductType.inApp) {
        return 'Subscriptions cannot be consumed.';
      }

      // Production apps should verify/persist purchase evidence on a trusted
      // backend before consuming. This button only demonstrates the API.
      await _iap.consume(purchase);
      _lastPurchase = null;
      return 'Consumed ${purchase.productId}.';
    });
  }

  String _rememberPurchase(IapPurchase purchase) {
    _lastPurchase = purchase;
    return 'Purchase completed: ${purchase.productId}\n'
        'Verify this purchase on your backend before granting entitlement.';
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final message = await action();
      if (!mounted) {
        return;
      }
      setState(() => _status = message);
    } on IapException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '${error.code.name}: ${error.message}\n'
            '${error.nativeExceptionType ?? ''}';
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = 'Error: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _productIdController.dispose();
    unawaited(_iap.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeLabel = _selectedStoreName.isEmpty
        ? 'No store selected'
        : _selectedStoreName;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('iran_iap example')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Store: $storeLabel',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_status),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _productIdController,
                decoration: const InputDecoration(
                  labelText: 'Product ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<IapProductType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Product type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: IapProductType.inApp,
                    child: Text('In-app product'),
                  ),
                  DropdownMenuItem(
                    value: IapProductType.subscription,
                    child: Text('Subscription'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _type = value);
                        }
                      },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _initialize,
                child: const Text('Initialize'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _queryProduct,
                child: const Text('Query product'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _purchase,
                child: const Text('Purchase'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _queryPurchases,
                child: const Text('Query owned purchases'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _consumeLast,
                child: const Text('Consume last in-app purchase'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
