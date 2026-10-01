part of '../ai_chat_sheet.dart';

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.transcribing,
    required this.onSend,
    required this.onSpeak,
  });

  final TextEditingController controller;

  /// Owned by the sheet, which listens on it: the cursor arriving here is
  /// what takes the sheet up to full height.
  final FocusNode focusNode;
  final bool sending;

  /// A recording is being turned into text. The composer says so rather than
  /// simply going dead — a request over a network with no sign it is running
  /// is the state people tap through twice.
  final bool transcribing;
  final VoidCallback onSend;

  /// Null where speech cannot work: a desktop build, or a provider that does
  /// not hear audio. The button is then absent rather than disabled — there
  /// is nothing the user could do to enable it from here.
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The larger of the keyboard and the system bar, never their sum: the
    // keyboard covers the navigation bar while it is up, so adding both
    // floats the composer a nav-bar's height above the keyboard. With
    // neither — `useSafeArea` deliberately leaves the bottom edge to the
    // sheet — the send button sat under the on-screen buttons on any phone
    // that still has them.
    final bottom = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      nexBottomInset(context),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.md + bottom,
      ),
      child: Row(
        children: [
          if (onSpeak != null)
            IconButton(
              onPressed: sending || transcribing ? null : onSpeak,
              tooltip: l10n.chatSpeak,
              icon: transcribing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mic_none),
            ),
          Expanded(
            // A Persian sentence with an English word in it used to scramble
            // as it was typed and read back correctly the moment it was sent:
            // the field had one direction for everything in it, the bubble
            // one per line. [NexTextField] is the platform's own editor, which
            // does what the bubble does.
            child: NexTextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !transcribing,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: transcribing ? l10n.chatTranscribing : l10n.chatHint,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(NexRadius.xl)),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: NexSpacing.md,
                  vertical: NexSpacing.sm,
                ),
              ),
            ),
          ),
          const SizedBox(width: NexSpacing.sm),
          IconButton.filled(
            onPressed: sending || transcribing ? null : onSend,
            tooltip: l10n.chatSend,
            icon: const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}

