import 'package:flutter/material.dart';

import 'package:nex_client/modules/module_api.dart';

/// Two fields side by side fit a phone held upright at the usual text size
/// and do not fit one at twice that size — the labels were being cut to
/// "Purchase …" and "Duratio…". Each pair therefore asks for the room it
/// has and stacks when there is not enough.

/// Whether a pair of fields has to become one above the other.
bool warrantyFieldsStack(BuildContext context, double width) =>
    width < 380 || MediaQuery.textScalerOf(context).scale(14) > 20;

/// Two fields beside each other, or one above the other when the room or
/// the text size says otherwise.
class WarrantyFieldPair extends StatelessWidget {
  const WarrantyFieldPair({
    super.key,
    required this.first,
    required this.second,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (warrantyFieldsStack(context, constraints.maxWidth)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            const SizedBox(height: NexSpacing.sm),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: NexSpacing.sm),
          Expanded(child: second),
        ],
      );
    },
  );
}
