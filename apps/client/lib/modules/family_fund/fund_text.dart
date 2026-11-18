import 'package:flutter/widgets.dart';
import 'package:nex_client/modules/module_api.dart';

/// Joins facts on one line: «،» in Persian, where a middle dot beside a
/// number reads as the Persian zero («· ۵۰۰٬۰۰۰» looked like «۰۵۰۰٬۰۰۰»)
/// (2.8.4), and « · » in English.
String fundSep(BuildContext context) =>
    fundSepFor(persian: NexModuleStrings.persian(context));

String fundSepFor({required bool persian}) => persian ? '، ' : ' · ';

/// A label and its value: «واریز شده: علی» in Persian, «Paid · Ali» in
/// English.
String fundLabeled(BuildContext context, String label, String value) =>
    NexModuleStrings.persian(context) ? '$label: $value' : '$label · $value';
