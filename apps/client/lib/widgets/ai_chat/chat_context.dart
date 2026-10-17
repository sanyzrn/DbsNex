part of '../ai_chat_sheet.dart';

/// What the assistant is given: the notes in front of it, the focused
/// note's file and pictures, retrieval and citations.
/// A checklist as words a model reads: what is still to do and what is
/// already done, said outright. Its `- [x]` marks, flattened onto one line,
/// were read as unticked — the assistant called done items still to do.
@visibleForTesting
String? checklistContextLine(Note note) {
  final items = note.checklistItems;
  if (items.isEmpty) return note.content;
  // Each item keeps its place in the list as a number: `check` names an item
  // by that index, and the two groups below are not in list order.
  String said(bool done) => [
    for (var i = 0; i < items.length; i++)
      if (items[i].done == done && items[i].text.trim().isNotEmpty)
        '#$i ${items[i].text.trim()}',
  ].join('; ');
  final open = said(false);
  final done = said(true);
  return [
    if (open.isNotEmpty) 'still to do: $open',
    if (done.isNotEmpty) 'already done: $done',
  ].join('. ');
}

/// What a note's line says about it besides its words: pinned, its
/// reminder, the day it was written. The assistant offered to pin what was
/// pinned and could not answer "what did I write last week".
@visibleForTesting
String noteContextMarks(
  Note note,
  DateTime now, {
  List<String> threads = const [],
}) {
  final written = note.createdAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  // Only for a note that is in one, and only its name: a mark every line
  // carried would be noise the model has to read past.
  final named = [for (final name in threads.take(3)) '"$name"'].join(', ');
  return [
    if (note.pinnedAt != null) 'pinned',
    ?reminderContextLabel(note, now),
    if (threads.isNotEmpty)
      threads.length == 1 ? 'in thread $named' : 'in threads $named',
    'written ${written.year}-${two(written.month)}-${two(written.day)}',
  ].join('; ');
}

/// A note's reminder as words a model reads, or null when it has none still
/// to come. Without it the assistant could not tell a note with a reminder
/// from one without, and offered to set one that was already set.
///
/// Local time in the same `YYYY-MM-DDTHH:MM` shape the `remind` action takes,
/// so changing it is a matter of copying it. A one-off reminder that has
/// already gone off is nothing to wait on and is left out.
@visibleForTesting
String? reminderContextLabel(Note note, DateTime now) {
  final due = note.dueAt;
  if (due == null) return null;
  final repeats = note.dueRepeat != NoteRepeat.once;
  if (!repeats && !due.isAfter(now)) return null;
  final local = due.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final at =
      '${local.year}-${two(local.month)}-${two(local.day)}'
      'T${two(local.hour)}:${two(local.minute)}';
  return repeats
      ? 'reminder set: $at, repeats ${note.dueRepeat.wireName}'
      : 'reminder set: $at';
}

/// A recurring item as the assistant reads it: its name — what the
/// commitment actions name it by — how often it comes round, and when next.
@visibleForTesting
String commitmentContextLine(NexCommitment item) {
  final next = item.dueAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final unit = item.cadence.wireName;
  final every = item.every == 1
      ? 'every ${unit.substring(0, unit.length - 1)}'
      : 'every ${item.every} $unit';
  return [
    '- ${item.title}: $every',
    'next due ${next.year}-${two(next.month)}-${two(next.day)}'
        'T${two(next.hour)}:${two(next.minute)}',
    if (item.paused) 'paused',
  ].join(', ');
}

