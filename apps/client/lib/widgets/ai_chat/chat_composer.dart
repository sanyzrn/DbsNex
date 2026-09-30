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
            // Rebuilt on every keystroke, which is the whole point: the field
            // has to change direction as the sentence being typed acquires
            // one. Listening to the controller rather than lifting the text
            // into the sheet's state keeps a per-character rebuild inside
            // this row instead of repainting the transcript above it.
            // [NexAutoDirection] rather than a `ValueListenableBuilder` on the
            // controller: that notifies on every *selection* change too, so
            // the composer was rebuilt on each frame of a handle drag —
            // a field being rebuilt underneath a selection is a selection
            // that will not be dragged. It also owns the `Directionality`,
            // so the hint and the decoration sit on the same side as the
            // words being typed.
            child: NexAutoDirection(
              controller: controller,
              builder: (context, direction) => TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !transcribing,
                minLines: 1,
                maxLines: 5,
                // A Persian sentence with an English word in it was being laid
                // out left-to-right, because the field took its direction from
                // the interface language and never from what was in it. Bidi
                // then reorders the runs around a base direction that is
                // wrong, so the line scrambles as you type — and read back
                // correctly the moment it was sent, since the bubble had been
                // doing this all along.
                textDirection: direction,
                textAlign: TextAlign.start,
                // Same reason as the capture field: the default highlight runs
                // to the end of the line on right-to-left text.
                selectionWidthStyle: BoxWidthStyle.tight,
                contextMenuBuilder: nexReadingMenu,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: transcribing
                      ? l10n.chatTranscribing
                      : l10n.chatHint,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(NexRadius.xl),
                    ),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.md,
                    vertical: NexSpacing.sm,
                  ),
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
    required this.onApply,
    required this.onDismiss,
  });

  final bool solar, persian;
  final List<AssistantAction> actions;
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
        AssistantActionKind.check => l10n.assistantConfirmCheck,
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
        // Never shown: a search is carried out on arrival, not confirmed.
        AssistantActionKind.search => '',
      };

  /// What the action would actually do, in the user's own words where there
  /// are any — a confirmation that does not show the text being written is
  /// asking someone to approve something they cannot see.
  String _detail(AssistantAction action) => switch (action.kind) {
    AssistantActionKind.create ||
    AssistantActionKind.edit ||
    AssistantActionKind.merge ||
    AssistantActionKind.toChecklist => action.text ?? '',
    AssistantActionKind.tag => [
      for (final tag in action.addTags) '+$tag',
      for (final tag in action.removeTags) '−$tag',
    ].join('  '),
    AssistantActionKind.setting =>
      '${action.settingKey} → ${action.settingValue}',
    // The date, spelled out. A reminder card that did not show *when* would
    // be asking somebody to approve an alarm they cannot see the time of,
    // which is the one thing about a reminder that matters.
    AssistantActionKind.remind =>
      action.at == null
          ? ''
          : [
              _whenLabel(action.at!),
              if (action.repeat != NoteRepeat.once)
                '· ${action.repeat.wireName}',
            ].join(' '),
    AssistantActionKind.title => action.text ?? '',
    AssistantActionKind.renameTag => '${action.tagName} → ${action.text}',
    AssistantActionKind.tagColor =>
      '${action.tagName} → ${action.text ?? 'default'}',
    // The cadence and the date, because those are the whole of what is being
    // agreed to. "Set up a recurring item?" with neither is a card asking
    // somebody to approve something they cannot see.
    AssistantActionKind.commitment => [
      action.commitmentName ?? '',
      if (action.cadence case final cadence?)
        '· ${_cadenceWire(cadence, action.every ?? 1)}',
      if (action.at case final at?) '· ${_whenLabel(at)}',
    ].join(' '),
    AssistantActionKind.commitmentMet ||
    AssistantActionKind.commitmentDelete => action.commitmentName ?? '',
    AssistantActionKind.pin ||
    AssistantActionKind.restore ||
    AssistantActionKind.delete ||
    AssistantActionKind.check ||
    AssistantActionKind.search => '',
  };

  /// "every 8 hours", for the confirmation card.
  ///
  /// Deliberately not the localised [nexCadenceLabel]: this sits next to a
  /// raw date in the same line, and the card's job here is to show exactly
  /// what was asked for rather than to read well.
  static String _cadenceWire(NexCadence cadence, int every) =>
      every == 1 ? 'every ${cadence.name}' : 'every $every ${cadence.name}';

  /// A due date as `2026-03-14 09:00`.
  ///
  /// Not a relative label ("in two days"), which is what the timeline cards
  /// use: this is the moment somebody is about to commit to, and "Friday"
  /// is exactly the word that was ambiguous enough to need confirming.
  String _whenLabel(DateTime when) =>
      nexDisplayDate(when, solar: solar, persian: persian, time: true);

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Every action in the set, listed. A single button applying
            // three changes the user was only shown one of is not consent.
            for (final action in actions) ...[
              Text(
                _question(l10n, action),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_detail(action) case final detail when detail.isNotEmpty) ...[
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
