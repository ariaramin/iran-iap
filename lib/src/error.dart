import 'package:iran_iap/src/store.dart';
import 'package:meta/meta.dart';

/// Stable error categories exposed by `iran_iap`.
///
/// Native SDK codes and exception types are preserved separately on
/// [IapException] so callers can log diagnostics without coupling business
/// logic to Poolakey or Myket SDK classes.
enum IapErrorCode {
  /// The Flutter plugin is unavailable on the current platform.
  unsupportedPlatform,

  /// The selected store application is not installed on the device.
  storeNotInstalled,

  /// The installed store does not support the required billing API.
  storeUnsupported,

  /// The billing service could not be reached or became unavailable.
  serviceUnavailable,

  /// A network-related store operation failed.
  network,

  /// A native response was malformed or could not be normalized safely.
  invalidResponse,

  /// Signature or purchase verification failed.
  verificationFailed,

  /// Package or caller configuration is invalid.
  configuration,

  /// A requested provider-specific feature is unavailable.
  featureUnavailable,

  /// The requested product is unavailable.
  itemUnavailable,

  /// The user already owns the requested product.
  itemAlreadyOwned,

  /// The requested product is not currently owned.
  itemNotOwned,

  /// Subscriptions are unavailable for the current store/configuration.
  subscriptionUnavailable,

  /// A purchase requires a compatible foreground Android Activity.
  activityUnavailable,

  /// Another asynchronous billing operation is currently running.
  operationInProgress,

  /// `IranIapClient.initialize()` has not completed or the native client
  /// disconnected.
  notInitialized,

  /// The client has been disposed and cannot be reused.
  disposed,

  /// The native billing SDK reported a developer/configuration error.
  developerError,

  /// A native platform operation failed without a more specific mapping.
  platform,

  /// The package received an error code it does not recognize yet.
  unknown,
}

/// A normalized billing failure with optional native diagnostics.
@immutable
final class IapException implements Exception {
  /// Creates an exception.
  IapException({
    required this.code,
    required this.store,
    required this.message,
    this.nativeCode,
    this.nativeMessage,
    this.nativeExceptionType,
    Map<String, Object?> details = const <String, Object?>{},
  }) : details = Map<String, Object?>.unmodifiable(details);

  /// Stable package-level error category.
  final IapErrorCode code;

  /// Store selected for the current build.
  final IapStore store;

  /// Human-readable diagnostic message.
  final String message;

  /// Original native SDK response code when available.
  final Object? nativeCode;

  /// Original native SDK message when available.
  final String? nativeMessage;

  /// Fully qualified native exception type when available.
  final String? nativeExceptionType;

  /// Additional immutable diagnostics supplied by the native implementation.
  ///
  /// Treat this map as diagnostic data. Its keys can grow in patch/minor
  /// releases and should not be used as the primary business-logic contract.
  final Map<String, Object?> details;

  @override
  String toString() =>
      'IapException('
      'code: $code, store: $store, message: $message, '
      'nativeCode: $nativeCode, nativeMessage: $nativeMessage, '
      'nativeExceptionType: $nativeExceptionType)';
}
