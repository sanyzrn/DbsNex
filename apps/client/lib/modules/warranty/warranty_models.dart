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

  /// The record layout this version writes. v1 records (2.1.x) are read
  /// field by field, so every field added in v2 is simply absent there and
  /// reads as empty — the warranty company, its phone, the card number, the
  /// kind of guarantee and who the device is registered to.
  static const version = 2;

  // ------------------------------------------------------ the kind of cover

  /// A company warranty (گارانتی شرکتی): an independent warranty company
  /// whose card and support line the buyer deals with — not the shop.
  static const coverCompany = 'company';

  /// The seller's own guarantee (ضمانت‌نامهٔ فروشنده): the shop's word,
  /// usually without a company card behind it.
  static const coverSeller = 'seller';

  /// After-sales service (خدمات پس از فروش): the maker's or importer's
  /// service and parts promise, which is separate from the warranty period.
  static const coverAfterSales = 'afterSales';

  /// The three kinds the editor offers, in the order it shows them.
  static const coverKinds = [coverCompany, coverSeller, coverAfterSales];

  /// A stored cover kind, or '' when missing or not one this version knows.
  static String readCoverKind(Map<String, Object?> body) {
    final value = body['coverKind'];
    return value is String && coverKinds.contains(value) ? value : '';
  }

  // ------------------------------------------------------- the phone registry

  /// The device is registered (رجیستری) in the person's own name.
  static const registryMine = 'mine';

  /// It is registered in someone else's name — a service centre asks for
  /// that person's national ID card.
  static const registryOther = 'other';

  /// A stored registry owner, or '' when it was never written down.
  static String readRegistry(Map<String, Object?> body) {
    final value = body['registryOwner'];
    if (value == registryMine) return registryMine;
    if (value == registryOther) return registryOther;
    return '';
  }

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
  ///
  /// The Iran-specific fields are optional and written only when the person
  /// filled them, so a record never claims a company, a phone number or a
  /// card number that nobody typed.
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
    String coverKind = '',
    String company = '',
    String supportPhone = '',
    String cardNumber = '',
    String registryOwner = '',
    int? durationMonths,
    int? amountRials,
    bool archived = false,
  }) => {
    'v': version,
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
    if (coverKind.isNotEmpty) 'coverKind': coverKind,
    if (company.trim().isNotEmpty) 'company': company.trim(),
    if (supportPhone.trim().isNotEmpty) 'supportPhone': supportPhone.trim(),
    if (cardNumber.trim().isNotEmpty) 'cardNumber': cardNumber.trim(),
    if (registryOwner.isNotEmpty) 'registryOwner': registryOwner,
    'durationMonths': ?durationMonths,
    'amountRials': ?amountRials,
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
