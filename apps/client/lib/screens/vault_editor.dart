import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import '../platform/vault_store.dart';
import '../platform/private_clipboard.dart';

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
      'iban',
      'account',
    ])
      key: TextEditingController(text: widget.entry.value(key)),
  };
  bool discard = false;
  late bool favorite = widget.entry.favorite;
  @override
  void dispose() {
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
              validator: (v) => validVaultCard(v) ? null : l.vaultInvalidCard,
            ),
            _field(
              'expiry',
              l.vaultExpiry,
              ltr: true,
              keyboard: TextInputType.datetime,
              validator: (v) =>
                  v.trim().isEmpty ||
                      RegExp(
                        r'^(0?[1-9]|1[0-2])\s*/\s*(\d{2}|\d{4})$',
                      ).hasMatch(vaultLatinDigits(v.trim()))
                  ? null
                  : l.vaultInvalidExpiry,
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
            ),
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
          const SizedBox(height: 16),
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

  Widget _field(
    String key,
    String label, {
    bool required = false,
    bool secret = false,
    bool ltr = false,
    int lines = 1,
    TextInputType? keyboard,
    String? Function(String)? validator,
  }) {
    final l = AppLocalizations.of(context);
    final field = TextFormField(
      key: ValueKey('vault-field-$key'),
      controller: fields[key],
      enabled: !widget.busy,
      obscureText: false,
      maxLines: lines,
      minLines: 1,
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ltr
          ? Directionality(textDirection: TextDirection.ltr, child: field)
          : NexAutoDirection(
              controller: fields[key]!,
              builder: (_, _) => field,
            ),
    );
  }
}
