import 'package:iran_iap/src/purchase.dart';

/// Result of a purchase flow.
///
/// User cancellation is modeled as [PurchaseCancelled], not an exception.
sealed class PurchaseOutcome {
  const PurchaseOutcome();
}

/// A purchase flow completed and returned purchase evidence.
final class PurchaseCompleted extends PurchaseOutcome {
  /// Creates a successful purchase outcome.
  const PurchaseCompleted(this.purchase);

  /// Purchase evidence returned by the selected store.
  final IapPurchase purchase;
}

/// The user cancelled the purchase flow without completing payment.
final class PurchaseCancelled extends PurchaseOutcome {
  /// Creates a cancellation outcome.
  const PurchaseCancelled();
}
