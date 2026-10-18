/// The save sheet: the words that travel with a saved estimate — a title,
/// the shop, the day it was quoted for, and a note. One primary action:
/// the save itself.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_fields.dart';
import 'gold_format.dart';
import 'gold_strings.dart';

/// Asks for the quote's words and resolves to true when the person
/// confirmed the save. The controllers belong to the screen, so an aborted
/// sheet keeps what was typed for the next try.
Future<bool> showGoldSaveSheet(
  BuildContext context, {
  required TextEditingController title,
  required TextEditingController shop,
  required TextEditingController quoteDate,
  required TextEditingController notes,
  required bool editing,
}) async {
  final result = await nexShowSheet<bool>(
    context: context,
    dismissible: false,
    swipeToClose: true,
    builder: (sheetContext) => _GoldSaveSheet(
      title: title,
      shop: shop,
      quoteDate: quoteDate,
      notes: notes,
      editing: editing,
    ),
  );
  return result == true;
}

class _GoldSaveSheet extends StatefulWidget {
  const _GoldSaveSheet({
    required this.title,
    required this.shop,
    required this.quoteDate,
    required this.notes,
    required this.editing,
  });

  final TextEditingController title;
  final TextEditingController shop;
  final TextEditingController quoteDate;
  final TextEditingController notes;
  final bool editing;

  @override
  State<_GoldSaveSheet> createState() => _GoldSaveSheetState();
}

class _GoldSaveSheetState extends State<_GoldSaveSheet> {
  final _form = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final strings = goldStrings;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings(context, 'saveSheetTitle'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.md),
            GoldAutoTextField(
              fieldKey: const ValueKey('gold-save-title'),
              label: strings(context, 'quoteTitle'),
              controller: widget.title,
            ),
            const SizedBox(height: NexSpacing.sm),
            GoldAutoTextField(
              fieldKey: const ValueKey('gold-save-shop'),
              label: strings(context, 'shop'),
              controller: widget.shop,
            ),
            const SizedBox(height: NexSpacing.sm),
            NexModuleDateEntry(
              controller: widget.quoteDate,
              hyphenated: true,
              child: TextFormField(
                key: const ValueKey('gold-save-date'),
                controller: widget.quoteDate,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: strings(context, 'quoteDate'),
                  helperText: strings(context, 'quoteDateHint'),
                  counterText: '',
                ),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (text) {
                  final value = (text ?? '').trim();
                  if (value.isEmpty) return strings(context, 'required');
                  if (!isIsoDate(value)) {
                    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)
                        ? strings(context, 'dateNotReal')
                        : strings(context, 'dateBadFormat');
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            GoldNoteField(
              fieldKey: const ValueKey('gold-save-notes'),
              controller: widget.notes,
              label: strings(context, 'notes'),
            ),
            const SizedBox(height: NexSpacing.md),
            FilledButton(
              key: const ValueKey('gold-save-confirm'),
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: Text(
                strings(context, widget.editing ? 'updateQuote' : 'saveQuote'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
