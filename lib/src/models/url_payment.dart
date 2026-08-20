import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';

/// Input for a hosted payment URL flow.
@immutable
final class IapUrlPaymentRequest {
  /// Creates a payment URL request.
  const IapUrlPaymentRequest({required this.paymentUrl});

  /// HTTPS URL generated for this checkout.
  final String paymentUrl;

  /// Validates the payment URL before it reaches the platform implementation.
  void validate() {
    final url = paymentUrl.trim();
    final uri = Uri.tryParse(url);
    if (url.isEmpty ||
        uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const PaymentConfigurationException(
        'paymentUrl must be an HTTPS URL without embedded credentials.',
      );
    }
  }

  /// The validated URL without surrounding whitespace.
  String get normalizedPaymentUrl => paymentUrl.trim();
}

/// Expected shape of a payment return deep link.
@immutable
final class PaymentCallbackConfig {
  /// Creates a callback contract.
  const PaymentCallbackConfig({
    required this.scheme,
    required this.host,
    required this.path,
    required this.expectedState,
    this.stateParameterName = 'state',
    this.statusParameterName = 'status',
    this.transactionIdParameterName = 'transaction_id',
    this.successValues = const {'success'},
    this.failureValues = const {'failed'},
    this.cancelValues = const {'cancelled', 'canceled'},
  });

  /// Decodes a platform-persisted callback contract.
  factory PaymentCallbackConfig.fromMap(Map<Object?, Object?> map) {
    String stringValue(String name) {
      final value = map[name];
      if (value is! String) {
        throw const PaymentCallbackException(
          'Persisted callback is malformed.',
        );
      }
      return value;
    }

    Set<String> stringSet(String name) {
      final values = map[name];
      if (values is! List || values.any((value) => value is! String)) {
        throw const PaymentCallbackException(
          'Persisted callback is malformed.',
        );
      }
      return values.cast<String>().toSet();
    }

    return PaymentCallbackConfig(
      scheme: stringValue('scheme'),
      host: stringValue('host'),
      path: stringValue('path'),
      expectedState: stringValue('expectedState'),
      stateParameterName: stringValue('stateParameterName'),
      statusParameterName: stringValue('statusParameterName'),
      transactionIdParameterName: stringValue('transactionIdParameterName'),
      successValues: stringSet('successValues'),
      failureValues: stringSet('failureValues'),
      cancelValues: stringSet('cancelValues'),
    );
  }

  /// URL scheme expected in the callback, such as `myapp` or `https`.
  final String scheme;

  /// URL host expected in the callback.
  final String host;

  /// Exact URL path expected in the callback.
  final String path;

  /// Server-generated state value that must be returned by the payment flow.
  final String expectedState;

  /// Query parameter containing [expectedState].
  final String stateParameterName;

  /// Query parameter containing the provider-defined outcome.
  final String statusParameterName;

  /// Optional query parameter containing a transaction identifier.
  final String transactionIdParameterName;

  /// Values that represent a successful client-side outcome.
  final Set<String> successValues;

  /// Values that represent a failed client-side outcome.
  final Set<String> failureValues;

  /// Values that represent a cancelled client-side outcome.
  final Set<String> cancelValues;

  /// Creates a cryptographically secure state value for a payment session.
  static String generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Validates this callback contract.
  void validate() {
    if (scheme.trim().isEmpty ||
        host.trim().isEmpty ||
        !path.startsWith('/') ||
        expectedState.trim().length < 16 ||
        stateParameterName.trim().isEmpty ||
        statusParameterName.trim().isEmpty ||
        transactionIdParameterName.trim().isEmpty) {
      throw const PaymentConfigurationException(
        'Callback scheme, host, absolute path, parameter names, and a '
        'state value of at least 16 characters are required.',
      );
    }
    final success = _normalizedValues(successValues);
    final failure = _normalizedValues(failureValues);
    final cancelled = _normalizedValues(cancelValues);
    if (success.isEmpty ||
        failure.isEmpty ||
        cancelled.isEmpty ||
        success.intersection(failure).isNotEmpty ||
        success.intersection(cancelled).isNotEmpty ||
        failure.intersection(cancelled).isNotEmpty) {
      throw const PaymentConfigurationException(
        'Callback outcome values must be non-empty and disjoint.',
      );
    }
  }

