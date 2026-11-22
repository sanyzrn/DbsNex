import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'card_number.dart';
import 'iban.dart';
import 'payment_cards.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

/// Add or edit one person's card/IBAN.
///
/// Only what people share openly to be paid: a 16-digit card number, an
/// Iranian IBAN, and the holder's name. There is no CVV2 field, no expiry
/// field and no password field, because the module has no use for them.
Future<bool?> showCardSheet(
  BuildContext context,
  NexModuleStore store, {
  PaymentCard? existing,
  String? person,
}) => nexShowSheet<bool>(
  context: context,
  builder: (_) => CardSheet(
    store: store,
    existing: existing,
    initialPerson: person ?? existing?.person ?? '',
  ),
);

class CardSheet extends StatefulWidget {
  const CardSheet({
    super.key,
    required this.store,
    required this.existing,
    this.initialPerson = '',
  });

  final NexModuleStore store;
  final PaymentCard? existing;
  final String initialPerson;

  @override
  State<CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<CardSheet> {
  late final _person = TextEditingController(text: widget.initialPerson);
  late final _holder = TextEditingController(
    text: widget.existing?.holder ?? '',
  );
  late final _card = TextEditingController(text: widget.existing?.card ?? '');
  late final _iban = TextEditingController(text: widget.existing?.iban ?? '');
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _card.addListener(_repaint);
    _iban.addListener(_repaint);
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _person.dispose();
    _holder.dispose();
    _card.dispose();
    _iban.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final person = _person.text.trim();
    final digits = cardDigits(_card.text);
    final iban = ibanNormalize(_iban.text);
    final typedCard = _card.text.trim().isNotEmpty;
    final typedIban = _iban.text.trim().isNotEmpty;
    final message = person.isEmpty
        ? upgradeWord(context, 'cardPersonRequired')
        : typedCard && !luhnOk(digits)
        ? upgradeWord(context, 'cardInvalid')
        : typedIban && !ibanOk(iban)
        ? upgradeWord(context, 'cardIbanInvalid')
        : !typedCard && !typedIban
        ? upgradeWord(context, 'cardNeedOne')
        : null;
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final card = PaymentCard(
      id: widget.existing?.id ?? personKeyOf(person),
      person: person,
      holder: _holder.text.trim(),
      card: typedCard ? digits : '',
      iban: typedIban ? iban : '',
    );
    final saved = await storeWrite(
      context,
      () => saveCard(widget.store, card, existingId: widget.existing?.id),
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final digits = cardDigits(_card.text);
    final bank = bankOf(digits);
    final validCard = luhnOk(digits);
    final validIban = ibanOk(_iban.text);
    final cardTyped = _card.text.trim().isNotEmpty;
    final ibanTyped = _iban.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          NexSpacing.md,
          NexSpacing.sm,
          NexSpacing.md,
          NexSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings(
                context,
                widget.existing == null ? 'cardNew' : 'cardEdit',
              ),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NexAutoDirection(
                      controller: _person,
                      builder: (context, _) => TextField(
                        key: const ValueKey('card-field-person'),
                        controller: _person,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: strings(context, 'cardPerson'),
                        ),
                      ),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    NexAutoDirection(
                      controller: _holder,
                      builder: (context, _) => TextField(
                        key: const ValueKey('card-field-holder'),
                        controller: _holder,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: strings(context, 'cardHolder'),
                        ),
                      ),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    TextField(
                      key: const ValueKey('card-field-number'),
                      controller: _card,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: strings(context, 'cardNumber'),
                        hintText: strings(context, 'cardNumberHint'),
                        errorText: cardTyped && !validCard
                            ? strings(context, 'cardInvalid')
                            : null,
                      ),
                    ),
                    if (validCard)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: NexSpacing.xs,
                          top: NexSpacing.xs,
                        ),
                        child: Text(
                          '${bank == null ? strings(context, 'cardBankUnknown') : (NexModuleStrings.persian(context) ? bank.fa : bank.en)} · ${groupCard(digits)}',
                          key: const ValueKey('card-number-preview'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: NexSpacing.sm),
                    TextField(
                      key: const ValueKey('card-field-iban'),
                      controller: _iban,
                      textDirection: TextDirection.ltr,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: strings(context, 'cardIban'),
                        hintText: strings(context, 'cardIbanHint'),
                        errorText: ibanTyped && !validIban
                            ? strings(context, 'cardIbanInvalid')
                            : null,
                      ),
                    ),
                    if (validIban)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: NexSpacing.xs,
                          top: NexSpacing.xs,
                        ),
                        child: Text(
                          groupIban(_iban.text),
                          key: const ValueKey('card-iban-preview'),
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: NexSpacing.sm),
                    Text(
                      strings(context, 'cardBankChecked', {
                        'date': nexModuleDateLabel(
                          context,
                          DateTime.utc(2026, 11, 17),
                        ),
                      }),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: NexSpacing.sm),
                      Text(
                        _error!,
                        key: const ValueKey('card-error'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            Row(
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('card-save'),
                  onPressed: _saving ? null : () => unawaited(_save()),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings(context, 'cardSave')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
