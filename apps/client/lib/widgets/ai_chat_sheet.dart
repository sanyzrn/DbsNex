import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../documents/docx_markdown.dart';
import '../l10n/app_localizations.dart';
import 'dismiss_on_overscroll.dart';
import 'assistant_settings.dart';
import '../platform/ai_provider.dart';
import '../platform/assistant_actions.dart';
import '../platform/chat_history.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import 'card_strings.dart';
import 'nex_banner.dart';
import 'nex_dialog.dart';
import 'recording_sheet.dart';

/// The assistant, reached by holding the capture button.
///
/// Opens as a short sheet and is dragged up to full screen — small because it
/// starts as a question and not a place you moved into, and expandable because
/// an answer worth reading needs the room. There is no separate "open the chat
/// screen" step: the same sheet is both.
///
/// Deliberately not wired through `ChatAdapterBinding`. That port is bound
/// only by the `ai` flavour's entry point, so on the shipped build it resolves
/// to `NullChatAdapter` and every message would come back "unavailable" — the
/// exact bug the Settings chat screen has. This talks to the provider the user
/// configured, through the same [CloudAIAdapter] the timeline's headline and
/// digest already use, and honours the same output-language setting.
class AiChatSheet extends StatefulWidget {
  const AiChatSheet({
    super.key,
    required this.preferences,
    required this.services,
    required this.history,
    this.resume,
    this.focus,
    this.scope,
    this.scopeLabel,
    this.client,
  });

  final NexPreferences preferences;

  /// The notes themselves — read for the context the assistant answers from,
  /// and written by the actions it asks for.
  final NexServices services;

  final ChatHistory history;

  /// A saved conversation to carry on with, or null for a new one.
  final ChatThread? resume;

  /// One note to talk about, instead of the recent library.
  ///
  /// What "ask about this note" opens. The context becomes that note alone,
  /// which is both what makes the answers specific and what keeps the
  /// question cheap — there is no reason to send twenty notes to ask about
  /// the one already on screen.
  final Note? focus;

  /// A run of notes to talk about, instead of one note or the recent library.
  ///
  /// What "ask about these" on a date heading opens. Same idea as [focus] and
  /// the same reason: the context is exactly the notes the question is about,
  /// which is what makes the answer specific and what stops the request
  /// carrying twenty unrelated notes to get there.
  final List<Note>? scope;

  /// What to call that run — the date heading's own words.
  final String? scopeLabel;

  /// Stands in for the network in tests.
  ///
  /// A seam rather than a mock of the whole sheet: what has to be provable
  /// here is that a model asking to delete a note does not delete it, and
  /// that is only provable by putting a real reply in and watching what the
  /// library does — which needs a reply this side of the network.
  @visibleForTesting
  final http.Client? client;

  /// Whether there is a provider behind this at all. The caller checks before
  /// opening, so nobody is shown a chat that cannot answer.
  static bool availableFor(NexPreferences preferences) =>
      preferences.aiEnabled && aiTextAvailableWith(preferences.aiProvider);

