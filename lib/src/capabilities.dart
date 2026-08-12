import 'package:meta/meta.dart';

/// Features reported by the selected native store implementation.
@immutable
final class IapCapabilities {
  /// Creates an immutable capability snapshot.
  const IapCapabilities({
    this.supportsSubscriptions = false,
    this.supportsConsumption = false,
    this.supportsDynamicPricing = false,
  });

  /// Whether subscription APIs are available for this configuration.
  final bool supportsSubscriptions;

  /// Whether consumable purchases can be consumed.
  final bool supportsConsumption;

  /// Whether the selected provider exposes dynamic-price purchase tokens.
  ///
  /// Dynamic-price tokens are currently a Cafe Bazaar-specific capability.
  /// Runtime store versions can still reject a token even when this is `true`.
  final bool supportsDynamicPricing;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IapCapabilities &&
          supportsSubscriptions == other.supportsSubscriptions &&
          supportsConsumption == other.supportsConsumption &&
          supportsDynamicPricing == other.supportsDynamicPricing;

  @override
  int get hashCode => Object.hash(
    supportsSubscriptions,
    supportsConsumption,
    supportsDynamicPricing,
  );

  @override
  String toString() =>
      'IapCapabilities('
      'subscriptions: $supportsSubscriptions, '
      'consumption: $supportsConsumption, '
      'dynamicPricing: $supportsDynamicPricing)';
}
