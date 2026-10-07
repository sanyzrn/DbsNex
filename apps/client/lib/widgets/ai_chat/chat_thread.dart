part of '../ai_chat_sheet.dart';

/// What the sheet offers before anyone has typed anything.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.controller, required this.onPick});

  final ScrollController controller;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Widgets rather than `IconData`: the first of them is painted, because
    // no Material glyph says "shorten this" (see [NexSummariseIcon]).
    final prompts = <(Widget, String)>[
      (const NexSummariseIcon(), l10n.chatPromptSummarise),
      (const Icon(Icons.checklist_outlined), l10n.chatPromptPlan),
      (const Icon(Icons.lightbulb_outline), l10n.chatPromptIdeas),
    ];
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        0,
      ),
      children: [
        Text(
          l10n.chatGreeting,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: NexSpacing.lg),
        for (final (icon, label) in prompts)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(NexRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onPick(label),
                child: Padding(
                  padding: const EdgeInsets.all(NexSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(NexRadius.md),
                        ),
                        child: IconTheme.merge(
                          data: const IconThemeData(size: 20),
                          child: icon,
                        ),
                      ),
                      const SizedBox(width: NexSpacing.md),
                      Expanded(
                        child: Text(label, style: theme.textTheme.bodyLarge),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The conversation itself.
class _Thread extends StatelessWidget {
  const _Thread({
    required this.controller,
    required this.turns,
    required this.sending,
    required this.failure,
    required this.notes,
    required this.onOpenNote,
  });

  final ScrollController controller;
  final List<ChatMessage> turns;

  /// The notes an answer can cite, by lower-case id.
  final Map<String, Note> notes;
  final ValueChanged<Note> onOpenNote;
  final bool sending;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(NexSpacing.md),
      itemCount: turns.length + (sending || failure != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == turns.length) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(bottom: NexSpacing.sm),
              child: failure != null
                  ? Text(
                      failure!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    )
                  : const SizedBox(width: 120, child: NexSkeleton(height: 16)),
            ),
          );
        }
        final turn = turns[index];
        // What the app looked up for the assistant. It travels as a user
        // turn — the one role every wire format agrees on — but it is not
        // something the person said, and in their bubble, raw, it read as a
        // strange message sent in their name. A quiet line says what was
        // looked at instead.
        if (turn.role == ChatRole.user &&
            turn.content.startsWith('<<<NOTES\n') &&
            turn.content.endsWith('\nNOTES>>>')) {
          return _LookupLine(findings: turn.content);
        }
        final mine = turn.role == ChatRole.user;
        // The assistant's markers come out of what is read: the ids it
        // cited become chips under the bubble, and "[general]" becomes a
        // line saying the answer is not from the notes.
        final cited = mine ? null : NexCitedReply.parse(turn.content);
        // A lookup's findings are sent between data markers; the reader
        // sees what was found, not the fence around it.
        final content =
            cited?.text ??
            (turn.content.startsWith('<<<NOTES\n') &&
                    turn.content.endsWith('\nNOTES>>>')
                ? turn.content.substring(9, turn.content.length - 9)
                : turn.content);
        final sources = [
          for (final id in cited?.noteIds ?? const <String>[])
            if (notes[id] case final note?) note,
        ];
        final bubble = Align(
          alignment: mine
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexSpacing.md,
                  vertical: NexSpacing.sm,
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                ),
                decoration: BoxDecoration(
                  color: mine
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(NexRadius.lg),
                ),
                // Long-press used to copy the whole turn and nothing else
                // could be taken out of it, on the reasoning that what people
                // want from a chat message is all of it. Sometimes. The rest of
                // the time they want the one command, the one address, the one
                // sentence — and had no way to get it, because a `Text` answers
                // no gesture at all. An area gives both: long-press takes the
                // word under the finger and the toolbar that comes with it
                // offers Select all, which is the old gesture two taps later
                // and every other selection besides.
                //
                // Scrolling is unaffected. Selection here begins on a long
                // press, so a finger dragged up the thread is still a scroll.
                child: SelectionArea(
                  contextMenuBuilder: nexSelectionMenu,
                  child: Builder(
                    builder: (context) {
                      // The on-colour that belongs to the container behind it.
                      // Left at the default the user's own words were onSurface on
                      // primaryContainer — a pairing nothing guarantees the
                      // contrast of, and in practice barely readable in the light
                      // theme.
                      final style = theme.textTheme.bodyMedium?.copyWith(
                        color: mine
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      );
                      // The assistant's own turns, and only when there is actually
                      // markup to gain by it. A model asked for a list writes one,
                      // and this is the difference between reading a list and
                      // reading its asterisks. The user's turns stay literal: they
                      // typed what they typed, and quietly eating a character of
                      // it would be the app editing their words.
                      if (!mine && nexLooksLikeMarkdown(content)) {
                        return NexMarkdown(
                          content,
                          style: style,
                          // Selection belongs to the area around the bubble, not
                          // to the text inside it — which is what lets a link in a
                          // reply still answer a tap.
                          selectable: false,
                        );
                      }
                      // Either side may be in either language — the assistant
                      // answers in whatever the output-language setting asks for.
                      // Hugged, in one direction for the whole turn: a bubble is
                      // sized to its content, and a block would draw every reply,
                      // "yes" included, most of the screen wide. Selection
                      // belongs to the area around the bubble.
                      return NexTextSurface(
                        content,
                        style: style,
                        fit: NexTextFit.hug,
                      );
                    },
                  ),
                ),
              ),
              _CopyTurn(text: content),
            ],
          ),
        );
        if (cited == null || (!cited.general && sources.isEmpty)) return bubble;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bubble,
            _Grounding(
              general: cited.general,
              sources: sources,
              onOpenNote: onOpenNote,
            ),
          ],
        );
      },
    );
  }
}