  static Future<void> show(
    BuildContext context, {
    required NexPreferences preferences,
    required NexServices services,
    required ChatHistory history,
    ChatThread? resume,
    Note? focus,
    List<Note>? scope,
    String? scopeLabel,
    http.Client? client,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AiChatSheet(
      preferences: preferences,
      services: services,
      history: history,
      resume: resume,
      focus: focus,
      scope: scope,
      scopeLabel: scopeLabel,
      client: client,
    ),
  );

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  final _input = TextEditingController();
  final _turns = <ChatMessage>[];

  /// One adapter — and so one HTTP connection — for the whole conversation,
  /// rather than one per message. Every turn goes to the same host, and
  /// building a fresh client each time threw away the connection just before
  /// the next question needed it.
  /// Built in initState rather than lazily: a sheet opened and closed without
  /// a question would otherwise construct its client inside dispose, purely to
  /// close it again.
  late final CloudAIAdapter _adapter;

  /// The sheet's own size, driven when the composer takes focus.
  ///
  /// A chat that opens at a bit over half the screen is a question rather
  /// than a room you moved into, and that is right until someone starts
  /// typing — at which point the keyboard takes the bottom half and the thread
  /// is squeezed into whatever is left. Tapping the composer says the
  /// conversation is the thing now, so the sheet goes up to meet it instead of
  /// waiting to be dragged.
  final _sheet = DraggableScrollableController();

  final _composerFocus = FocusNode();

  /// The scroll controller [DraggableScrollableSheet] handed down, kept so
  /// the thread can be scrolled to the bottom from outside the builder.
  ScrollController? _scroll;

  bool _sending = false;

  /// True from the moment the recording stops until the transcript is back.
  ///
  /// Separate from [_sending] on purpose: the composer is disabled for both,
  /// but only this one is about a question that has not been asked yet, and
  /// the line it puts on screen says so.
  bool _transcribing = false;

  /// The identity of this conversation in [ChatHistory]. Fixed for the life
  /// of the sheet, so every save replaces the same thread rather than filling
  /// the list with one entry per exchange.
  late final String _threadId;

  /// The user's recent notes, formatted once when the sheet opens.
  ///
  /// Not refreshed per message: the conversation is about the notes as they
  /// were when it started, and re-reading the library between turns would
  /// silently change what earlier answers were based on.
  String _notesContext = '';

  /// The focused note's own picture, when there is one and the provider can
  /// look at it. Loaded once with the context and re-sent with every
  /// question — see [NexChatAttachment].
  List<NexChatAttachment> _attachments = const [];

  /// The actions the assistant last asked for, waiting on the user.
  List<AssistantAction> _pending = const [];

  /// How many times this exchange has let the assistant search and think
  /// again. Bounded: a model that keeps searching instead of answering would
  /// otherwise spend the user's quota in a loop nobody asked for.
  int _searchRounds = 0;

  /// What the last confirmed action did, in one line.
  String? _actionResult;

  /// Set when a reply does not arrive, and cleared by the next attempt. Shown
  /// in the thread rather than as a toast: the failure belongs to the message
  /// it answers, and a toast would be gone before it is read.
  String? _failure;

  @override
  void initState() {
    super.initState();
    final resumed = widget.resume;
    _threadId =
        resumed?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    if (resumed != null) _turns.addAll(resumed.messages);
    _adapter = CloudAIAdapter(
      config: widget.preferences.aiProvider,
      outputLanguage: widget.preferences.aiOutputLanguage,
      client: widget.client,
    );
    unawaited(_loadNotesContext());
    _composerFocus.addListener(_growWhenTyping);
  }

  /// Takes the sheet to full height the moment the composer has the cursor.
  ///
  /// Guarded on `isAttached` because focus can arrive before the sheet has
  /// laid out, and on the current size so a sheet already up there is not
  /// re-animated to where it is.
  void _growWhenTyping() {
    if (!_composerFocus.hasFocus || !_sheet.isAttached) return;
    if (_sheet.size > 0.92) return;
    unawaited(
      _sheet.animateTo(1, duration: NexMotion.standard, curve: NexMotion.curve),
    );
  }

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
      final line = _contextLine(
        focused,
        limit: 6000,
        fileText: await _fileText(focused),
      );
      final images = _imagesFor(focused);
      if (mounted) {
        setState(() {
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
      final lines = <String>[
        for (final note in scoped)
          if (_contextLine(note) case final line?) line,
      ];
      if (mounted) setState(() => _notesContext = lines.join('\n'));
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
    final lines = <String>[
      for (final note in notes)
        if (_contextLine(note) case final line?) line,
    ];
    if (!mounted) return;
    setState(() => _notesContext = lines.join('\n'));
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
    return '[${note.id}] ${note.type.wireName}: $clipped';
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
    if (!widget.preferences.aiProvider.provider.readsImages) {
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
    notesContext: _notesContext,
    attachments: _attachments,
    // Acting needs ids to act on. With no notes in context every id the model
    // could produce would be invented, which is the one thing the prompt
    // tells it not to do.
    canAct: _notesContext.isNotEmpty,
  );

  @override
  void dispose() {
    _composerFocus.removeListener(_growWhenTyping);
    _composerFocus.dispose();
    _sheet.dispose();
    _input.dispose();
    _adapter.close();
    super.dispose();
  }

  /// Whether the microphone is worth offering at all.
  ///
  /// The transcript comes from the same provider the chat does, and two of the
  /// four providers cannot hear audio. A mic button that always failed would
  /// be worse than no mic button.
  bool get _canSpeak =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      widget.preferences.aiProvider.provider.hearsAudio;

  /// Record a question instead of typing it.
  ///
  /// The transcript lands in the composer rather than being sent: speech
  /// recognition on a free-tier model gets names and Persian word breaks
  /// wrong often enough that sending unseen would mean arguing with the
  /// assistant about a question nobody asked. One extra tap buys the chance
  /// to fix it.
  ///
  /// The clip itself is temporary and deleted either way — this is a question,
  /// not a note, and it has no business in the media directory that backups
  /// and the library read from.
  Future<void> _speak() async {
    if (_sending || _transcribing) return;
    final recorder = AudioRecorder();
    // The same silence as voice capture had, in the same words — see
    // `captureVoice`. Dictation is the only way to ask the assistant without
    // typing, so a mute button here reads as the assistant being broken.
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      if (!mounted) return;
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).micDenied,
        kind: NexBannerKind.failed,
        haptics: widget.preferences.haptics,
      );
      return;
    }
    final file = File(
      p.join(
        Directory.systemTemp.path,
        'nex-ask-${DateTime.now().millisecondsSinceEpoch}.m4a',
      ),
    );
    await recorder.start(const RecordConfig(), path: file.path);
    if (!mounted) {
      await recorder.stop();
      await recorder.dispose();
      return;
    }
    final keep = await nexShowSheet<bool>(
      context: context,
      dismissible: false,
      builder: (_) => RecordingSheet(recorder: recorder),
    );
    final recorded = await recorder.stop();
    await recorder.dispose();
    if (keep != true || recorded == null) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    if (mounted) setState(() => _transcribing = true);
    String text = '';
    try {
      final transcript = await _adapter.transcribe(
        AudioRef(mediaUri: recorded, bytes: await File(recorded).readAsBytes()),
      );
      text = transcript?.text.trim() ?? '';
    } catch (_) {
      text = '';
    } finally {
      // Deleted whatever happened, including on the throw: a failed request
      // is the case where a stray recording would otherwise sit in temp with
      // nothing left that knows about it.
      if (file.existsSync()) file.deleteSync();
    }
    if (!mounted) return;
    setState(() => _transcribing = false);
    if (text.isEmpty) {
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).chatTranscribeFailed,
        haptics: widget.preferences.haptics,
      );
      return;
    }
    nexBump();
    // Appended, not replaced: someone who typed half a question and then
    // spoke the rest meant both halves.
    final existing = _input.text.trimRight();
    _input.text = existing.isEmpty ? text : '$existing $text';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context);

    setState(() {
      _turns.add(ChatMessage(role: ChatRole.user, content: trimmed));
      _sending = true;
      _failure = null;
      _pending = const [];
      _actionResult = null;
      _searchRounds = 0;
      _input.clear();
    });
    _toBottom();

    String? reply;
    try {
      reply = await _adapter.chat(List.of(_turns), options: _options);
    } catch (_) {
      reply = null;
    }
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (reply == null || reply.isEmpty) {
        // The runtime's own words when the model is what failed. Telling
        // someone who deliberately has no provider to "check the provider in
        // Settings" sends them to the one screen that is already correct.
        final local = _adapter.localFailure;
        _failure = local == null
            ? l10n.chatFailed
            : '${l10n.localModelLoadFailed}\n$local';
        return;
      }
      final actions = parseAssistantActions(reply);
      _pending = [
        for (final action in actions)
          if (!action.isRead) action,
      ];
      // A reply that is only an action block has no prose worth showing —
      // the confirmation card says what it is in the user's own language,
      // and the raw JSON underneath it would be noise. A reply carrying both
      // keeps the words and drops the block.
      final prose = actions.isEmpty ? reply : withoutActionBlock(reply);
      if (prose.isNotEmpty) {
        _turns.add(ChatMessage(role: ChatRole.assistant, content: prose));
      }
      _lookups = [
        for (final action in actions)
          if (action.isRead) action,
      ];
    });
    _persist();
    _toBottom();
    if (_lookups.isNotEmpty) await _runLookups();
  }

  /// Searches the assistant asked for, and the answer it gets back.
  List<AssistantAction> _lookups = const [];

  /// Runs the assistant's own searches and hands it the results.
  ///
  /// This is what lets it know about a note that is not in the twenty it was
  /// given: it asks, the app looks, and the exchange continues with the
  /// findings in front of it. The results go in as a user turn because that
  /// is the only role every one of the three wire formats agrees on for
  /// something that is neither the system prompt nor the model's own words.
  Future<void> _runLookups() async {
    final queries = _lookups;
    _lookups = const [];
    if (_searchRounds >= 2 || queries.isEmpty) return;
    _searchRounds++;

    final findings = StringBuffer();
    for (final lookup in queries) {
      final query = lookup.text ?? '';
      List<Note> found;
      try {
        final parsed = parseSearchQuery(query);
        found = await widget.services.search(
          SearchFilters(query: parsed.text, types: parsed.types),
        );
      } catch (_) {
        found = const [];
      }
      findings.writeln('Results for "$query":');
      if (found.isEmpty) {
        findings.writeln('(nothing found)');
      } else {
        for (final note in found.take(10)) {
          final line = _contextLine(note);
          if (line != null) findings.writeln(line);
        }
      }
    }
    if (!mounted) return;

    setState(() {
      _sending = true;
      _turns.add(
        ChatMessage(role: ChatRole.user, content: findings.toString().trim()),
      );
    });
    String? reply;
    try {
      reply = await _adapter.chat(List.of(_turns), options: _options);
    } catch (_) {
      reply = null;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (reply == null || reply.isEmpty) return;
      final actions = parseAssistantActions(reply);
      _pending = [
        for (final action in actions)
          if (!action.isRead) action,
      ];
      final prose = actions.isEmpty ? reply : withoutActionBlock(reply);
      if (prose.isNotEmpty) {
        _turns.add(ChatMessage(role: ChatRole.assistant, content: prose));
      }
    });
    _persist();
    _toBottom();
  }

  /// Writes the conversation after every exchange. Fire-and-forget: a thread
  /// that fails to save is not worth interrupting the conversation over.
  void _persist() => unawaited(widget.history.save(_threadId, _turns));

  /// Carries out what the user just confirmed.
  ///
  /// Everything here goes through [NexServices], the same path the UI itself
  /// uses — so an assistant edit is indistinguishable from a hand edit, syncs
  /// like one, and lands in Recently Deleted like one.
  Future<void> _runPending() async {
    final actions = _pending;
    if (actions.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _pending = const [];
      _sending = true;
    });
    var ok = true;
    try {
      // Every note this set claims to act on, checked before any of it runs.
      //
      // Without this the confirmation was a guess. `ok` only went false when
      // something *threw*, and none of these throw on a note that is not
      // there: a delete is an UPDATE matched by id, and matching no rows is
      // a successful statement that changed nothing. So an id the model
      // invented, or one left over from a note deleted earlier in the same
      // conversation, produced "Done" over a library that had not moved —
      // and the reader's next act is to believe it.
      //
      // Checked first rather than counted afterwards, for the reason the
      // loop below already gives: a half-applied set is worse than none of
      // it. Finding the bad id on the third of three actions is finding it
      // too late.
      if (!await _targetsExist(actions)) {
        throw StateError('an action names a note that is not there');
      }
      // In order, and stopping at the first failure. A half-applied set is
      // worse than none of it: the user confirmed one intention, and leaving
      // two of its three changes in place is a state nobody asked for and
      // nobody can see.
      for (final action in actions) {
        switch (action.kind) {
          case AssistantActionKind.create:
            if (action.items.isNotEmpty) {
              await widget.services.captureChecklist([
                for (final line in action.items)
                  ChecklistItem(text: line, done: false),
              ]);
            } else {
              await widget.services.captureText(action.text!);
            }
          case AssistantActionKind.edit:
            await widget.services.updateNote(action.noteId!, action.text!);
          case AssistantActionKind.delete:
            await widget.services.deleteNote(action.noteId!);
          case AssistantActionKind.tag:
            await _applyTags(action);
          case AssistantActionKind.merge:
            await _merge(action);
          case AssistantActionKind.toChecklist:
            await _toChecklist(action);
          case AssistantActionKind.check:
            await widget.services.toggleChecklistItem(
              action.noteId!,
              action.index!,
            );
          case AssistantActionKind.setting:
            await _applySetting(action);
          case AssistantActionKind.remind:
            // Both halves at once, the way the reminder picker does it —
            // `setDueAt` schedules or cancels the alarm behind the date, so
            // nothing here has to know that a reminder is two things.
            await widget.services.setDueAt(
              action.noteId!,
              action.at,
              repeat: action.repeat,
            );
          case AssistantActionKind.pin:
            if (action.flag ?? true) {
              // Five pins is the library's limit, and `pinNote` answers
              // false rather than throwing when it is reached. Left
              // unchecked that is the same bug the id check above exists
              // for: a card that says "Done" over a timeline that has not
              // moved, and a reader whose next act is to believe it.
              if (!await widget.services.pinNote(action.noteId!)) {
                throw StateError('the library already has five pinned notes');
              }
            } else {
              await widget.services.unpinNote(action.noteId!);
            }
          case AssistantActionKind.title:
            await widget.services.setTitle(action.noteId!, action.text);
          case AssistantActionKind.restore:
            await widget.services.undelete(action.noteId!);
          case AssistantActionKind.renameTag:
            await _renameTag(action);
          case AssistantActionKind.tagColor:
            await _setTagColor(action);
          case AssistantActionKind.commitment:
            await _saveCommitment(action);
          case AssistantActionKind.commitmentMet:
            // Rolls it forward rather than finishing it — the difference
            // between a commitment and a reminder, in one call. Existence was
            // settled before any of this set ran.
            final met = await _commitmentByName(action.commitmentName);
            if (met != null) {
              await widget.services.markCommitmentMet(met.id);
            }
          case AssistantActionKind.commitmentDelete:
            final gone = await _commitmentByName(action.commitmentName);
            if (gone != null) {
              await widget.services.deleteCommitment(gone.id);
            }
          case AssistantActionKind.search:
            break;
        }
      }
    } catch (_) {
      ok = false;
    }
    await widget.services.refreshTimeline();
    if (!mounted) return;
    setState(() {
      _sending = false;
      _actionResult = ok
          ? l10n.assistantActionDone
          : l10n.assistantActionFailed;
    });
    // The library moved, so the context the rest of this conversation is
    // answering from is now stale.
    unawaited(_loadNotesContext());
    _toBottom();
  }

  /// Whether every note the set names is really there.
  ///
  /// Both id fields count: `noteId` for the single-target actions and
  /// `noteIds` for a merge, which folds several notes together and is the one
  /// action that can be half-right — two real ids and one invented.
  ///
  /// A create carries no id and a search is never in this list, so an empty
  /// set of note targets is a legitimate answer of "nothing to check". The
  /// two tag-wide actions name a tag rather than a note and are checked the
  /// same way lower down, by name: a tag the model invented would otherwise
  /// be a rename that changed nothing and reported "Done".
  ///
  /// A restore is checked against the trash instead, because its target is
  /// by definition a note `getById` will not return: it is the one action
  /// whose id being absent from the library is the *reason* for it. Against
  /// the trash's own page of most-recent deletions, which is what the
  /// Recently Deleted screen shows and therefore the only notes the model
  /// could have been told about in the first place.
  Future<bool> _targetsExist(List<AssistantAction> actions) async {
    final targets = <String>{
      for (final action in actions)
        if (action.kind != AssistantActionKind.restore) ...[
          if (action.noteId case final id?) id,
          ...action.noteIds,
        ],
    };
    for (final id in targets) {
      if (await widget.services.getById(id) == null) return false;
    }
    final restoring = <String>{
      for (final action in actions)
        if (action.kind == AssistantActionKind.restore)
          if (action.noteId case final id?) id,
    };
    // Tags are named rather than identified, so "there is a tag called
    // this" is the same question `getById` answers for a note — and a tag
    // the model invented would otherwise be a rename that changed nothing
    // and said "Done".
    final tagNames = <String>{
      for (final action in actions)
        if (action.tagName case final name?) name.toLowerCase(),
    };
    if (tagNames.isNotEmpty) {
      final known = {
        for (final tag in await widget.services.listTags())
          tag.name.toLowerCase(),
      };
      if (!tagNames.every(known.contains)) return false;
    }
    // The two commitment actions that act on an existing one. A `commitment`
    // is left out on purpose: it creates as readily as it edits, so a name
    // that is not there yet is the ordinary case rather than a mistake.
    final named = <String>{
      for (final action in actions)
        if (action.kind == AssistantActionKind.commitmentMet ||
            action.kind == AssistantActionKind.commitmentDelete)
          if (action.commitmentName case final name?) name.toLowerCase(),
    };
    if (named.isNotEmpty) {
      final known = {
        for (final one in await widget.services.commitments())
          one.title.toLowerCase(),
      };
      if (!named.every(known.contains)) return false;
    }
    if (restoring.isEmpty) return true;
    final deleted = {
      for (final note in await widget.services.deletedNotes()) note.id,
    };
    return restoring.every(deleted.contains);
  }

  /// Renames a tag everywhere it is worn, found by the name the model used.
  ///
  /// By name because that is all the model ever sees — the notes it is given
  /// carry tag names, never tag ids — and case-insensitively because "Work"
  /// and "work" are the same tag to everybody except a string comparison.
  Future<void> _renameTag(AssistantAction action) async {
    final tag = await _tagNamed(action.tagName);
    if (tag == null || action.text == null) return;
    await widget.services.renameTag(tag.id, action.text!);
  }

  Future<void> _setTagColor(AssistantAction action) async {
    final tag = await _tagNamed(action.tagName);
    if (tag == null) return;
    // Null is `default` — the colour cleared, which is a thing the picker
    // can do and so is a thing that can be asked for.
    await widget.services.setTagColor(tagId: tag.id, color: action.text);
  }

  /// Creates a standing obligation, or edits the one already under that name.
  ///
  /// Same name means same thing, deliberately: a model asked twice about the
  /// rent should not leave two rents behind, and "change the insurance to
  /// every two years" is the same sentence as setting it up.
  Future<void> _saveCommitment(AssistantAction action) async {
    final name = action.commitmentName!;
    final cadence = action.cadence!;
    final every = action.every ?? 1;
    final now = DateTime.now();
    final existing = await _commitmentByName(name);
    if (existing != null) {
      await widget.services.saveCommitment(
        existing.copyWith(
          title: name,
          cadence: cadence,
          every: every,
          // No date given means leave it where it is. Editing the cadence
          // should not move the next occurrence the user already agreed to.
          dueAt: action.at,
          updatedAt: now,
        ),
      );
      return;
    }
    await widget.services.saveCommitment(
      NexCommitment(
        id: newUuidV7(),
        title: name,
        cadence: cadence,
        every: every,
        // Tomorrow morning when the model did not say. Not "now": a
        // commitment due the instant it is created is overdue before the
        // confirmation card has closed.
        dueAt:
            action.at ??
            DateTime(now.year, now.month, now.day, 9)
                .add(const Duration(days: 1)),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// The commitment stored under [name], case-insensitively.
  Future<NexCommitment?> _commitmentByName(String? name) async {
    if (name == null) return null;
    final lowered = name.toLowerCase();
    for (final one in await widget.services.commitments()) {
      if (one.title.toLowerCase() == lowered) return one;
    }
    return null;
  }

  Future<Tag?> _tagNamed(String? name) async {
    if (name == null) return null;
    final lowered = name.toLowerCase();
    final tags = await widget.services.listTags();
    for (final tag in tags) {
      if (tag.name.toLowerCase() == lowered) return tag;
    }
    return null;
  }

  /// Opens the assistant's own settings over the chat.
  ///
  /// Over rather than instead: unlike history, nothing here replaces the
  /// conversation, so the thread is still underneath and still there when the
  /// panel closes. The sheet rebuilds on the way back because every one of
  /// these settings changes what the next answer will be.
  Future<void> _openSettings() async {
    await AssistantSettingsPanel.show(context, preferences: widget.preferences);
    if (mounted) setState(() {});
  }

  /// Swaps this sheet for a saved conversation, or a fresh one.
  ///
  /// Replaces rather than stacks: two assistant sheets on top of each other
  /// is two conversations both claiming to be the one on screen, and the one
  /// underneath would keep saving itself over the one above.
  Future<void> _openHistory() async {
    final chosen = await ChatHistorySheet.show(
      context,
      history: widget.history,
    );
    if (chosen == null || !mounted) return;
    Navigator.pop(context);
    await AiChatSheet.show(
      context,
      preferences: widget.preferences,
      services: widget.services,
      history: widget.history,
      resume: chosen.thread,
    );
  }

  /// Folds several notes into one and removes the originals.
  ///
  /// The merged text is the model's when it wrote one — that is the whole
  /// value of asking it to merge rather than concatenating — and a plain join
  /// when it did not, so the action never silently loses what was in the
  /// notes. The originals go to Recently Deleted rather than being erased:
  /// the one action here that destroys something the user cannot retype
  /// deserves the same undo every other delete has.
  Future<void> _merge(AssistantAction action) async {
    final notes = <Note>[];
    for (final id in action.noteIds) {
      final note = await widget.services.getById(id);
      if (note != null) notes.add(note);
    }
    if (notes.length < 2) return;
    final text =
        action.text ??
        notes
            .map((note) => (note.content ?? note.displayText ?? '').trim())
            .where((part) => part.isNotEmpty)
            .join('\n\n');
    if (text.trim().isEmpty) return;
    await widget.services.captureText(text);
    for (final note in notes) {
      await widget.services.deleteNote(note.id);
    }
  }

  /// Rewrites a note as a checklist, one item per line.
  ///
  /// A new note and a deleted one rather than a type change in place: a
  /// note's type is part of its identity in the timeline, in sync and in
  /// export, and turning one into another is exactly the kind of edit that
  /// should be undoable by pulling the original back out of the trash.
  Future<void> _toChecklist(AssistantAction action) async {
    final note = await widget.services.getById(action.noteId!);
    if (note == null) return;
    final source = action.text ?? note.content ?? note.displayText ?? '';
    final items = [
      for (final line in source.split('\n'))
        if (line.trim().isNotEmpty)
          ChecklistItem(
            text: line.trim().replaceFirst(RegExp(r'^[-*]\s*'), ''),
            done: false,
          ),
    ];
    if (items.isEmpty) return;
    await widget.services.captureChecklist(items);
    await widget.services.deleteNote(note.id);
  }

  /// Applies one setting from the short list in [assistantSettableKeys].
  ///
  /// Every value is checked here as well as at parse time. The parser
  /// guarantees the *key* is one this app offered; this guarantees the value
  /// is one that key accepts, so a model writing `{"key":"theme","value":
  /// "blue"}` changes nothing rather than storing a theme that does not
  /// exist.
  Future<void> _applySetting(AssistantAction action) async {
    final value = action.settingValue;
    switch (action.settingKey) {
      case 'theme':
        final mode = switch (value) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => null,
        };
        if (mode != null) await widget.preferences.setThemeMode(mode);
      case 'language':
        if (value == 'en' || value == 'fa' || value == 'system') {
          // 'system' verbatim, never an empty string: the getter reads
          // anything that is not null or 'system' as a language code, so an
          // empty value came back as Locale('') — a locale that matches no
          // translation and is not the system default either.
          await widget.preferences.setLocale(value!);
        }
      case 'ai_language':
        final language = switch (value) {
          'en' => AiOutputLanguage.english,
          'fa' => AiOutputLanguage.persian,
          'auto' => AiOutputLanguage.auto,
          _ => null,
        };
        if (language != null) {
          await widget.preferences.setAiOutputLanguage(language);
        }
      // The four sizes the settings screen offers and no others. A free
      // number would let a model store 4.0 and hand back a phone whose text
      // does not fit on it — and a size nobody can reach by hand is not a
      // size this app has.
      case 'text_size':
        final scale = switch (value) {
          'small' => 0.9,
          'default' || 'normal' || 'medium' => 1.0,
          'large' => 1.15,
          'larger' || 'largest' => 1.3,
          _ => null,
        };
        if (scale != null) await widget.preferences.setUiScale(scale);
      case 'background':
        for (final pattern in NexBackgroundPattern.values) {
          if (pattern.wireName != value) continue;
          await widget.preferences.setBackgroundPattern(pattern);
          break;
        }
      // Already normalised to `#RRGGBB` by the parser, or null for the
      // shipped accent.
      case 'accent':
        if (value == 'default') {
          await widget.preferences.setAccentSeed(null);
        } else if (value != null && _hexSeed.hasMatch(value)) {
          await widget.preferences.setAccentSeed(value.toUpperCase());
        }
      case 'comfort_mode':
        if (_onOff(value) case final on?) {
          await widget.preferences.setComfortMode(on);
        }
      case 'haptics':
        if (_onOff(value) case final on?) {
          await widget.preferences.setHaptics(on);
        }
      case 'show_greeting':
        if (_onOff(value) case final on?) {
          await widget.preferences.setShowGreeting(on);
        }
      case 'show_digest':
        if (_onOff(value) case final on?) {
          await widget.preferences.setShowDaySummary(on);
        }
      case 'show_search':
        if (_onOff(value) case final on?) {
          await widget.preferences.setShowSearchField(on);
        }
      case 'show_tags':
        if (_onOff(value) case final on?) {
          await widget.preferences.setShowTagRow(on);
        }
      case 'daily_nudge':
        if (_onOff(value) case final on?) {
          await widget.preferences.setDailyNudge(on);
        }
      case 'daily_nudge_time':
        if (_minutesOfDay(value) case final minutes?) {
          await widget.preferences.setDailyNudgeMinutes(minutes);
        }
    }
  }

  /// `#RRGGBB`. Checked here as well as at parse time, for the reason the
  /// method's own comment gives: the parser guarantees the key, this
  /// guarantees the value.
  static final _hexSeed = RegExp(r'^#[0-9a-fA-F]{6}$');

  /// The several words a model reaches for when it means yes or no.
  static bool? _onOff(String? value) => switch (value) {
    'on' || 'true' || 'yes' || 'enabled' => true,
    'off' || 'false' || 'no' || 'disabled' => false,
    _ => null,
  };

  /// `HH:MM` as minutes past midnight, or null when it is not a time.
  static int? _minutesOfDay(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  Future<void> _applyTags(AssistantAction action) async {
    final existing = await widget.services.listTags();
    for (final name in action.removeTags) {
      final match = existing.where(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
      );
      if (match.isEmpty) continue;
      await widget.services.removeTag(
        noteId: action.noteId!,
        tagId: match.first.id,
      );
    }
    for (final name in action.addTags) {
      await widget.services.addTag(noteId: action.noteId!, name: name);
    }
  }

  /// After the frame that added the message, not before it — the list has to
  /// have grown before there is anywhere new to scroll to.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scroll = _scroll;
      if (scroll == null || !scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: NexMotion.standard,
        curve: NexMotion.curve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return NexAmbientEdgeGlow(
      // The hold that opens this sheet lights the whole edge of the screen
      // and then lets it go. A thread of the same spectrum stays for as long
      // as the assistant is up, so the mode is visible from anywhere on the
      // display rather than only from the sheet you happen to be looking at.
      colors: nexAssistantSpectrum,
      child: DraggableScrollableSheet(
        controller: _sheet,
        // Starts as a question, not a room you moved into.
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 1,
        // Snaps to the two ends so a half-dragged sheet settles somewhere
        // deliberate instead of wherever the finger let go.
        snap: true,
        snapSizes: const [0.55],
        expand: false,
        builder: (context, sheetScroll) {
          _scroll = sheetScroll;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(NexRadius.xl),
              ),
            ),
            child: Column(
              children: [
                // The drag handle doubles as the affordance for "this gets
                // bigger" — it is the only thing suggesting the sheet moves.
                Padding(
                  padding: const EdgeInsets.only(top: NexSpacing.sm),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(NexRadius.xs),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NexSpacing.md,
                    NexSpacing.sm,
                    NexSpacing.sm,
                    0,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                      // Which note this is about, when it is about one. The
                      // sheet already answers only from that note and can act
                      // on it, and none of that was visible: the same blank
                      // chat opened whether it had been reached from the
                      // capture button or from one note's own action row.
                      if (widget.scopeLabel case final group?) ...[
                        const SizedBox(width: NexSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.chatAboutGroup(group, widget.scope?.length ?? 0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textDirection: nexDirectionOf(group),
                          ),
                        ),
                      ] else if (widget.focus case final note?) ...[
                        const SizedBox(width: NexSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.chatAboutNote(_focusLabel(note)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textDirection: nexDirectionOf(_focusLabel(note)),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      IconButton(
                        tooltip: l10n.chatHistory,
                        onPressed: _openHistory,
                        icon: const Icon(Icons.history),
                      ),
                      // The same settings the Settings row opens, on the
                      // surface where they are actually being judged: the
                      // answer that was too long is on screen while the length
                      // control is being changed.
                      IconButton(
                        tooltip: l10n.assistant,
                        onPressed: _openSettings,
                        icon: const Icon(Icons.tune),
                      ),
                      IconButton(
                        tooltip: l10n.cancel,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _turns.isEmpty && _failure == null
                      ? _Suggestions(
                          // The sheet's own scrollable has to be the one
                          // DraggableScrollableSheet handed down, or dragging the
                          // body does not resize the sheet.
                          controller: sheetScroll,
                          onPick: (text) => unawaited(_send(text)),
                        )
                      : _Thread(
                          // Same controller as the suggestions above: the thread
                          // has to be the sheet's own scrollable too, or dragging
                          // it up stops resizing the sheet the moment the first
                          // message lands.
                          controller: sheetScroll,
                          turns: _turns,
                          sending: _sending,
                          failure: _failure,
                        ),
                ),
                if (_pending.isNotEmpty)
                  _ActionCard(
                    actions: _pending,
                    onApply: () => unawaited(_runPending()),
                    onDismiss: () => setState(() => _pending = const []),
                  ),
                if (_actionResult case final result?)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NexSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: NexSpacing.sm),
                        Text(result, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                _Composer(
                  controller: _input,
                  focusNode: _composerFocus,
                  sending: _sending,
                  transcribing: _transcribing,
                  onSend: () => unawaited(_send(_input.text)),
                  onSpeak: _canSpeak ? () => unawaited(_speak()) : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

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
  });

  final ScrollController controller;
  final List<ChatMessage> turns;
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
        final mine = turn.role == ChatRole.user;
        return Align(
          alignment: mine
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            margin: const EdgeInsets.only(bottom: NexSpacing.sm),
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
                  if (!mine && nexLooksLikeMarkdown(turn.content)) {
                    return NexMarkdown(
                      turn.content,
                      style: style,
                      // Selection belongs to the area around the bubble, not
                      // to the text inside it — which is what lets a link in a
                      // reply still answer a tap.
                      selectable: false,
                    );
                  }
                  // A [Directionality] as well as the argument below. The
                  // argument places the glyphs; the selection handles are
                  // placed by the ambient direction, which is the interface
                  // language's — so a Persian reply in an English interface
                  // came up with its two handles the wrong way round, and
                  // dragging one widened the selection from the wrong end.
                  return NexTextDirection(
                    text: turn.content,
                    child: Text(
                      turn.content,
                      style: style,
                      // Either side may be in either language — the assistant
                      // answers in whatever the output-language setting asks
                      // for.
                      //
                      // One direction for the whole turn, not one per line the
                      // way [NexBodyText] does it: that lays its lines out in
                      // a stretched column, and a bubble is sized to its
                      // content — every reply, "yes" included, would be drawn
                      // 78% of the screen wide.
                      textDirection: nexDirectionOf(turn.content),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

}

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
    required this.actions,
    required this.onApply,
    required this.onDismiss,
  });

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
        AssistantActionKind.remind => action.at == null
            ? l10n.assistantConfirmRemindClear
            : l10n.assistantConfirmRemind,
        AssistantActionKind.pin => (action.flag ?? true)
            ? l10n.assistantConfirmPin
            : l10n.assistantConfirmUnpin,
        AssistantActionKind.title => action.text == null
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
  static String _detail(AssistantAction action) => switch (action.kind) {
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
    AssistantActionKind.remind => action.at == null
        ? ''
        : [
            _whenLabel(action.at!),
            if (action.repeat != NoteRepeat.once) '· ${action.repeat.wireName}',
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
  static String _whenLabel(DateTime when) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${when.year}-${two(when.month)}-${two(when.day)} '
        '${two(when.hour)}:${two(when.minute)}';
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

/// What the history button opens: every saved conversation, newest first.
///
/// Returns the thread to reopen, wrapped — a bare `ChatThread?` cannot tell
/// "the user picked nothing" from "the user asked for a new conversation",
/// and those do opposite things.
@immutable
class ChatHistoryChoice {
  const ChatHistoryChoice(this.thread);

  /// Null means: start a fresh conversation.
  final ChatThread? thread;
}

class ChatHistorySheet extends StatefulWidget {
  const ChatHistorySheet({super.key, required this.history});

  final ChatHistory history;

  static Future<ChatHistoryChoice?> show(
    BuildContext context, {
    required ChatHistory history,
  }) => nexShowSheet<ChatHistoryChoice>(
    context: context,
    builder: (_) => ChatHistorySheet(history: history),
  );

  @override
  State<ChatHistorySheet> createState() => _ChatHistorySheetState();
}

class _ChatHistorySheetState extends State<ChatHistorySheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final threads = widget.history.threads;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: nexBottomInset(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: Text(l10n.chatNewConversation),
              onTap: () =>
                  Navigator.pop(context, const ChatHistoryChoice(null)),
            ),
            const Divider(height: 1),
            if (threads.isEmpty)
              Padding(
                padding: const EdgeInsets.all(NexSpacing.xl),
                child: Text(
                  l10n.chatHistoryEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                // The list fills the panel, so a downward drag over it never
                // reached the sheet's own drag-to-dismiss: a scroll view wins
                // that gesture outright whether or not it has anywhere left
                // to go. This is the same answer the note detail sheet and
                // Settings use.
                child: NexDismissOnOverscroll(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: threads.length,
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      return ListTile(
                        title: Text(
                          thread.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: nexDirectionOf(thread.title),
                        ),
                        // The same words the timeline cards use for "2h", so
                        // the two places that show an age agree.
                        subtitle: Text(
                          nexCardStrings(
                            context,
                          ).relativeTime(nexRelativeTimeOf(thread.updatedAt)),
                        ),
                        trailing: IconButton(
                          tooltip: l10n.delete,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () async {
                            await widget.history.remove(thread.id);
                            if (mounted) setState(() {});
                          },
                        ),
                        onTap: () =>
                            Navigator.pop(context, ChatHistoryChoice(thread)),
                      );
                    },
                  ),
                ),
              ),
            if (threads.isNotEmpty) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.delete_sweep_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  l10n.chatClearHistory,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () async {
                  await widget.history.clear();
                  if (mounted) setState(() {});
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The assistant's own settings, opened from inside the chat.
///
/// Same controls as the Settings row, on the surface where they are actually
/// being judged — the answer that was too long is still on screen behind this
/// while the length is being changed. It sits *over* the conversation rather
/// than replacing it, which is the difference between this and history.
class AssistantSettingsPanel extends StatelessWidget {
  const AssistantSettingsPanel({super.key, required this.preferences});

  final NexPreferences preferences;

  static Future<void> show(
    BuildContext context, {
    required NexPreferences preferences,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AssistantSettingsPanel(preferences: preferences),
  );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      builder: (context, scroll) => NexDismissOnOverscroll(
        child: AssistantSettingsBody(
          preferences: preferences,
          // The sheet's own scrollable, or dragging the settings would not
          // resize the panel holding them.
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.lg + nexBottomInset(context),
          ),
        ),
      ),
    );
  }
}
