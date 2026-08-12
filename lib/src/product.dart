import 'package:iran_iap/src/store.dart';
import 'package:meta/meta.dart';

/// Product metadata returned by the selected store.
@immutable
final class IapProduct {
  /// Creates product metadata.
  IapProduct({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.price,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
  }

  /// Store product/SKU identifier.
  final String id;

  /// Product type reported by the store.
  final IapProductType type;

  /// Store-provided display title.
  final String title;

  /// Store-provided description.
  final String description;

  /// Localized display price returned by the native billing SDK.
  ///
  /// This value is intended for UI display. Do not parse it for accounting or
  /// entitlement decisions.
  final String price;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IapProduct &&
          id == other.id &&
          type == other.type &&
          title == other.title &&
          description == other.description &&
          price == other.price;

  @override
  int get hashCode => Object.hash(id, type, title, description, price);

  @override
  String toString() => 'IapProduct(id: $id, type: $type, price: $price)';
}
