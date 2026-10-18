import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'draft_guard.dart';
import 'package:nex_ai/cloud.dart';
import '../platform/nex_preferences.dart';
import '../platform/crash_reporter.dart';
import 'nex_banner.dart';
import 'nex_dialog.dart';
import 'nex_text_field.dart';
import 'keyboard_dismisser.dart';

/// Editing a note's words.
///
/// This was an `AlertDialog` with a three-line field in it, which is the
/// shape a *confirmation* has: a question, and two buttons under it. Editing
/// is not a question — it is the app's second-longest-running activity after
/// writing, and it was being done through a letterbox, in a box that could
/// not grow, on a surface nothing else in the app uses.
///
/// So it is a sheet, like everything else that opens here, and it can become
/// as tall as the screen when the note is long enough to need it. The size is
/// a `setState`, not a second route: expanding is a change of how much room
/// the same editor has, and pushing a page to say that would mean two editors
/// with two copies of the text, a result to hand back, and a question about
/// what the back gesture means that has no good answer.
///
/// With a model available — a provider, or one downloaded onto the phone —
/// the editor can also hand the whole note to it. See [NexRewriteStyle] for
/// what each action is allowed to do; the rule that matters here is that
/// nothing it returns is saved until Save, and everything it returns can be
/// put back with one tap.
class NoteEditorSheet extends StatefulWidget {
  const NoteEditorSheet({
    super.key,
    required this.initial,
    required this.preferences,
    this.client,
    this.draftKey,
    this.allowEmpty = false,
    this.noteId,
  });

  final String initial;

  /// The note being edited, named in the log of what left the phone when
  /// the text is sent for a rewrite.
  final String? noteId;
  final String? draftKey;
  final bool allowEmpty;
  final NexPreferences preferences;

  /// Test seam for the AI calls, the same one the assistant sheet takes.
  final CloudAIAdapter Function()? client;