/// What an answer rests on, under its bubble: the notes it used as chips,
/// or one quiet line when it came from general knowledge instead.
class _Grounding extends StatelessWidget {
  const _Grounding({
    required this.general,
    required this.sources,
    required this.onOpenNote,
  });

  final bool general;
  final List<Note> sources;
  final ValueChanged<Note> onOpenNote;

  /// A note in a few words: the first line it has in words, or its kind.
  static String _label(Note note, AppLocalizations l10n) {
    for (final source in [
      note.title,
      note.content,
      note.transcriptText,
      note.ocrText,
      note.linkExcerpt,
    ]) {
      final line = (source ?? '')
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => '');
      if (line.isNotEmpty) return line;
    }
    return switch (note.type) {
      NoteType.text => l10n.text,
      NoteType.voice => l10n.voice,
      NoteType.photo => l10n.photo,
      NoteType.file => l10n.file,
      NoteType.checklist => l10n.checklist,
      NoteType.link => l10n.link,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.md),
      child: Wrap(
        spacing: NexSpacing.xs,
        runSpacing: NexSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (general && sources.isEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.public,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: NexSpacing.xs),
                Text(
                  l10n.assistantGeneralKnowledge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          for (final note in sources)
            ActionChip(
              avatar: Icon(nexNoteTypeIcon(note.type.wireName), size: 16),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  _label(note, l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () => onOpenNote(note),
              tooltip: l10n.assistantOpenSource,
            ),
        ],
      ),
    );
  }
}

/// The small copy button under every turn, the user's and the assistant's.
///
/// Selection inside the bubble takes a part of it; this takes the whole turn
/// in one tap, which is what is wanted most of the time from an answer.
class _CopyTurn extends StatelessWidget {
  const _CopyTurn({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.xs),
      child: IconButton(
        tooltip: MaterialLocalizations.of(context).copyButtonLabel,
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: text.trim()));
          if (context.mounted) nexShowBanner(context, message: l10n.copied);
        },
        icon: const Icon(Icons.copy_rounded),
      ),
    );
  }
}

/// One line, centred and quiet, for what the app looked up between two
/// turns: "Searched your notes", "Read your Cycle summary".
class _LookupLine extends StatelessWidget {
  const _LookupLine({required this.findings});

  final String findings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final what = <(IconData, String)>[
      if (findings.contains('\nCycle') ||
          findings.startsWith('<<<NOTES\nCycle'))
        (Icons.water_drop_outlined, l10n.chatLookedCycle),
      if (findings.contains('Results for "'))
        (Icons.search, l10n.chatLookedSearch),
      if (findings.contains('Threads:'))
        (Icons.forum_outlined, l10n.chatLookedThreads),
      if (findings.contains('Notes with '))
        (Icons.sticky_note_2_outlined, l10n.chatLookedNotes),
    ];
    if (what.isEmpty) what.add((Icons.search, l10n.chatLookedSearch));
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: NexSpacing.md,
          runSpacing: NexSpacing.xs,
          children: [
            for (final (icon, label) in what)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: NexSpacing.xs),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
