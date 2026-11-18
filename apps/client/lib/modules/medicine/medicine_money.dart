import 'package:flutter/widgets.dart';
import 'package:nex_client/modules/module_api.dart';

import 'local_values.dart';

/// What a medicine cost, kept the way the app's money modules keep money:
/// a whole number of **rials**, and read back in **tomans**, because that
/// is what a person in Iran says at the counter. One toman is ten rials,
/// so a toman amount can need a tenth (one rial) and nothing smaller.
///
/// This file is the module's own small copy of that rule — a module may
/// not import another module's folder (`docs/18-module-kit.md`).
class MedicineMoney {
  const MedicineMoney._();

  static const rialPerToman = 10;

  /// What a person typed, read as tomans and stored as rials. Null when it
  /// is not a price: empty, negative, more than one decimal, or too large
  /// to hold exactly.
  static int? parse(String written) {
    final text = LocalValues.ascii(written.trim())
        .replaceAll('٬', '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll('٫', '.');
    if (text.isEmpty) {
      return null;
    }
    final match = RegExp(r'^(\d+)(?:\.(\d))?$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final whole = BigInt.tryParse(match.group(1)!);
    if (whole == null) {
      return null;
    }
    final rials =
        whole * BigInt.from(rialPerToman) +
        BigInt.from(int.parse(match.group(2) ?? '0'));
    if (rials > BigInt.from(LocalValues.maxExact)) {
      return null;
    }
    return rials.toInt();
  }

  /// Stored rials as the tomans a person reads: grouped, the reader's
  /// digits, and a tenth only when the rials leave a remainder.
  static String tomanText(BuildContext context, int rials) {
    final persian = NexModuleStrings.persian(context);
    final value = rials.abs();
    final whole = value ~/ rialPerToman;
    final rest = value % rialPerToman;
    final grouped = _grouped(whole, persian);
    final fraction = rest == 0 ? '' : '${persian ? '٫' : '.'}$rest';
    return nexDigits('$grouped$fraction', persian: persian);
  }

  /// Stored rials as the editor's field text, in tomans and without
  /// grouping — what a person can type over.
  static String inputToman(int rials) {
    final value = rials.abs();
    final whole = value ~/ rialPerToman;
    final rest = value % rialPerToman;
    return rest == 0 ? '$whole' : '$whole.$rest';
  }

  static String _grouped(int value, bool persian) {
    final digits = '$value';
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      groups.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
    }
    return groups.join(persian ? '٬' : ',');
  }
}
