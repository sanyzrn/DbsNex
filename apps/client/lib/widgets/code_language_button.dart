import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'nex_dialog.dart';

/// Editing tools shared by quick capture and the full snippet editor.
class NexCodeToolbar extends StatelessWidget {
  const NexCodeToolbar({
    super.key,
    required this.pickerKey,
    required this.language,
    required this.controller,
    required this.focus,
    required this.onSelected,
    this.rawLanguage,
    this.showIndentation = true,
    this.enabled = true,
  });
  final Key pickerKey;
  final NexCodeLanguage language;
  final String? rawLanguage;
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<NexCodeLanguage> onSelected;
  final bool showIndentation;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final refocus = focus.hasFocus;
    final picked = await nexShowSheet<NexCodeLanguage>(
      context: context,
      builder: (context) =>
          _LanguagePalette(language: language, rawLanguage: rawLanguage),
    );
    if (!context.mounted) return;
    if (picked != null) onSelected(picked);
    if (refocus) focus.requestFocus();
  }

  void _indent(bool remove) {
    final before = controller.value;
    final text = before.text;
    final selection = before.selection.isValid
        ? before.selection
        : TextSelection.collapsed(offset: text.length);
    final start = selection.start;
    final end = selection.end;
    final first = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final changes = <(int, int)>[];
    var line = first;
    do {
      final delta = !remove
          ? 2
          : text.startsWith('\t', line)
          ? -1
          : text.startsWith('  ', line)
          ? -2
          : text.startsWith(' ', line)
          ? -1
          : 0;
      if (delta != 0) changes.add((line, delta));
      final next = text.indexOf('\n', line);
      if (next < 0) break;
      line = next + 1;
    } while (line < end);
    if (changes.isEmpty) return;
    final output = StringBuffer();
    var cursor = 0;
    for (final (index, delta) in changes) {
      output.write(text.substring(cursor, index));
      if (delta > 0) output.write('  ');
      cursor = delta < 0 ? index - delta : index;
    }
    output.write(text.substring(cursor));
    int mapped(int offset) {
      var result = offset;
      for (final (index, delta) in changes) {
        if (index > offset) break;
        result += delta < 0 ? delta.clamp(index - offset, 0) : delta;
      }
      return result;
    }

    controller.value = TextEditingValue(
      text: output.toString(),
      selection: selection.copyWith(
        baseOffset: mapped(selection.baseOffset),
        extentOffset: mapped(selection.extentOffset),
      ),
    );
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = nexCodeLanguageLabel(
      context,
      language,
      rawLanguage: rawLanguage,
    );
    return TextFieldTapRegion(
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              child: TextButton.icon(
                key: pickerKey,
                onPressed: enabled ? () => _pick(context) : null,
                icon: NexCodeLanguageGlyph(language, size: 18),
                label: Text(
                  label,
                  semanticsLabel: '${l10n.codeLanguage}: $label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              builder: (context, value, picker) {
                final suggestion =
                    language == NexCodeLanguage.plainText && rawLanguage == null
                    ? _suggestLanguage(value.text)
                    : null;
                return Row(
                  children: [
                    Flexible(child: picker!),
                    if (suggestion != null)
                      Flexible(
                        child: TextButton(
                          key: const ValueKey('code-language-suggestion'),
                          onPressed: enabled
                              ? () => onSelected(suggestion)
                              : null,
                          child: Text(
                            '${nexCodeLanguageLabel(context, suggestion)}?',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            semanticsLabel:
                                '${l10n.codeSuggestedLanguage}: ${nexCodeLanguageLabel(context, suggestion)}',
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (showIndentation) ...[
            IconButton(
              tooltip: l10n.codeOutdent,
              onPressed: enabled ? () => _indent(true) : null,
              icon: const Icon(
                Icons.format_indent_decrease,
                textDirection: TextDirection.ltr,
              ),
            ),
            IconButton(
              tooltip: l10n.codeIndent,
              onPressed: enabled ? () => _indent(false) : null,
              icon: const Icon(
                Icons.format_indent_increase,
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// A hint only: ambiguous input keeps its chosen language. Match a bounded
// prefix so a large paste never makes the keyboard wait for a full scan.
final _languageHints = <NexCodeLanguage, RegExp>{
  NexCodeLanguage.php: RegExp(r'<\?php\b', caseSensitive: false),
  NexCodeLanguage.html: RegExp(
    r'^<(?:!doctype\s+html|html|div|table|head|body|section|script|style)\b',
    caseSensitive: false,
  ),
  NexCodeLanguage.dart: RegExp(
    r"""^(?:import\s+['"](?:dart:|package:)|void\s+main\s*\()""",
  ),
  NexCodeLanguage.python: RegExp(
    r'^(?:(?:async\s+)?def\s+\w+\s*\(|from\s+\S+\s+import\s|#![^\n]*python)',
  ),
  NexCodeLanguage.javascript: RegExp(
    r'^(?:(?:export\s+)?(?:async\s+)?function\s+\w+\s*\(|(?:const|let)\s+\w+\s*=)',
  ),
  NexCodeLanguage.json: RegExp(r'^\s*[\[{]\s*\{?\s*"[^"\n]+"\s*:'),
  NexCodeLanguage.css: RegExp(
    r'^(?:@(?:media|charset|keyframes)\b|[^{};<>]+\{\s*(?:--)?[a-z-]+\s*:)',
  ),
};

NexCodeLanguage? _suggestLanguage(String source) {
  final prefix = source.substring(0, math.min(768, source.length)).trimLeft();
  if (prefix.isEmpty) return null;
  for (final entry in _languageHints.entries) {
    if (entry.value.hasMatch(prefix)) return entry.key;
  }
  return null;
}

class _LanguagePalette extends StatelessWidget {
  const _LanguagePalette({required this.language, this.rawLanguage});
  final NexCodeLanguage language;
  final String? rawLanguage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NexSheetBody(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).codeLanguage,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.md),
            Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.xs,
              children: [
                if (rawLanguage != null)
                  Chip(
                    label: Text(rawLanguage!),
                    avatar: const Icon(Icons.check, size: 16),
                  ),
                for (final lang in NexCodeLanguage.selectable)
                  ChoiceChip(
                    label: Text(nexCodeLanguageLabel(context, lang)),
                    avatar: NexCodeLanguageGlyph(lang, size: 18),
                    showCheckmark: false,
                    selected: rawLanguage == null && lang == language,
                    onSelected: (_) => Navigator.of(context).pop(lang),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What a language is called where a person reads it.
///
/// The names are proper nouns and stay close to their own spelling; only the
/// one that is a description — plain text — is fully translated. An unknown
/// fence keeps the string it arrived with.
String nexCodeLanguageLabel(
  BuildContext context,
  NexCodeLanguage language, {
  String? rawLanguage,
}) {
  final raw = rawLanguage?.trim() ?? '';
  if (raw.isNotEmpty) return raw;
  final l10n = AppLocalizations.of(context);
  return switch (language) {
    NexCodeLanguage.plainText => l10n.codeLanguagePlainText,
    NexCodeLanguage.dart => l10n.codeLanguageDart,
    NexCodeLanguage.javascript => l10n.codeLanguageJavaScript,
    NexCodeLanguage.python => l10n.codeLanguagePython,
    NexCodeLanguage.json => l10n.codeLanguageJson,
    NexCodeLanguage.html => l10n.codeLanguageHtml,
    NexCodeLanguage.css => l10n.codeLanguageCss,
    NexCodeLanguage.php => l10n.codeLanguagePhp,
  };
}
