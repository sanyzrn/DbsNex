import 'local_values.dart';

/// Warranties — one folder, the module API and nothing else.
///
/// The record kinds, the coverage arithmetic and the honest limits are
/// documented in `README.md`. Nothing in this module reaches past its
/// `NexModuleStore`: no camera, no file attachments, no notifications,
/// no network, and no promise about merchants or reimbursement.
class WarrantyModels {
  const WarrantyModels._();

  /// Record kind: one purchased product and its coverage.
  static const warranty = 'warranty';

  /// Record kind: one dated claim or service note.
  static const claim = 'claim';

  /// How many days ahead an ending coverage still counts as "expiring".
  static const expiringWindowDays = 30;

  // ------------------------------------------------------------- readers

  /// A string field, or '' when missing or wrong-typed.
  static String readString(Map<String, Object?> body, String key) {
    final value = body[key];
    return value is String ? value : '';
  }

  /// A stored ISO 8601 timestamp, or null when missing or unparsable.
  static DateTime? readDate(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! String) {
      return null;
    }
    return key == 'purchasedAt' || key == 'coverageEnd'
        ? LocalValues.calendar(value)
        : LocalValues.stamp(value);
  }

  /// A non-negative integer (rials, months), or null when missing,
  /// negative or wrong-typed.
  static int? readCount(Map<String, Object?> body, String key) {
    final value = body[key];
    return LocalValues.count(value);
  }

  /// Whether the record is archived. A missing field is false.
  static bool readArchived(Map<String, Object?> body) =>
      body['archived'] == true;

  // -------------------------------------------------------------- writers

  /// The body of a warranty. [coverageEnd] is always present: either the
  /// person wrote it, or it was computed visibly from the purchase date
  /// and [durationMonths] — which is kept for the record of how.
  static Map<String, Object?> warrantyBody({
    required String product,
    required String category,
    required String brand,
    required String model,
    required String serial,
    required String merchant,
    required String receiptRef,
    required String coverageType,
    required String note,
    required DateTime purchasedAt,
    required DateTime coverageEnd,
    int? durationMonths,
    int? amountRials,
    bool archived = false,
  }) => {
    'v': 1,
    'product': product.trim(),
    'category': category.trim(),
    'brand': brand.trim(),
    'model': model.trim(),
    'serial': serial.trim(),
    'merchant': merchant.trim(),
    'receiptRef': receiptRef.trim(),
    'coverageType': coverageType.trim(),
    'note': note,
    'purchasedAt': purchasedAt.toIso8601String(),
    'coverageEnd': coverageEnd.toIso8601String(),
    if (durationMonths != null) 'durationMonths': durationMonths,
    if (amountRials != null) 'amountRials': amountRials,
    'archived': archived,
  };

  /// The body of a claim or service note.
  static Map<String, Object?> claimBody({
    required String warrantyId,
    required String kind,
    required String note,
    required DateTime at,
  }) => {
    'v': 1,
    'warrantyId': warrantyId,
    'kind': kind,
    'note': note,
    'at': at.toUtc().toIso8601String(),
  };

  /// The two kinds a claim note can be.
  static const claimKind = 'claim';
  static const serviceKind = 'service';
}