/// What the assistant has asked to do, and the button that lets it.
///
/// Nothing the assistant proposes happens without this card being answered.
/// It says the action in the user's own language rather than showing the
/// JSON: "Move this note to Recently Deleted?" is a question someone can
/// answer, and `{"action":"delete"}` is not.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.solar,
    required this.persian,
    required this.actions,
    required this.notes,
    required this.onApply,
    required this.onDismiss,
  });

  final bool solar, persian;
  final List<AssistantAction> actions;

  /// The notes this conversation has seen, by lowercased id — where a card
  /// finds the words to name the note an action changes.
  final Map<String, Note> notes;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  /// The one sentence for this action, in the user's language.
  static String _question(AppLocalizations l10n, AssistantAction action) =>
      switch (action.kind) {
        AssistantActionKind.create => l10n.assistantConfirmCreate,
        AssistantActionKind.edit => l10n.assistantConfirmEdit,
        AssistantActionKind.delete => l10n.assistantConfirmDelete,
        AssistantActionKind.tag => l10n.assistantConfirmTags,
        AssistantActionKind.merge => l10n.assistantConfirmMerge,
        AssistantActionKind.toChecklist => l10n.assistantConfirmChecklist,
        AssistantActionKind.check =>
          action.flag == false
              ? l10n.assistantConfirmUncheck
              : l10n.assistantConfirmCheck,
        AssistantActionKind.setting => l10n.assistantConfirmSetting,
        // Setting one and clearing one are different enough to be worth
        // different words: "stop reminding me" confirmed with "Set a
        // reminder?" is a card that says the opposite of what it does.
        AssistantActionKind.remind =>
          action.at == null
              ? l10n.assistantConfirmRemindClear
              : l10n.assistantConfirmRemind,
        AssistantActionKind.pin =>
          (action.flag ?? true)
              ? l10n.assistantConfirmPin
              : l10n.assistantConfirmUnpin,
        AssistantActionKind.title =>
          action.text == null
              ? l10n.assistantConfirmTitleClear
              : l10n.assistantConfirmTitle,
        AssistantActionKind.restore => l10n.assistantConfirmRestore,
        AssistantActionKind.renameTag => l10n.assistantConfirmRenameTag,
        AssistantActionKind.tagColor => l10n.assistantConfirmTagColor,
        AssistantActionKind.commitment => l10n.assistantConfirmCommitment,
        AssistantActionKind.commitmentMet => l10n.assistantConfirmCommitmentMet,
        AssistantActionKind.commitmentDelete =>
          l10n.assistantConfirmCommitmentDelete,
        AssistantActionKind.thread => l10n.assistantConfirmThread,
        // Shown only for a search the person's words did not ask for; the
        // rest run on arrival.
        AssistantActionKind.search => l10n.assistantConfirmSearch,
        AssistantActionKind.threads => '',
      };

  /// What the action would actually do, in the user's own words where there
  /// are any — a confirmation that does not show the text being written is
  /// asking someone to approve something they cannot see.
  ///
  /// Every fragment in the reader's language (UX-01, LOC-09): this card is
  /// the one place the app asks to be trusted with a change to someone's own
  /// notes, and it used to print `text_size → large` and `every 8 hours`
  /// under a Persian question. The note an action touches is not here; it is
  /// [_noteLabels]' job, so that a run of the same change can name each note.
  String _detail(AppLocalizations l10n, AssistantAction action) {
    String when(DateTime at, NoteRepeat repeat) => [
      '⏰ ${_whenLabel(at)}',
      if (repeat != NoteRepeat.once) nexRepeatLabel(l10n, repeat),
      // A one-off time already gone rings never: say so here, where it can
      // still be declined (AI-03).
      if (repeat == NoteRepeat.once && !at.isAfter(DateTime.now()))
        l10n.assistantReminderPast,
    ].join(' · ');
    return switch (action.kind) {
      // A new note shows its reminder too: approving one without seeing
      // when it rings is approving an alarm blind.
      AssistantActionKind.create => [
        action.text ?? action.items.join('\n'),
        if (action.at case final at?) when(at, action.repeat),
      ].where((line) => line.isNotEmpty).join('\n'),
      AssistantActionKind.edit ||
      AssistantActionKind.merge ||
      AssistantActionKind.toChecklist => action.text ?? '',
      AssistantActionKind.tag => [
        for (final tag in action.addTags) '+$tag',
        for (final tag in action.removeTags) '−$tag',
      ].join('  '),
      AssistantActionKind.setting =>
        '${_settingName(l10n, action.settingKey)}: '
            '${_settingValue(l10n, action.settingKey, action.settingValue)}',
      // The date, spelled out. A reminder card that did not show *when*
      // would be asking somebody to approve an alarm they cannot see the
      // time of, which is the one thing about a reminder that matters.
      AssistantActionKind.remind =>
        action.at == null ? '' : when(action.at!, action.repeat),
      AssistantActionKind.title => action.text ?? '',
      AssistantActionKind.renameTag => '${action.tagName} → ${action.text}',
      AssistantActionKind.tagColor =>
        '${action.tagName} → ${action.text ?? l10n.defaultColor}',
      // The cadence and the date, because those are the whole of what is
      // being agreed to.
      AssistantActionKind.commitment => [
        action.commitmentName ?? '',
        if (action.cadence case final cadence?)
          nexCadenceLabel(l10n, cadence, action.every ?? 1),
        if (action.at case final at?) _whenLabel(at),
      ].where((part) => part.isNotEmpty).join(' · '),
      AssistantActionKind.commitmentMet ||
      AssistantActionKind.commitmentDelete => action.commitmentName ?? '',
      AssistantActionKind.thread => action.threadName ?? '',
      AssistantActionKind.search => _quoted(action.text ?? ''),
      AssistantActionKind.pin ||
      AssistantActionKind.restore ||
      AssistantActionKind.delete ||
      AssistantActionKind.check ||
      AssistantActionKind.threads => '',
    };
  }

  /// The notes [action] changes, in a few words each.
  ///
  /// A delete used to say "Move this note to Recently Deleted? ×12" and name
  /// none of the twelve (SEC-02, AI-08) — the most destructive change asking
  /// for the most trust per note. A note the conversation never showed has
  /// no words to give, and is counted instead.
  List<String> _noteLabels(AppLocalizations l10n, AssistantAction action) {
    final ids = action.kind == AssistantActionKind.create
        ? const <String>[]
        : [?action.noteId, ...action.noteIds];
    return [
      for (final id in ids)
        if (notes[id.toLowerCase()] case final note?)
          _Grounding._label(note, l10n),
    ];
  }

  /// The card's lines: each question and detail, with the notes a run of the
  /// same change touches gathered under it.
  List<({String question, String detail, int count, List<String> notes})>
  _lines(AppLocalizations l10n) {
    final lines =
        <({String question, String detail, int count, List<String> notes})>[];
    for (final action in actions) {
      final question = _question(l10n, action);
      final detail = _detail(l10n, action);
      final labels = _noteLabels(l10n, action);
      if (lines.isNotEmpty &&
          lines.last.question == question &&
          lines.last.detail == detail) {
        final last = lines.removeLast();
        lines.add((
          question: question,
          detail: detail,
          count: last.count + 1,
          notes: [...last.notes, ...labels],
        ));
      } else {
        lines.add((
          question: question,
          detail: detail,
          count: 1,
          notes: labels,
        ));
      }
    }
    return lines;
  }

  /// The settings a conversation may change, by the names their rows have.
  static String _settingName(AppLocalizations l10n, String? key) =>
      switch (key) {
        'theme' => l10n.theme,
        'language' => l10n.language,
        'ai_language' => l10n.aiOutputLanguage,
        'text_size' => l10n.uiScale,
        'palette' => l10n.assistantSettingPalette,
        'accent' => l10n.accentColorSetting,
        'haptics' => l10n.haptics,
        'show_greeting' => l10n.layoutGreeting,
        'show_digest' => l10n.layoutDaySummary,
        'show_search' => l10n.layoutSearchField,
        'show_tags' => l10n.layoutTagRow,
        'daily_nudge' => l10n.nudgeTitle,
        'daily_nudge_time' => l10n.nudgeTime,
        _ => key ?? '',
      };

  /// A setting's new value, in words where the app has words for it.
  String _settingValue(AppLocalizations l10n, String? key, String? value) {
    final v = value ?? '';
    switch (v) {
      case 'on' || 'true' || 'yes':
        return l10n.assistantValueOn;
      case 'off' || 'false' || 'no':
        return l10n.assistantValueOff;
    }
    return switch ((key, v)) {
      ('theme', 'light') => l10n.themeLight,
      ('theme', 'dark') => l10n.themeDark,
      ('theme', 'system') => l10n.themeSystem,
      ('language' || 'ai_language', 'en') => l10n.aiOutputLanguageEnglish,
      ('language' || 'ai_language', 'fa') => l10n.aiOutputLanguagePersian,
      ('language', 'system') => l10n.languageSystem,
      ('ai_language', 'auto') => l10n.aiOutputLanguageAuto,
      ('text_size', 'small') => l10n.uiScaleSmall,
      ('text_size', 'default' || 'normal' || 'medium') => l10n.uiScaleDefault,
      ('text_size', 'large') => l10n.uiScaleLarge,
      ('text_size', 'larger' || 'largest') => l10n.uiScaleLarger,
      ('accent', 'default') => l10n.defaultColor,
      ('palette', _) =>
        [
              for (final preset in nexThemePresets)
                if (preset.id == v) persian ? preset.fa : preset.en,
            ].firstOrNull ??
            v,
      ('daily_nudge_time', _) => nexDigits(v, persian: persian),
      _ => v,
    };
  }

  /// A due date as `2026-03-14 09:00`.
  ///
  /// Not a relative label ("in two days"), which is what the timeline cards
  /// use: this is the moment somebody is about to commit to, and "Friday"
  /// is exactly the word that was ambiguous enough to need confirming.
  String _whenLabel(DateTime when) =>
      nexDisplayDate(when, solar: solar, persian: persian, time: true);

  /// [text] in the quotation marks of the reader's language.
  String _quoted(String text) => persian ? '«$text»' : '“$text”';

  /// "a", "b" and "c", then "and 9 more" — enough to recognise, never a list
  /// that pushes the button off the sheet.
  String _noteList(AppLocalizations l10n, List<String> labels) {
    const shown = 3;
    String clip(String label) =>
        label.length > 40 ? '${label.substring(0, 39)}…' : label;
    return [
      for (final label in labels.take(shown)) _quoted(clip(label)),
      if (labels.length > shown) l10n.assistantMoreNotes(labels.length - shown),
    ].join(persian ? '، ' : ', ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // One destructive action in the set colours the whole card: the button
    // applies all of them together, so the strongest consequence in the set
    // is the one the button carries.
    final destructive = actions.any(
      (action) =>
          action.kind == AssistantActionKind.delete ||
          action.kind == AssistantActionKind.merge,
    );
    final accent = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        0,
        NexSpacing.md,
        NexSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(NexSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NexRadius.lg),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
          color: accent.withValues(alpha: 0.06),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Every action in the set, listed. A single button applying
            // three changes the user was only shown one of is not consent.
            // The same change to several notes is one line with its count —
            // "tag these twelve as work" would otherwise be twelve identical
            // lines pushing the button off the sheet — and a set still too
            // long for the sheet scrolls rather than overflowing it.
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in _lines(l10n)) ...[
                        Text(
                          line.count > 1
                              ? '${line.question}  '
                                    '×${nexDigits('${line.count}', persian: persian)}'
                              : line.question,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (line.notes.isNotEmpty) ...[
                          const SizedBox(height: NexSpacing.xs),
                          Text(
                            _noteList(l10n, line.notes),
                            style: theme.textTheme.bodySmall,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (line.detail case final detail
                            when detail.isNotEmpty) ...[
                          const SizedBox(height: NexSpacing.xs),
                          Text(
                            detail,
                            style: theme.textTheme.bodySmall,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            textDirection: nexDirectionOf(detail),
                            textAlign: TextAlign.start,
                          ),
                        ],
                        const SizedBox(height: NexSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: Text(l10n.cancel)),
                const SizedBox(width: NexSpacing.sm),
                FilledButton(
                  onPressed: onApply,
                  style: destructive
                      ? FilledButton.styleFrom(backgroundColor: accent)
                      : null,
                  child: Text(l10n.assistantApply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
