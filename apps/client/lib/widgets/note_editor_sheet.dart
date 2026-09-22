import 'dart:async';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import 'nex_banner.dart';
import 'nex_dialog.dart';
import 'text_format_menu.dart';

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
  });

  final String initial;
  final NexPreferences preferences;

  /// Test seam for the AI calls, the same one the assistant sheet takes.
  final CloudAIAdapter Function()? client;

  /// Resolves to the edited text, or null when the editor was dismissed.
  static Future<String?> show(
    BuildContext context, {
    required String initial,
    required NexPreferences preferences,
    CloudAIAdapter Function()? client,
  }) => nexShowSheet<String>(
    context: context,
    builder: (_) => NoteEditorSheet(
      initial: initial,
      preferences: preferences,
      client: client,
    ),
  );

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  /// What the text was before each AI edit, newest last.
  ///
  /// A stack rather than one slot: people try two styles in a row, and the
  /// way back from that should be the way they came. It is also the only
  /// record of the original — nothing here is saved until Save, so an edit
  /// that made the note worse costs one tap, not a re-typing.
  final _undo = <String>[];

  bool _expanded = false;
  NexRewriteStyle? _running;

  /// The formatting menu, made once and kept.
  ///
  /// Not `nexFormatContextMenuBuilder(context)` in `build`, which is where it
  /// used to be and is the whole of a bug worth stating: `EditableText`
  /// compares this builder against the previous one **by identity**, and a
  /// fresh closure every rebuild reads as a changed menu. Its answer to that
  /// is to dispose the selection overlay and make a new one after the next
  /// frame — and the selection handles, the magnifier and the toolbar live in
  /// that overlay, with their gesture recognizers. Disposing a recognizer
  /// while a finger is on it cancels the drag, and the handle that replaces it
  /// a frame later never saw the pointer, so nothing resumes.
  ///
  /// This sheet rebuilds on every keystroke — see [_onChanged], which is
  /// already careful not to rebuild on anything less — so the overlay was
  /// being torn down by the last characters typed before a hand reached for
  /// a handle. One closure, held for the life of the sheet, and the overlay
  /// survives every rebuild.
  late final EditableTextContextMenuBuilder _formatMenu =
      nexFormatContextMenuBuilder(context);

  @override
  void initState() {
    super.initState();
    _lastText = _text.text;
    _text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _text.removeListener(_onChanged);
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
    setState(() => _lastText = _text.text);
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
    final before = _text.text.trim();
    if (before.isEmpty) return;
    setState(() => _running = style);
    final adapter = _adapter();
    String? edited;
    try {
      edited = await adapter.rewrite(before, style: style);
    } catch (_) {
      edited = null;
    } finally {
      adapter.close();
    }
    if (!mounted) return;
    setState(() => _running = null);
    if (edited == null) {
      NexBannerHost.of(context)?.show(
        message: AppLocalizations.of(context).aiEditFailed,
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
      NexBannerHost.of(context)?.show(
        message: AppLocalizations.of(context).aiEditUnchanged,
      );
      return;
    }
    setState(() {
      _undo.add(before);
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
      _text.value = TextEditingValue(
        text: previous,
        selection: TextSelection.collapsed(offset: previous.length),
      );
    });
  }

  void _save() => Navigator.pop(context, _text.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final field = NexAutoDirection(
      controller: _text,
      // Persian content in an English-locale app used to render left-aligned:
      // the field followed the ambient (LTR) Directionality rather than the
      // script actually typed into it. [NexAutoDirection] supplies a
      // `Directionality` rather than only the argument below, so the
      // selection handles and the context menu agree with the paragraph they
      // are attached to — see its own doc for why that was the painful half.
      builder: (context, direction) => TextField(
        controller: _text,
        autofocus: true,
        textDirection: direction,
        textAlign: TextAlign.start,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        // Expanded, the field fills what it is given and scrolls inside it;
        // collapsed, it grows with the text up to the box below.
        expands: _expanded,
        maxLines: null,
        minLines: _expanded ? null : 3,
        // See the same field in capture_sheet.dart: BoxWidthStyle.max (the
        // default) paints a double-tap word selection out to the end of the
        // line on Persian text.
        selectionWidthStyle: BoxWidthStyle.tight,
        // The same selection menu the capture sheet has: a note is formatted
        // where it is written, and it is written in both.
        contextMenuBuilder: _formatMenu,
        // Read-only while a model is holding it. Not disabled — the text stays
        // selectable and the same colour, because it is still the note.
        readOnly: _running != null,
        decoration: const InputDecoration(border: InputBorder.none),
        ),
    );

    // The height comes from the constraints rather than from the screen's:
    // inside [NexSheetBody] they are already the sheet's own maximum less its
    // padding and the drag handle, which is exactly the room there is. The
    // arithmetic version of that number overflows by whatever it forgot.
    return NexSheetBody(
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height: _expanded && constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : null,
          child: Column(
          mainAxisSize: _expanded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.editNote, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  tooltip: _expanded ? l10n.editorSmaller : l10n.editorFullScreen,
                  icon: Icon(
                    _expanded
                        ? Icons.close_fullscreen
                        : Icons.open_in_full,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.sm),
            if (_expanded)
              Expanded(child: field)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: field,
              ),
            // The one-tap way back from an edit nobody liked. Present only
            // when there is something to go back to, because a control that
            // is usually disabled teaches people it is never usable.
            if (_undo.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.sm),
              _UndoBar(onUndo: _undoLast),
            ],
            if (_aiAvailable) ...[
              const SizedBox(height: NexSpacing.md),
              _AiActions(
                expanded: _expanded,
                running: _running,
                enabled: _text.text.trim().isNotEmpty,
                onPick: (style) => unawaited(_apply(style)),
              ),
            ],
            const SizedBox(height: NexSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: NexSpacing.sm),
                FilledButton(
                  // Empty is not an edit, it is a note being deleted by a
                  // route that cannot delete notes.
                  onPressed: _text.text.trim().isEmpty || _running != null
                      ? null
                      : _save,
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
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
          Icon(
            Icons.auto_awesome,
            size: 16,
            color: theme.colorScheme.primary,
          ),
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

/// The edits a model can make, as one row of chips.
///
/// Scrolling sideways in the sheet and wrapping when the editor is full
/// screen — which is the whole of what "more room" buys here. Six actions in
/// a scroller means the last three are found by dragging; six in a wrap are
/// simply all there, which is what somebody who has just asked for a bigger
/// editor wants.
class _AiActions extends StatelessWidget {
  const _AiActions({
    required this.expanded,
    required this.running,
    required this.enabled,
    required this.onPick,
  });

  final bool expanded;
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
        if (expanded)
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: chips,
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final chip in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: NexSpacing.sm),
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
  Widget build(BuildContext context) => ActionChip(
    avatar: busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 18),
    label: Text(label),
    onPressed: onTap,
  );
}
