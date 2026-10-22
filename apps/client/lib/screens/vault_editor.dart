import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/vault_banks.dart';
import '../platform/vault_store.dart';
import '../platform/private_clipboard.dart';
import '../widgets/feature_label.dart';
import '../widgets/nex_text_field.dart';
import '../widgets/tag_color_picker.dart';

class VaultEditor extends StatefulWidget {
  const VaultEditor({
    super.key,
    required this.entry,
    required this.busy,
    required this.onChanged,
    required this.onSave,
    required this.onDiscard,
  });
  final VaultEntry entry;
  final bool busy;
  final ValueChanged<VaultEntry> onChanged;
  final Future<void> Function(VaultEntry) onSave;
  final Future<void> Function() onDiscard;
  @override
  State<VaultEditor> createState() => _VaultEditorState();
}

class _VaultEditorState extends State<VaultEditor> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields = {
    for (final key in [
      'title',
      'login',
      'password',
      'website',
      'notes',
      'bank',
      'holder',
      'number',
      'expiry',
      'cvv2',
      'iban',
      'account',
    ])
      key: TextEditingController(text: widget.entry.value(key)),
  };
  bool discard = false;

  /// The bank name this editor filled in by itself, so a later digit can
  /// replace it while a name the person typed is never touched.
  String? _autoBank;
  VaultBank? _guessedBank;

  /// A card's own colour as `#RRGGBB`, or null for the theme's. Chosen with
  /// the same picker tags and the app accent use, not a second one.
  late String? color = nexParseTagColor(widget.entry.value('color')) == null
      ? null
      : widget.entry.value('color');
  late bool favorite = widget.entry.favorite;

  @override
  void initState() {
    super.initState();
    fields['number']!.addListener(_onNumberText);
    _guessedBank = vaultBankFor(vaultCardDigits(fields['number']!.text));
  }

  /// Recognises the bank from the first six digits and, when the bank field is
  /// empty (or still holds what this did), fills it in.
  void _onNumberText() {
    final digits = vaultCardDigits(fields['number']!.text);
    final bank = vaultBankFor(digits);
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final field = fields['bank']!;
    if (bank != null &&
        (field.text.trim().isEmpty || field.text == _autoBank)) {
      final name = bank.name(persian: persian);
      field.text = name;
      _autoBank = name;
      _changed();
    } else if (bank == null && field.text == _autoBank) {
      field.clear();
      _autoBank = null;
      _changed();
    }
    // The hints under the field follow every digit.
    if (mounted) setState(() => _guessedBank = bank);
  }

  @override
  void dispose() {
    fields['number']!.removeListener(_onNumberText);
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  VaultEntry _value({bool normalize = false}) {
    final values = {
      for (final e in fields.entries)
        e.key: e.key == 'password' ? e.value.text : e.value.text.trim(),
    };
    if (normalize && widget.entry.kind == VaultKind.card) {
      values['number'] = vaultCardDigits(values['number']!);
      values['iban'] = vaultLatinDigits(
        values['iban']!,
      ).replaceAll(RegExp(r'\s'), '').toUpperCase();
      values['account'] = vaultLatinDigits(values['account']!);
      values['expiry'] = vaultLatinDigits(values['expiry']!);
      values['cvv2'] = vaultLatinDigits(values['cvv2']!);
    }
    if (widget.entry.kind == VaultKind.card && color != null) {
      values['color'] = color!;
    }
    return VaultEntry(
      id: widget.entry.id,
      kind: widget.entry.kind,
      fields: values,
      favorite: favorite,
      updatedAt: DateTime.now(),
    );
  }

  void _changed() => widget.onChanged(_value());
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final password = widget.entry.kind == VaultKind.password;
    return Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, NexSpacing.xl),
        children: [
          Text(l.vaultEditHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 18),
          _field('title', l.vaultTitleField, required: true),
          if (password) ...[
            _field('login', l.vaultLogin, ltr: true),
            _field(
              'password',
              l.vaultPassword,
              required: true,
              secret: true,
              ltr: true,
            ),
            _field(
              'website',
              l.vaultWebsite,
              ltr: true,
              keyboard: TextInputType.url,
            ),
          ] else ...[
            _field('bank', l.vaultBank),
            _field('holder', l.vaultHolder),
            _field(
              'number',
              l.vaultNumber,
              required: true,
              ltr: true,
              keyboard: TextInputType.number,
              formatters: [_CardNumberFormatter()],
              // Only the shape stops a save. A check digit that does not
              // add up is said below the field and left to the person: the
              // number may be exactly what is printed on their card.
              validator: (v) =>
                  validVaultCardShape(v) ? null : l.vaultInvalidCard,
              footer: _numberHints(l, theme),
            ),
            _field(
              'expiry',
              l.vaultExpiry,
              ltr: true,
              keyboard: TextInputType.datetime,
              formatters: [_LatinDigits(extra: '/')],
              validator: (v) =>
                  validVaultExpiry(v) ? null : l.vaultInvalidExpiry,
            ),
            _field(
              'cvv2',
              l.vaultCvv2,
              ltr: true,
              keyboard: TextInputType.number,
              formatters: [_LatinDigits(max: 4)],
              validator: (v) =>
                  v.trim().isEmpty ||
                      RegExp(r'^\d{3,4}$').hasMatch(vaultLatinDigits(v.trim()))
                  ? null
                  : l.vaultInvalidCvv2,
            ),
            _field(
              'iban',
              l.vaultIban,
              ltr: true,
              validator: (v) => v.trim().isEmpty || validVaultIban(v)
                  ? null
                  : l.vaultInvalidIban,
            ),
            _field(
              'account',
              l.vaultAccount,
              ltr: true,
              keyboard: TextInputType.number,
              formatters: [_LatinDigits()],
            ),
            _colorRow(theme),
          ],
          _field('notes', l.vaultNotes, lines: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: favorite,
            title: Text(l.vaultFavorite),
            secondary: const Icon(Icons.star_outline),
            onChanged: widget.busy
                ? null
                : (v) {
                    setState(() => favorite = v ?? false);
                    _changed();
                  },
          ),
          const SizedBox(height: NexSpacing.md),
          FilledButton.icon(
            onPressed: widget.busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    FocusManager.instance.primaryFocus?.unfocus();
                    await widget.onSave(_value(normalize: true));
                  },
            icon: const Icon(Icons.lock_outline),
            label: Text(l.vaultSave),
          ),
          const SizedBox(height: 12),
          if (discard)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              children: [
                TextButton(
                  onPressed: widget.busy
                      ? null
                      : () => setState(() => discard = false),
                  child: Text(l.cancel),
                ),
                TextButton(
                  onPressed: widget.busy ? null : widget.onDiscard,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: Text(l.vaultDiscard),
                ),
              ],
            )
          else
            TextButton(
              onPressed: widget.busy
                  ? null
                  : () => setState(() => discard = true),
              child: Text(l.vaultDiscard),
            ),
        ],
      ),
    );
  }

  Widget _colorRow(ThemeData theme) {
    final title = nexLabel(context, 'Card color', 'رنگ کارت');
    final swatch = nexParseTagColor(color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        key: const ValueKey('vault-card-color'),
        contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.md),
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        leading: const Icon(Icons.palette_outlined),
        title: Text(title),
        subtitle: Text(
          swatch == null
              ? nexLabel(context, 'Follows the theme', 'هماهنگ با تم')
              : color!,
          textDirection: swatch == null ? null : TextDirection.ltr,
        ),
        trailing: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: swatch ?? theme.colorScheme.primaryContainer,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
        ),
        enabled: !widget.busy,
        onTap: () async {
          final result = await TagColorPicker.show(
            context,
            initial: color,
            title: title,
            defaultColor: theme.colorScheme.primaryContainer,
          );
          if (result == null || !mounted) return;
          setState(() => color = result.color);
          _changed();
        },
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    bool secret = false,
    bool ltr = false,
    int lines = 1,
    TextInputType? keyboard,
    String? Function(String)? validator,
    List<TextInputFormatter>? formatters,
    Widget? footer,
  }) {
    final l = AppLocalizations.of(context);
    if (lines > 1) {
      // Several lines of the person's own words: the platform's editor, for
      // the same reason every note is (ADR-037), with the private clipboard.
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: NexTextField(
          key: ValueKey('vault-field-$key'),
          controller: fields[key]!,
          enabled: !widget.busy,
          minLines: 1,
          maxLines: lines,
          maxLength: key == 'notes' ? 2000 : 256,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          onCopy: PrivateClipboard.copy,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: label,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NexRadius.md),
            ),
          ),
        ),
      );
    }
    final field = TextFormField(
      key: ValueKey('vault-field-$key'),
      controller: fields[key],
      enabled: !widget.busy,
      obscureText: false,
      maxLength: key == 'notes' ? 2000 : 256,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      contextMenuBuilder: (context, state) =>
          AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: [
              for (final item in state.contextMenuButtonItems)
                if (item.type == ContextMenuButtonType.copy ||
                    item.type == ContextMenuButtonType.cut)
                  ContextMenuButtonItem(
                    type: item.type,
                    label: item.label,
                    onPressed: () async {
                      final c = fields[key]!;
                      final value = c.value;
                      state.hideToolbar();
                      if (!value.selection.isValid) return;
                      try {
                        await PrivateClipboard.copy(
                          value.selection.textInside(value.text),
                        );
                        if (!mounted) return;
                        if (item.type == ContextMenuButtonType.cut &&
                            c.value == value) {
                          final text =
                              value.selection.textBefore(value.text) +
                              value.selection.textAfter(value.text);
                          c.value = TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                              offset: value.selection.start,
                            ),
                          );
                          _changed();
                        }
                      } catch (_) {
                        /* The original text stays intact if copying fails. */
                      }
                    },
                  )
                else
                  item,
            ],
          ),
      textDirection: ltr ? TextDirection.ltr : null,
      keyboardType:
          keyboard ??
          (secret ? TextInputType.visiblePassword : TextInputType.text),
      inputFormatters: formatters,
      onChanged: (_) => _changed(),
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) {
          return l.vaultRequired;
        }
        return validator?.call(v ?? '');
      },
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NexRadius.md),
        ),
      ),
    );
    final body = ltr
        ? Directionality(textDirection: TextDirection.ltr, child: field)
        : NexAutoDirection(controller: fields[key]!, builder: (_, _) => field);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: footer == null
          ? body
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [body, footer],
            ),
    );
  }

  /// What the number so far tells: the bank it looks like, and — only once it
  /// is a whole number — a check digit that does not add up.
  Widget _numberHints(AppLocalizations l, ThemeData theme) {
    final digits = vaultCardDigits(fields['number']!.text);
    final persian = l.localeName == 'fa';
    final bank = _guessedBank;
    final network = vaultNetworkFor(digits);
    final suspicious = validVaultCardShape(digits) && !validVaultCard(digits);
    Widget line(IconData icon, String text, Color color) => Padding(
      padding: const EdgeInsetsDirectional.only(
        start: NexSpacing.sm,
        top: NexSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: NexSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bank != null)
          line(
            Icons.account_balance_outlined,
            l.vaultBankGuess(bank.name(persian: persian)),
            theme.colorScheme.onSurfaceVariant,
          ),
        if (network != null)
          line(
            Icons.credit_card_outlined,
            l.vaultBankGuess(network.label),
            theme.colorScheme.onSurfaceVariant,
          ),
        if (suspicious)
          line(
            Icons.info_outline,
            l.vaultCardChecksum,
            theme.colorScheme.tertiary,
          ),
      ],
    );
  }
}

