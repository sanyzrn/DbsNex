import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_fields.dart';
import 'warranty_models.dart';
import 'warranty_strings.dart';

/// The purchase as plain text a person can hand to a shop or a repairer:
/// what it is, when it was bought, where, the serial and invoice reference
/// they wrote down, when the coverage ends, and the dated claim and service
/// notes in order. Only what is in the record — nothing is added, nothing is
/// claimed about what the maker or the merchant will accept.
String warrantyServiceFile(
  BuildContext context,
  Map<String, Object?> body,
  List<ModuleRecord> claims,
) {
  final strings = warrantyStrings;
  String text(String key) => WarrantyModels.readString(body, key).trim();
  final lines = <String>[text('product')];

  void field(String label, String value) {
    if (value.isNotEmpty) lines.add('$label: $value');
  }

  field(strings(context, 'category'), text('category'));
  field(strings(context, 'brand'), text('brand'));
  field(strings(context, 'model'), text('model'));
  field(strings(context, 'serialLabel'), text('serial'));
  field(strings(context, 'merchantLabel'), text('merchant'));
  field(strings(context, 'receiptLabel'), text('receiptRef'));
  final purchased = WarrantyModels.readDate(body, 'purchasedAt');
  if (purchased != null) {
    field(
      strings(context, 'purchasedLabel'),
      WarrantyFields.dayLabel(context, purchased),
    );
  }
  final end = WarrantyModels.readDate(body, 'coverageEnd');
  if (end != null) {
    field(strings(context, 'endsLabel'), WarrantyFields.dayLabel(context, end));
  }
  field(strings(context, 'typeLabel'), text('coverageType'));
  field(strings(context, 'noteLabel'), text('note'));

  final dated =
      [
        for (final claim in claims)
          (WarrantyModels.readDate(claim.body, 'at'), claim),
      ]..sort((a, b) {
        final left = a.$1, right = b.$1;
        if (left == null || right == null) return left == null ? 1 : -1;
        return left.compareTo(right);
      });
  if (dated.isNotEmpty) {
    lines
      ..add('')
      ..add(strings(context, 'claimsTitle'));
    for (final (at, claim) in dated) {
      final kind = WarrantyModels.readString(claim.body, 'kind');
      final label = strings(
        context,
        kind == WarrantyModels.claimKind
            ? 'claimed'
            : kind == WarrantyModels.serviceKind
            ? 'serviced'
            : 'unknownLog',
      );
      final when = at == null ? '' : WarrantyFields.instantLabel(context, at);
      final note = WarrantyModels.readString(claim.body, 'note').trim();
      lines.add(
        '- ${[when, label].where((p) => p.isNotEmpty).join(' · ')}: $note',
      );
    }
  }
  return lines.join('\n');
}