  /// Resolves to the edited text, or null when the editor was dismissed.
  static Future<String?> show(
    BuildContext context, {
    required String initial,
    required NexPreferences preferences,
    CloudAIAdapter Function()? client,
    String? draftKey,
    bool allowEmpty = false,
    String? noteId,
  }) async {
    try {
      return await nexShowSheet<String>(
        context: context,
        dismissible: false,
        swipeToClose: true,
        builder: (_) => NoteEditorSheet(
          initial: initial,
          preferences: preferences,
          client: client,
          draftKey: draftKey,
          allowEmpty: allowEmpty,
          noteId: noteId,
        ),
      );
    } finally {
      if (context.mounted) nexDismissKeyboard(context);
    }
  }

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet>
    with NexDraftGuard<NoteEditorSheet> {
  @override
  bool get hasUnsavedChanges => _text.text != widget.initial;
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  /// What the text was before each AI edit, newest last.
  ///
  /// A stack rather than one slot: people try two styles in a row, and the
  /// way back from that should be the way they came. It is also the only
  /// record of the original — nothing here is saved until Save, so an edit
  /// that made the note worse costs one tap, not a re-typing.
  final _undo = <TextEditingValue>[];
  final _focus = FocusNode();
  bool _aiTrayOpen = false;
  int _editRevision = 0;

  bool _expanded = false;
  bool _saving = false;
  NexRewriteStyle? _running;

  /// Keeps the one field — and Android's editor under it, with its caret,
  /// selection and keyboard — when it moves between the two layouts.
  final _fieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final recovered = widget.preferences.editorDrafts?.read(
      widget.draftKey ?? '',
    )?['text'];
    if (widget.draftKey != null && recovered is String) _text.text = recovered;
    _lastText = _text.text;
    _text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _text.removeListener(_onChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// The text as the chrome below last saw it.
  ///
  /// A `TextEditingController` notifies its listeners when the **selection**
  /// moves as well as when the text does, and this listener rebuilt the whole
  /// sheet on every one of them. Dragging a selection handle is a stream of
  /// selection changes, so the field was being rebuilt underneath the drag,
  /// frame after frame — which is what made selecting text in here feel like
  /// it was fighting back, in both languages.
  ///
  /// Nothing the rebuild is for depends on the selection: it is whether Save
  /// is allowed, and whether there is anything for the AI actions to work on.
  /// So the text is what is watched.
  String _lastText = '';

  /// Only the things the chrome shows: whether Save is allowed, and whether
  /// there is text to rewrite. Direction is [NexAutoDirection]'s job now.
  void _onChanged() {
    if (_text.text == _lastText) return;
    if (widget.draftKey case final key?) {
      widget.preferences.editorDrafts?.writeSoon(key, {'text': _text.text});
    }
    setState(() => _lastText = _text.text);
  }

  @override
  void discardDraft() {
    if (widget.draftKey case final key?) {
      widget.preferences.editorDrafts?.clear(key);
    }
  }

  bool get _aiAvailable =>
      widget.preferences.aiEnabled &&
      aiTextAvailableWith(widget.preferences.aiProvider);

  CloudAIAdapter _adapter() =>
      widget.client?.call() ??
      CloudAIAdapter(
        config: widget.preferences.aiProvider,
        outputLanguage: widget.preferences.aiOutputLanguage,
      );

  Future<void> _apply(NexRewriteStyle style) async {
    if (_running != null) return;
    final original = _text.value;
    final before = original.text.trim();
    if (before.isEmpty) return;
    setState(() => _running = style);
    final adapter = _adapter();
    String? edited;
    try {
      edited = await NexDisclosureLog.about(
        notes: [?widget.noteId],
        () => adapter.rewrite(before, style: style),
      );
    } catch (error) {
      unawaited(NexCrashLog.handled('editor.rewrite', error));
      edited = null;
    } finally {
      adapter.close();
    }
    if (!mounted) return;
    setState(() => _running = null);
    if (_text.text != original.text) return;
    if (edited == null) {
      NexBannerHost.of(context)?.show(
        message: adapter.lastReplyTruncated
            ? AppLocalizations.of(context).aiIncompleteReply
            : AppLocalizations.of(context).aiEditFailed,
        kind: NexBannerKind.failed,
      );
      return;
    }
    // Copied to a final before the closure below reads it: a nullable local
    // that is assigned more than once is not promoted inside one.
    final result = edited;
    if (result.trim() == before) {
      // Said out loud rather than left as a button that did nothing. "Fix
      // writing" on text with nothing wrong with it is a success, and silence
      // is what a broken button looks like.
      NexBannerHost.of(
        context,
      )?.show(message: AppLocalizations.of(context).aiEditUnchanged);
      return;
    }
    setState(() {
      _undo.add(original);
      _editRevision++;
      // The caret goes to the end rather than staying where it was: the text
      // under it is not the text it was in.
      _text.value = TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    setState(() {
      _editRevision++;
      _text.value = previous;
    });
  }

  void _save() {
    if (_saving) return;
    _saving = true;
    nexDismissKeyboard(context);
    if (mounted) Navigator.pop(context, _text.text);
  }

  bool get _canSave =>
      (widget.allowEmpty || _text.text.trim().isNotEmpty) && _running == null;
  void _toggleSize() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Keep the Android texture view in one hierarchy and one expanding mode.
    // Reparenting it between two layouts can detach its drawing surface.
    final field = NexBorderBeam(
      token: _editRevision,
      active: _editRevision > 0,
      laps: 1,
      period: NexMotion.morph * 2,
      strength: 0.3,
      thickness: 0.6,
      colors: [
        scheme.primary.withValues(alpha: 0.05),
        scheme.primary,
        scheme.primary.withValues(alpha: 0.05),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
        child: NexTextField(
          key: _fieldKey,
          controller: _text,
          focusNode: _focus,
          autofocus: true,
          expands: true,
          minLines: null,
          formatting: true,
          readOnly: _running != null,
          decoration: const InputDecoration(border: InputBorder.none),
        ),
      ),
    );
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
                : MediaQuery.sizeOf(context).height * 0.85;
            final showStyles =
                _aiAvailable && (!_expanded || _aiTrayOpen) && room > 420;
            final showUndo = !_expanded && _undo.isNotEmpty && room > 340;
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final chrome =
                124.0 +
                (showStyles ? 100 * scale : 0) +
                (showUndo ? 56 * scale : 0);
            return AnimatedContainer(
              key: const ValueKey('note-editor-frame'),
              duration: NexMotion.of(context, NexMotion.morph),
              curve: NexMotion.curve,
              height: _expanded ? room : math.min(room, chrome + 220),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: NexMotion.of(context, NexMotion.fast),
                          child: _expanded
                              ? const SizedBox.shrink(
                                  key: ValueKey('editor-no-title'),
                                )
                              : Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    l10n.editNote,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                ),
                        ),
                      ),
                      if (_expanded && _undo.isNotEmpty)
                        IconButton(
                          onPressed: _undoLast,
                          tooltip: l10n.aiEditUndo,
                          icon: const Icon(Icons.undo),
                        ),
                      IconButton(
                        onPressed: _toggleSize,
                        tooltip: _expanded
                            ? l10n.editorSmaller
                            : l10n.editorFullScreen,
                        icon: AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: NexMotion.of(context, NexMotion.slow),
                          curve: NexMotion.curve,
                          child: Icon(
                            _expanded
                                ? Icons.close_fullscreen
                                : Icons.open_in_full,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Expanded(child: field),
                  NexReveal(
                    visible: showUndo,
                    child: Padding(
                      padding: const EdgeInsets.only(top: NexSpacing.sm),
                      child: _UndoBar(onUndo: _undoLast),
                    ),
                  ),
                  NexReveal(
                    visible: showStyles,
                    child: Padding(
                      padding: const EdgeInsets.only(top: NexSpacing.md),
                      child: _AiActions(
                        running: _running,
                        enabled: _text.text.trim().isNotEmpty,
                        onPick: (style) => unawaited(_apply(style)),
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Row(
                    children: [
                      if (_aiAvailable && (_expanded || !showStyles))
                        IconButton(
                          tooltip: l10n.aiEditTools,
                          isSelected: _aiTrayOpen,
                          onPressed: _running != null
                              ? null
                              : () {
                                  if (room <= 420) {
                                    nexDismissKeyboard(context);
                                  }
                                  setState(() => _aiTrayOpen = !_aiTrayOpen);
                                },
                          icon: AnimatedSwitcher(
                            duration: NexMotion.of(context, NexMotion.fast),
                            child: _running != null
                                ? const SizedBox(
                                    key: ValueKey('editor-working'),
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _aiTrayOpen
                                        ? Icons.auto_awesome
                                        : Icons.auto_awesome_outlined,
                                    key: ValueKey(_aiTrayOpen),
                                    color: scheme.primary,
                                  ),
                          ),
                        ),
                      const Spacer(),
                      if (_expanded)
                        IconButton(
                          onPressed: requestDiscard,
                          tooltip: l10n.cancel,
                          icon: const Icon(Icons.close),
                        )
                      else
                        TextButton(
                          onPressed: requestDiscard,
                          child: Text(l10n.cancel),
                        ),
                      const SizedBox(width: NexSpacing.sm),
                      if (_expanded)
                        IconButton.filled(
                          onPressed: _canSave ? _save : null,
                          tooltip: l10n.save,
                          icon: const Icon(Icons.check),
                        )
                      else
                        FilledButton(
                          onPressed: _canSave ? _save : null,
                          child: Text(l10n.save),
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

/// "Edited by AI — Undo", over the field it changed.
class _UndoBar extends StatelessWidget {
  const _UndoBar({required this.onUndo});

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: NexSpacing.md, right: NexSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              l10n.aiEditApplied,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onUndo, child: Text(l10n.aiEditUndo)),
        ],
      ),
    );
  }
}

/// The edits a model can make, as one row of chips scrolling sideways.
///
/// Full screen reveals the same tray on demand to leave room for the note.
class _AiActions extends StatelessWidget {
  const _AiActions({
    required this.running,
    required this.enabled,
    required this.onPick,
  });

  final NexRewriteStyle? running;
  final bool enabled;
  final ValueChanged<NexRewriteStyle> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chips = [
      for (final style in NexRewriteStyle.values)
        _StyleChip(
          key: ValueKey(style),
          label: _label(l10n, style),
          icon: _icon(style),
          busy: running == style,
          // One at a time. A second request while the first is in flight
          // would be two answers racing for the same field.
          onTap: !enabled || running != null ? null : () => onPick(style),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.aiEditTools,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final chip in chips)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
                  child: chip,
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _label(AppLocalizations l10n, NexRewriteStyle style) =>
      switch (style) {
        NexRewriteStyle.autoStyle => l10n.aiEditAutoStyle,
        NexRewriteStyle.fix => l10n.aiEditFix,
        NexRewriteStyle.formal => l10n.aiEditFormal,
        NexRewriteStyle.friendly => l10n.aiEditFriendly,
        NexRewriteStyle.concise => l10n.aiEditConcise,
        NexRewriteStyle.simple => l10n.aiEditSimple,
      };

  /// A glyph each, because six chips of pure text read as a paragraph of
  /// buttons. None of them is a picture of the writing — they are pictures of
  /// the *act*: a wand, a tick, a tie.
  static IconData _icon(NexRewriteStyle style) => switch (style) {
    NexRewriteStyle.autoStyle => Icons.auto_fix_high_outlined,
    NexRewriteStyle.fix => Icons.spellcheck,
    NexRewriteStyle.formal => Icons.work_outline,
    NexRewriteStyle.friendly => Icons.chat_bubble_outline,
    NexRewriteStyle.concise => Icons.compress,
    NexRewriteStyle.simple => Icons.wb_sunny_outlined,
  };
}

/// The same six edits behind one button, for the full-screen editor.
class _StyleChip extends StatelessWidget {
  const _StyleChip({
    super.key,
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => NexPress(
    enabled: onTap != null,
    child: AnimatedScale(
      scale: busy ? 1.035 : 1,
      duration: NexMotion.of(context, NexMotion.standard),
      curve: NexMotion.curve,
      child: ActionChip(
        avatar: AnimatedSwitcher(
          duration: NexMotion.of(context, NexMotion.fast),
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 18, key: const ValueKey('style-icon')),
        ),
        label: Text(label),
        onPressed: onTap,
      ),
    ),
  );
}