/// Digits only, in Latin form, for a field that holds a number: a Persian or
/// Arabic digit typed or pasted becomes the same digit in Latin, and anything
/// that is not a digit (or [extra]) is dropped, up to [max] characters.
class _LatinDigits extends TextInputFormatter {
  _LatinDigits({this.max, this.extra = ''});

  final int? max;
  final String extra;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final keep = RegExp('[0-9${RegExp.escape(extra)}]');
    final kept = [
      for (final ch in vaultLatinDigits(newValue.text).split(''))
        if (keep.hasMatch(ch)) ch,
    ].join();
    final text = max != null && kept.length > max!
        ? kept.substring(0, max)
        : kept;
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: text.length < newValue.selection.end
            ? text.length
            : newValue.selection.end.clamp(0, text.length),
      ),
    );
  }
}

/// A card number as it is printed: digits in groups of four, whatever the
/// person typed or pasted — Persian digits, dashes, spaces — up to nineteen.
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digitsOf(String text) =>
        vaultLatinDigits(text).replaceAll(RegExp(r'\D'), '');
    var digits = digitsOf(newValue.text);
    if (digits.length > 19) digits = digits.substring(0, 19);
    final grouped = [
      for (var i = 0; i < digits.length; i += 4)
        digits.substring(i, i + 4 > digits.length ? digits.length : i + 4),
    ].join(' ');
    // Keep the caret after the same digit it was after.
    final end = newValue.selection.end.clamp(0, newValue.text.length);
    final before = digitsOf(
      newValue.text.substring(0, end),
    ).length.clamp(0, digits.length);
    final caret = before == 0 ? 0 : before + (before - 1) ~/ 4;
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(
        offset: caret.clamp(0, grouped.length),
      ),
    );
  }
}