  /// Parses and validates a callback URL for this contract.
  PaymentResult parseCallback(Uri callbackUrl) {
    validate();
    if (callbackUrl.scheme.toLowerCase() != scheme.trim().toLowerCase() ||
        callbackUrl.host.toLowerCase() != host.trim().toLowerCase() ||
        callbackUrl.path != path ||
        callbackUrl.userInfo.isNotEmpty) {
      throw const PaymentCallbackException('Callback URL does not match.');
    }
    if (_singleQueryParameter(callbackUrl, stateParameterName) !=
        expectedState) {
      throw const PaymentCallbackException('Callback state does not match.');
    }
    final status = _singleQueryParameter(
      callbackUrl,
      statusParameterName,
    ).toLowerCase();
    final resultStatus = switch (status) {
      _ when _normalizedValues(successValues).contains(status) =>
        PaymentStatus.success,
      _ when _normalizedValues(failureValues).contains(status) =>
        PaymentStatus.failed,
      _ when _normalizedValues(cancelValues).contains(status) =>
        PaymentStatus.cancelled,
      _ => throw const PaymentCallbackException('Callback status is unknown.'),
    };
    final transactionIds =
        callbackUrl.queryParametersAll[transactionIdParameterName];
    if (transactionIds != null && transactionIds.length > 1) {
      throw const PaymentCallbackException(
        'Callback contains duplicate transaction identifiers.',
      );
    }
    return PaymentResult(
      status: resultStatus,
      sessionId: expectedState,
      callbackUrl: callbackUrl,
      transactionId: transactionIds == null || transactionIds.isEmpty
          ? null
          : transactionIds.single,
    );
  }

  /// Encodes the callback contract for platform-side session recovery.
  Map<String, Object> toMap() => <String, Object>{
    'scheme': scheme.trim(),
    'host': host.trim(),
    'path': path,
    'expectedState': expectedState,
    'stateParameterName': stateParameterName.trim(),
    'statusParameterName': statusParameterName.trim(),
    'transactionIdParameterName': transactionIdParameterName.trim(),
    'successValues': successValues.toList(growable: false),
    'failureValues': failureValues.toList(growable: false),
    'cancelValues': cancelValues.toList(growable: false),
  };
}

/// Client-visible state of a payment URL session.
enum PaymentStatus {
  /// The callback reported a successful client-side outcome.
  success,

  /// The callback reported a failed client-side outcome.
  failed,

  /// The callback reported cancellation or the application cancelled it.
  cancelled,

  /// No callback arrived before the configured deadline.
  timedOut,
}

/// Client-side result of a correlated payment callback.
///
/// This is not proof of settlement. Verify valuable payments with a trusted
/// backend or payment provider before granting entitlements.
@immutable
final class PaymentResult {
  /// Creates a payment result.
  const PaymentResult({
    required this.status,
    required this.sessionId,
    this.callbackUrl,
    this.transactionId,
  });

  /// Client-side outcome reported by the callback or timeout.
  final PaymentStatus status;

  /// Correlation value for this session.
  final String sessionId;

  /// Validated callback URL, when one was received.
  final Uri? callbackUrl;

  /// Optional transaction identifier returned by the callback.
  final String? transactionId;
}

/// Base exception for payment URL plugin failures.
sealed class PaymentException implements Exception {
  /// Creates a payment exception.
  const PaymentException(this.message);

  /// Safe diagnostic message that does not include a payment URL.
  final String message;

  @override
  String toString() => message;
}

/// Thrown when the payment or callback contract is unsafe or incomplete.
final class PaymentConfigurationException extends PaymentException {
  /// Creates a configuration exception.
  const PaymentConfigurationException(super.message);
}

/// Thrown when an active payment session already exists.
final class PaymentInProgressException extends PaymentException {
  /// Creates an in-progress exception.
  const PaymentInProgressException()
    : super('A payment session is already in progress.');
}

/// Thrown when a callback cannot be safely matched or parsed.
final class PaymentCallbackException extends PaymentException {
  /// Creates a callback exception.
  const PaymentCallbackException(super.message);
}

String _singleQueryParameter(Uri uri, String name) {
  final values = uri.queryParametersAll[name];
  if (values == null || values.length != 1 || values.single.isEmpty) {
    throw const PaymentCallbackException('Callback parameter is missing.');
  }
  return values.single;
}

Set<String> _normalizedValues(Set<String> values) =>
    values.map((value) => value.trim().toLowerCase()).toSet();