extension _ChatContext on _AiChatSheetState {
  /// Reads the recent notes the assistant is allowed to see.
  ///
  /// Bounded by the user's own setting, and each note reduced to one line
  /// with its id in front — the id is what makes "delete that one" possible
  /// to act on without the model guessing which note was meant.
  Future<void> _loadNotesContext() async {
    final focused = widget.focus;
    if (focused != null) {
      // A far bigger budget than a volunteered note gets, because this one is
      // the subject: somebody opened the assistant on it to ask about it, and
      // four hundred characters of a document is a paragraph of an answer
      // about a page nobody read.
      await _knowThreads([focused]);
      final line = _contextLine(
        focused,
        limit: 6000,
        fileText: await _fileText(focused),
      );
      final images = _imagesFor(focused);
      _remember([focused]);
      if (mounted) {
        _rebuild(() {
          if (line != null) _notesContext = line;
          _attachments = images;
        });
      }
      return;
    }
    // A whole date run, and all of it: the reader picked this set, so it is
    // not the app's place to trim it down to the context setting — that
    // number is about how much of the *library* to volunteer when nobody has
    // said what the question is about.
    if (widget.scope case final scoped?) {
      _remember(scoped);
      await _knowThreads(scoped);
      final lines = <String>[
        for (final note in scoped)
          if (_contextLine(note) case final line?) line,
      ];
      if (mounted) _rebuild(() => _notesContext = lines.join('\n'));
      return;
    }
    final count = widget.preferences.aiNotesContextCount;
    if (count == 0) return;
    List<Note> notes;
    try {
      notes = await widget.services.timeline(limit: count);
    } catch (_) {
      return;
    }
    _remember(notes);
    await _knowThreads(notes);
    final lines = <String>[
      for (final note in notes)
        if (_contextLine(note) case final line?) line,
    ];
    if (!mounted) return;
    _rebuild(() => _notesContext = lines.join('\n'));
  }

  /// The focused note in a few words, for the line that says what this chat is
  /// about.
  ///
  /// Title first where there is one, then whatever the note carries in words —
  /// a recording's transcript and a photo's extracted text included, because
  /// those are exactly the notes with nothing typed on them and exactly the
  /// ones someone opens this from.
  String _focusLabel(Note note) {
    final source = (note.title?.trim().isNotEmpty ?? false)
        ? note.title!.trim()
        : (note.content ?? note.transcriptText ?? note.ocrText ?? '').trim();
    final line = source
        .split('\n')
        .firstWhere(
          (candidate) => candidate.trim().isNotEmpty,
          orElse: () => '',
        );
    return line.length <= 40 ? line : '${line.substring(0, 39)}…';
  }

  /// One note as the assistant sees it: its id, then whatever words it has.
  ///
  /// The id goes first because it is what an action refers back to — without
  /// one, "delete that one" can only be guessed at. The text is everything
  /// the note carries in words rather than only what its card shows: a
  /// photo's OCR read and a recording's transcript are the only way the
  /// assistant knows those notes exist as anything but "a photo".
  String? _contextLine(Note note, {int limit = 400, String? fileText}) {
    final text =
        [
              note.title,
              // The person's own line on a photo, voice or file note.
              note.caption,
              if (note.type == NoteType.checklist)
                checklistContextLine(note)
              else
                note.content,
              note.transcriptText,
              note.ocrText,
              note.linkExcerpt,
              // What is *inside* an attached file, for the kinds this app can
              // read. Without it the assistant knew a note had a markdown
              // file on it and nothing about what the file said — so a
              // question about a document sitting open on the screen was
              // answered from its filename.
              //
              // Passed in rather than read here: a `.docx` has to be unzipped
              // on another isolate, and this method is synchronous because
              // the twenty volunteered notes go through it in a loop.
              fileText,
            ]
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .join(' — ')
            .replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return null;
    final clipped = text.length > limit ? '${text.substring(0, limit)}…' : text;
    // Its tags, so "the ones tagged work" can be answered from what is
    // already in front of the model, and acted on without a search.
    final tags = [for (final tag in note.tags) '#${tag.name}'].join(' ');
    // Pinned, its reminder and its date, so "remind me about it" is not
    // offered for a note that already has one and "when is it?" is answered
    // rather than guessed.
    final marks = noteContextMarks(
      note,
      DateTime.now(),
      threads: _threadsOf[note.id] ?? const [],
    );
    return '[${note.id}] ${note.type.wireName}${tags.isEmpty ? '' : ' $tags'}'
        ' ($marks): $clipped';
  }

  /// Which threads each of [notes] is in, by name, for [_contextLine] —
  /// asked once per note and kept for the conversation.
  Future<void> _knowThreads(Iterable<Note> notes) async {
    for (final note in notes) {
      if (_threadsOf.containsKey(note.id)) continue;
      try {
        _threadsOf[note.id] = [
          for (final thread in await widget.services.threadsForNote(note.id))
            thread.name,
        ];
      } catch (_) {
        _threadsOf[note.id] = const [];
      }
    }
  }

