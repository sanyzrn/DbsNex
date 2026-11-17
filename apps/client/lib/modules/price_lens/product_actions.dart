import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'comparison.dart';
import 'controller.dart';
import 'history_status.dart';
import 'lens_undo.dart';
import 'money_render.dart';
import 'option_editor.dart';
import 'options.dart';
import 'price_lens_common.dart';
import 'products.dart';
import 'rational.dart';
import 'strings.dart';
import 'units.dart';

String memoryQuantity(
  BuildContext context,
  PriceMemory m, {
  PriceUnit? inUnit,
}) {
  final unit = inUnit ?? priceUnitOf(m.unitKey)!;
  final amount = convertQuantity(
    m.quantity * Fraction(m.packageCount),
    priceUnitOf(m.unitKey)!,
    unit,
  )!;
  final raw = amount.toDecimalString(digits: 6);
  return '${nexDigits(raw, persian: NexModuleStrings.persian(context))} ${priceLensStrings(context, 'unit${unit.key[0].toUpperCase()}${unit.key.substring(1)}')}';
}

String memoryChangeLabel(
  BuildContext context,
  LensProduct product,
  DateTime today,
) {
  final change = productChange(product, today),
      latest = product.latestKnown(today);
  if (change == null || latest == null) {
    return priceLensStrings(context, 'trendNeedsHistory');
  }
  final old = product.previousDay(latest)!;
  final text = nexDigits(
    percentageChangeText(change)
        .replaceAll('.', NexModuleStrings.persian(context) ? '٫' : '.'),
    persian: NexModuleStrings.persian(context),
  );
  return priceLensStrings(context, 'priceChange', {
    'percent': NexModuleStrings.persian(context)
        ? text.replaceFirst(RegExp(r'^[+−]'), '')
        : text,
    'direction': change < const Fraction(0)
        ? 'کاهش'
        : change == const Fraction(0)
        ? 'تغییر'
        : 'افزایش',
    'unit': priceLensStrings(
      context,
      'unit${product.common.key[0].toUpperCase()}${product.common.key.substring(1)}',
    ),
    'days': elapsedPriceDays(old.date, latest.date),
  });
}

Future<void> addProductPrice(
  BuildContext context,
  PriceLensController controller,
  LensProduct product,
) {
  final last = product.latestKnown(DateTime.now()) ?? product.prices.last;
  return showOptionEditor(
    context,
    store: controller.store,
    priceEntry: true,
    existing: PriceOption(
      id: 'new',
      label: product.label,
      productName: product.label,
      priceMinor: 0,
      currency: last.currency,
      quantity: last.quantity,
      unitKey: last.unitKey,
      packageCount: last.packageCount,
      date: priceDay(DateTime.now()),
    ),
    onSave: (_) {},
    persist: (option) async {
      final paid = effectivePriceMinor(option);
      await controller.saveMemory(
        PriceMemory(
          id: option.id,
          label: option.label,
          productName: option.productName ?? product.label,
          person: option.person,
          priceMinor: paid.roundHalfUp(),
          paidFraction: paid,
          currency: option.currency,
          quantity: option.quantity,
          unitKey: option.unitKey,
          packageCount: option.packageCount,
          date: option.date ?? priceDay(DateTime.now()),
        ),
      );
    },
  );
}

Future<void> forgetProductPrice(
  BuildContext context,
  PriceLensController controller,
  PriceMemory memory,
) async {
  final s = priceLensStrings,
      host = NexBannerHost.of(context),
      l10n = AppLocalizations.of(context);
  final yes = await nexShowDialog<bool>(
    context: context,
    builder: (c) => NexAlertDialog(
      title: Text(s(c, 'deleteMemoryTitle')),
      content: NexDialogBody(child: Text(s(c, 'memoryDeleteBody'))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(s(c, 'cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(c).colorScheme.error,
          ),
          child: Text(s(c, 'delete')),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  try {
    await controller.deleteMemory(memory.id);
    LensUndo.offer(
      host,
      message: s.text(l10n, 'memoryDeleted'),
      undoLabel: s.text(l10n, 'undo'),
      failureMessage: s.text(l10n, 'undoFailed'),
      restore: () => controller.restoreMemory(memory),
    );
  } catch (_) {
    if (context.mounted) lensWriteFailure(context);
  }
}

String productShareText(BuildContext context, LensProduct product) {
  final s = priceLensStrings;
  final history = product.prices.reversed.take(100).toList();
  return [
    product.label,
    s(context, 'sharedHistory', {'n': history.length}),
    for (final m in history)
      [
        lensFullDate(context, m.date),
        lensMoney(context, m.exactPaid, m.currency),
        memoryQuantity(context, m),
        if (m.shop.isNotEmpty) m.shop,
      ].join(' · '),
    s(context, 'estimateOnly'),
  ].join('\n');
}

Future<void> shareProduct(BuildContext context, LensProduct product) async {
  try {
    await nexModuleShareText(productShareText(context, product));
  } catch (_) {
    if (context.mounted) {
      nexShowBanner(
        context,
        message: priceLensStrings(context, 'shareFailed'),
        kind: NexBannerKind.failed,
      );
    }
  }
}
