import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import 'code_editing_controller.dart';
import 'code_language_button.dart';
import 'draft_guard.dart';
import 'keyboard_dismisser.dart';
import 'nex_dialog.dart';
import 'nex_text_field.dart';

/// Editing a snippet: its code and the language it is highlighted as.
///
/// The ordinary editor edits words and trims them; neither is right for
/// source. Here the field is fixed-width and left to right, Return is a
/// newline, and the text is returned exactly as it stands — the language is
/// the second half of what is being edited, in the same sheet, rather than a
/// second menu somewhere after saving.
class NexSnippetEditorSheet extends StatefulWidget {
  const NexSnippetEditorSheet({
    super.key,
    required this.initial,
    required this.preferences,
    this.draftKey,
  });

  final NexCodeSnippet initial;
  final NexPreferences preferences;
  final String? draftKey;

  static Future<NexCodeSnippet?> show(
    BuildContext context, {
    required NexCodeSnippet initial,
    required NexPreferences preferences,
    String? draftKey,
  }) async {
    try {
      return await nexShowSheet<NexCodeSnippet>(
        context: context,
        dismissible: false,
        // The guard owns every way out: a swipe would walk past its question
        // and drop the edit without asking.
        swipeToClose: false,
        builder: (_) => NexSnippetEditorSheet(
          initial: initial,
          preferences: preferences,
          draftKey: draftKey,
        ),
      );
    } finally {
      if (context.mounted) nexDismissKeyboard(context);
    }
  }

  @override
  State<NexSnippetEditorSheet> createState() => _NexSnippetEditorSheetState();
}

class _NexSnippetEditorSheetState extends State<NexSnippetEditorSheet>
    with NexDraftGuard<NexSnippetEditorSheet> {
  late final _code = NexCodeEditingController(
    text: widget.initial.code,
    language: widget.initial.language,
  );
  final _focus = FocusNode();
  late NexCodeLanguage _language = widget.initial.language;
  late String? _rawLanguage = widget.initial.rawLanguage;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    final recovered = widget.draftKey == null
        ? null
        : widget.preferences.editorDrafts?.read(widget.draftKey!);
    final text = recovered?['text'];
    if (text is String) {
      _code.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      final id = recovered?['language'];
      if (id is String) {
        final recoveredLanguage = NexCodeLanguage.fromId(id);
        if (recoveredLanguage != null) _language = recoveredLanguage;
      }
      final raw = recovered?['rawLanguage'];
      _rawLanguage = raw is String ? raw : null;
    }
    _code.language = _language;
    _lastText = _code.text;
    _code.addListener(_onChanged);
  }

  @override
  void dispose() {
    _code.removeListener(_onChanged);
    widget.preferences.editorDrafts?.flushPending();
    _focus.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_code.text == _lastText) return;
    final wasEdited = _lastText != widget.initial.code;
    _lastText = _code.text;
    _writeDraft();
    // PopScope needs a new canPop value on the first edit and after undo.
    if (wasEdited != (_lastText != widget.initial.code)) setState(() {});
  }

  void _writeDraft() {
    final key = widget.draftKey;
    if (key == null) return;
    widget.preferences.editorDrafts?.writeSoon(key, {
      'text': _code.text,
      'language': _language.id,
      'rawLanguage': _rawLanguage,
    });
  }

  @override
  void discardDraft() {
    final key = widget.draftKey;
    if (key != null) widget.preferences.editorDrafts?.clear(key);
  }

  @override
  bool get hasUnsavedChanges =>
      _code.text != widget.initial.code ||
      _language != widget.initial.language ||
      _rawLanguage != widget.initial.rawLanguage;

  void _selectLanguage(NexCodeLanguage language) {
    if (language == _language && _rawLanguage == null) return;
    setState(() {
      _language = language;
      _code.language = language;
      _rawLanguage = null;
    });
    _writeDraft();
  }

  bool get _canSave => _code.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    nexDismissKeyboard(context);
    if (mounted) {
      Navigator.pop(
        context,
        // The same language keeps the fence's whole info string (2.8.19).
        _language == widget.initial.language &&
                _rawLanguage == widget.initial.rawLanguage
            ? widget.initial.withCode(_code.text)
            : NexCodeSnippet(
                code: _code.text,
                language: _language,
                rawLanguage: _rawLanguage,
              ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return guardDraft(
      NexSheetBody(
        padding: const EdgeInsets.fromLTRB(
          NexSpacing.md,
          NexSpacing.sm,
          NexSpacing.md,
          NexSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final room = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height * 0.75;
            return SizedBox(
              height: room,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.editCode,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => unawaited(requestDiscard()),
                        tooltip: l10n.cancel,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  NexCodeToolbar(
                    pickerKey: const ValueKey('snippet-code-language'),
                    language: _language,
                    rawLanguage: _rawLanguage,
                    controller: _code,
                    focus: _focus,
                    onSelected: _selectLanguage,
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(NexSpacing.sm),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(NexRadius.md),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: NexTextField(
                        controller: _code,
                        useNativeEditor: false,
                        focusNode: _focus,
                        autofocus: true,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        textDirection: TextDirection.ltr,
                        monospace: true,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: l10n.codeHint,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => unawaited(requestDiscard()),
                        child: Text(l10n.cancel),
                      ),
                      const Spacer(),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _code,
                        builder: (context, value, _) => FilledButton(
                          onPressed: value.text.trim().isEmpty ? null : _save,
                          child: Text(l10n.save),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