  /// The text of the file attached to [note], for the kinds Nex can read.
  ///
  /// The same kinds the detail sheet renders in place, which is the honest
  /// boundary: if the app can show it to you, it can tell the assistant about
  /// it. Markdown, plain text, code and delimited tables are read straight
  /// off the disk; a `.docx` is a zip of XML, so it goes to the same reader
  /// the note's own preview uses, on another isolate. A PDF is still named
  /// and not read — Nex has no renderer for one, and handing the assistant a
  /// file it cannot read only produces a confident guess.
  ///
  /// The focused note only. The volunteered notes — the recent ones nobody
  /// has pointed at — are read in a loop when the sheet opens, and opening a
  /// sheet is the one moment that must not stall. It is also the narrower
  /// answer on what leaves the device, which is the right way round for a
  /// file somebody attached rather than typed.
  Future<String?> _fileText(Note note) async {
    final path = note.mediaUri;
    if (path == null || path.isEmpty) return null;
    final kind = NexFileKinds.of(path: path, mimeType: note.mimeType);
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      if (kind == NexFileKind.document) {
        if (NexFileKinds.extensionOf(path) != 'docx') return null;
        if (file.lengthSync() > NexDocx.maxBytes) return null;
        final read = await Isolate.run(
          () => NexDocx.read(File(path).readAsBytesSync()),
        );
        final markdown = read?.markdown.trim();
        return (markdown == null || markdown.isEmpty) ? null : markdown;
      }
      if (kind != NexFileKind.markdown &&
          kind != NexFileKind.plainText &&
          kind != NexFileKind.code &&
          kind != NexFileKind.table) {
        return null;
      }
      // A cap in bytes before a cap in characters: a log somebody attached
      // could be megabytes, and reading it whole to throw most of it away is
      // the work this guard exists to skip.
      if (file.lengthSync() > 512 * 1024) return null;
      final text = file.readAsStringSync().trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      // A binary mislabelled as text, a document this reader cannot parse, or
      // a file the OS took back. None of them is worth an error in a chat
      // sheet: the note's own words still go.
      return null;
    }
  }

  /// The focused note's picture, if the provider can see one.
  ///
  /// Only the focused note. Attaching the images of twenty recent notes to
  /// every question would be a bill nobody agreed to and a prompt no model
  /// answers well; the note somebody opened the assistant *on* is the one
  /// they are asking about.
  List<NexChatAttachment> _imagesFor(Note note) {
    if (!widget.preferences.aiProvider.supportsImages) {
      return const [];
    }
    final path = note.mediaUri;
    if (path == null || path.isEmpty) return const [];
    if (NexFileKinds.of(path: path, mimeType: note.mimeType) !=
        NexFileKind.image) {
      return const [];
    }
    try {
      final file = File(path);
      if (!file.existsSync()) return const [];
      // Providers reject a base64 image past a few megabytes, and a photo
      // that big says nothing a smaller one does not.
      if (file.lengthSync() > 8 * 1024 * 1024) return const [];
      return [
        NexChatAttachment(
          bytes: file.readAsBytesSync(),
          mimeType: note.mimeType?.startsWith('image/') ?? false
              ? note.mimeType!
              : 'image/jpeg',
        ),
      ];
    } catch (_) {
      return const [];
    }
  }

  AiChatOptions get _options => AiChatOptions(
    creativity: widget.preferences.aiCreativity,
    length: widget.preferences.aiAnswerLength,
    notesOnly: widget.preferences.aiNotesOnly,
    // Tone has one control: a preset says how to sound, and "Custom" replaces
    // it with the user's own sentence. Sending both would be two answers to
    // one question — "be formal" and "be witty and sarcastic" arriving
    // together, with nothing to say which wins — so the text only travels
    // under the style it belongs to. It stays in storage either way, so
    // switching back to Custom brings it back rather than asking for it again.
    instruction: widget.preferences.aiResponseStyle == AiResponseStyle.custom
        ? widget.preferences.aiInstruction
        : '',
    responseStyle: widget.preferences.aiResponseStyle,
    userName: widget.preferences.aiUserName,
    userIntroduction: widget.preferences.aiUserIntroduction,
    gentle: _gentle,
    notesContext: _context,
    attachments: _attachments,
    // Acting needs ids to act on. With no notes in context every id the model
    // could produce would be invented, which is the one thing the prompt
    // tells it not to do.
    canAct: _context.isNotEmpty,
    currentSettings: _currentSettings,
    appGuide: _guide,
  );

  /// The settings [assistantSettableKeys] covers, as they are now, in the
  /// values a `setting` action takes.
  String get _currentSettings {
    final p = widget.preferences;
    String onOff(bool on) => on ? 'on' : 'off';
    String two(int value) => value.toString().padLeft(2, '0');
    final scale = p.uiScale;
    return [
      'theme ${p.themeMode.name}',
      'language ${p.locale?.languageCode ?? 'system'}',
      'ai_language ${p.aiOutputLanguage.wireName}',
      'text_size ${scale < 0.95
          ? 'small'
          : scale < 1.1
          ? 'default'
          : scale < 1.25
          ? 'large'
          : 'larger'}',
      'palette ${p.themePreset}',
      'accent ${p.accentSeed ?? 'default'}',
      'haptics ${onOff(p.haptics)}',
      'show_greeting ${onOff(p.showGreeting)}',
      'show_digest ${onOff(p.showDaySummary)}',
      'show_search ${onOff(p.showSearchField)}',
      'show_tags ${onOff(p.showTagRow)}',
      'daily_nudge ${onOff(p.dailyNudge)}',
      'daily_nudge_time ${two(p.dailyNudgeMinutes ~/ 60)}:'
          '${two(p.dailyNudgeMinutes % 60)}',
    ].join(', ');
  }

  /// Finds the notes a question is about through the same ranked search the
  /// search field uses (W2.4) — words and meaning, best first — so the
  /// assistant answers from the notes that match, not only from the most
  /// recent ones. Skipped for a chat about one note or one day: there the
  /// reader has already said what the question is about.
  Future<void> _retrieveFor(String question) async {
    if (widget.focus != null || widget.scope != null) return;
    List<Note> found;
    try {
      found = await widget.services.fusedSearch(SearchFilters(query: question));
    } catch (_) {
      found = const [];
    }
    await _knowThreads(found.take(_AiChatSheetState._retrievedCount));
    final lines = <String>[
      for (final note in found.take(_AiChatSheetState._retrievedCount))
        if (_contextLine(note) case final line?) line,
    ];
    _remember(found.take(_AiChatSheetState._retrievedCount));
    _retrieved = lines.join('\n');
  }

  /// Everything the assistant answers from: the notes it was given when the
  /// chat opened, and those matching the latest question.
  String get _context => [
    if (_notesContext.isNotEmpty) _notesContext,
    if (_retrieved.isNotEmpty)
      'Notes matching the latest question, best match first:\n$_retrieved',
  ].join('\n\n');

  /// Looks up any note an answer cites that this sheet has not seen — a
  /// resumed conversation's, or one the library changed under.
  ///
  /// A note that is gone, or in Recently Deleted, stays unresolved and its
  /// chip is simply not drawn: a chip that opens nothing is worse than none.
  Future<void> _resolveCitations() async {
    final missing = <String>{
      for (final turn in _turns)
        if (turn.role == ChatRole.assistant)
          ...NexCitedReply.parse(turn.content).noteIds,
    }.where((id) => !_notes.containsKey(id));
    var changed = false;
    for (final id in missing) {
      try {
        final note = await widget.services.getById(id);
        if (note != null && note.deletedAt == null) {
          _notes[id] = note;
          changed = true;
        }
      } catch (_) {}
    }
    if (changed && mounted) _rebuild(() {});
  }

  Future<void> _openCited(Note note) async {
    await nexShowSheet<DetailResult>(
      context: context,
      builder: (_) => NoteDetailSheet(
        services: widget.services,
        preferences: widget.preferences,
        noteId: note.id,
      ),
    );
    await widget.services.refreshTimeline();
  }
}
