/// The calculator's input pieces: labelled number fields with their
/// validation in the words of the module, and the pickers.
///
/// One line a person types follows ADR-037 as far as the module API
/// allows: amounts and dates run left to right inside an explicit
/// `textDirection`, titles and shops follow the typed script through
/// [NexAutoDirection], and the multi-line note uses the module's local
/// stand-in for `NexTextField` (see README Platform requests).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_format.dart';
import 'gold_strings.dart';
import 'gold_fineness_dialog.dart';

/// A number field: label, hint, its own validation words, and the parsed
/// scaled value handed to the parent on every keystroke.
class GoldNumberField extends StatelessWidget {
  const GoldNumberField({
    super.key,
    required this.label,
    required this.controller,
    required this.scale,
    required this.maxScaled,
    this.hint,
    this.suffix,
    this.allowEmpty = true,
    this.onChanged,
    this.fieldKey,
  });

  final String label;
  final String? hint;
  final String? suffix;
  final TextEditingController controller;
  final int scale;
  final int maxScaled;

  /// Whether an empty field is acceptable (weight and rate say no).
  final bool allowEmpty;
  final void Function(int? value)? onChanged;

  /// A stable key for tests, distinct from the label's own text.
  final Key? fieldKey;

  String? _problem(String text) {
    final (value, problem) = parseScaledDetailed(text, scale);
    if (problem != null) {
      if (problem == GoldParseProblem.empty && allowEmpty) return null;
      return problem == GoldParseProblem.empty
          ? 'required'
          : 'parse_${problem.name}';
    }
    if (value! > maxScaled) return 'parse_tooBig';
    return null;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        key: fieldKey,
        controller: controller,
        textDirection: TextDirection.ltr,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        // No input formatter: the platform's formatter is not reachable
        // through the module API, and the validator below already refuses
        // whatever slips past the keyboard, in words rather than silence.
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          errorMaxLines: 3,
        ),
        onChanged: (text) {
          final (value, problem) = parseScaledDetailed(text, scale);
          final capped = value != null && value <= maxScaled ? value : null;
          onChanged?.call(problem == null ? capped : null);
        },
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (text) {
          final problemKey = _problem(text ?? '');
          return problemKey == null ? null : goldStrings(context, problemKey);
        },
      ),
      if (hint != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
          child: Text(
            hint!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ],
  );
}

/// A one-line field that follows the script being typed into it.
class GoldAutoTextField extends StatelessWidget {
  const GoldAutoTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.fieldKey,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => NexAutoDirection(
    controller: controller,
    builder: (context, _) => TextField(
      key: fieldKey,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
    ),
  );
}

/// The module's stand-in for the platform's `NexTextField`: a real local
/// editor for multi-line text, built on `EditableText` with its own focus
/// and decoration — the same shape `NexTextField` itself uses off-Android
/// (a field under [NexAutoDirection]). The platform's own editor — with
/// per-paragraph direction and the system's handles — is not exported
/// through the module API; that request is in the README.
class GoldNoteField extends StatefulWidget {
  const GoldNoteField({
    super.key,
    required this.controller,
    required this.label,
    this.fieldKey,
    this.minLines = 2,
  });

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final int minLines;

  @override
  State<GoldNoteField> createState() => _GoldNoteFieldState();
}

class _GoldNoteFieldState extends State<GoldNoteField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NexAutoDirection(
      controller: widget.controller,
      builder: (context, direction) => InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          alignLabelWithHint: true,
          counterText: '',
        ),
        isFocused: _focus.hasFocus,
        isEmpty: widget.controller.text.isEmpty,
        child: EditableText(
          key: widget.fieldKey,
          controller: widget.controller,
          focusNode: _focus,
          style: theme.textTheme.bodyLarge ?? const TextStyle(),
          cursorColor: theme.colorScheme.primary,
          backgroundCursorColor: theme.colorScheme.onSurfaceVariant,
          maxLines: null,
          minLines: widget.minLines,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textDirection: direction,
        ),
      ),
    );
  }
}

/// A picker on a plain 48dp touch target that shows what is chosen.
class GoldDropdownField<T> extends StatelessWidget {
  const GoldDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onSelected,
    this.hint,
    this.fieldKey,
  });

  final String label;
  final String? hint;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onSelected;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedLabel = items
        .map((item) => item.$1 == value ? item : null)
        .nonNulls
        .firstOrNull
        ?.$2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.xs),
          child: Text(label, style: theme.textTheme.labelLarge),
        ),
        NexPopupMenuButton<T>(
          key: fieldKey,
          initialValue: value,
          onSelected: onSelected,
          position: PopupMenuPosition.under,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          itemBuilder: (context) => [
            for (final (itemValue, itemLabel) in items)
              PopupMenuItem(
                value: itemValue,
                height: 48,
                child: Text(itemLabel),
              ),
          ],
          child: InputDecorator(
            decoration: const InputDecoration(
              suffixIcon: Icon(Icons.unfold_more),
            ),
            child: Text(selectedLabel ?? ''),
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
            child: Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Fineness in parts per thousand: the four presets, and «Custom», which
/// asks its one question in a dialog and shows the number on the field.
class GoldFinenessField extends StatelessWidget {
  const GoldFinenessField({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.fieldKey,
  });

  final String label;
  final String? hint;
  final int value;
  final void Function(int) onChanged;
  final Key? fieldKey;

  static const custom = -1;

  String _presetLabel(BuildContext context, int ppt) {
    final persian = NexModuleStrings.persian(context);
    final karat = switch (ppt) {
      999 => '24k',
      916 => '22k',
      875 => '21k',
      _ => '18k',
    };
    return '${groupDigits(ppt, persian: persian)} · ${persian ? goldDigits(karat.replaceFirst('k', ' عیار'), true) : karat}';
  }

  Future<void> _askCustom(BuildContext context) async {
    final result = await showGoldFinenessDialog(context, value);
    if (context.mounted && result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final persian = NexModuleStrings.persian(context);
    final isPreset = goldFinenessPresets.contains(value);
    final items = <(int, String)>[
      for (final ppt in goldFinenessPresets) (ppt, _presetLabel(context, ppt)),
      (
        custom,
        isPreset
            ? goldStrings(context, 'finenessCustom')
            : '${goldStrings(context, 'finenessCustom')} · '
                  '${groupDigits(value, persian: persian)}',
      ),
    ];
    return GoldDropdownField<int>(
      fieldKey: fieldKey,
      label: label,
      hint: hint,
      value: isPreset ? value : custom,
      items: items,
      onSelected: (picked) {
        if (picked == custom) {
          unawaited(_askCustom(context));
          return;
        }
        onChanged(picked);
      },
    );
  }
}
