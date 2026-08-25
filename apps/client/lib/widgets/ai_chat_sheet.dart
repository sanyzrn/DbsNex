import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../l10n/app_localizations.dart';
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
  }

  /// Reads the recent notes the assistant is allowed to see.
  ///
  /// Bounded by the user's own setting, and each note reduced to one line
  /// with its id in front — the id is what makes "delete that one" possible
  /// to act on without the model guessing which note was meant.
  Future<void> _loadNotesContext() async {
    final focused = widget.focus;
    if (focused != null) {
      final line = _contextLine(focused);
      if (line != null && mounted) setState(() => _notesContext = line);
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
  String? _contextLine(Note note) {
    final text =
        [
              note.title,
              note.content,
              note.transcriptText,
              note.ocrText,
              note.linkExcerpt,
            ]
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .join(' — ')
            .replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return null;
    final clipped = text.length > 400 ? '${text.substring(0, 400)}…' : text;
    return '[${note.id}] ${note.type.wireName}: $clipped';
  }

  AiChatOptions get _options => AiChatOptions(
    creativity: widget.preferences.aiCreativity,
    length: widget.preferences.aiAnswerLength,
    notesOnly: widget.preferences.aiNotesOnly,
    instruction: widget.preferences.aiInstruction,
    notesContext: _notesContext,
    // Acting needs ids to act on. With no notes in context every id the model
    // could produce would be invented, which is the one thing the prompt
    // tells it not to do.
    canAct: _notesContext.isNotEmpty,
  );

  @override
  void dispose() {
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
    if (!await recorder.hasPermission()) return recorder.dispose();
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
      // In order, and stopping at the first failure. A half-applied set is
      // worse than none of it: the user confirmed one intention, and leaving
      // two of its three changes in place is a state nobody asked for and
      // nobody can see.
      for (final action in actions) {
        switch (action.kind) {
          case AssistantActionKind.create:
            await widget.services.captureText(action.text!);
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
    }
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
    return DraggableScrollableSheet(
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
                    if (widget.focus case final note?) ...[
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
                sending: _sending,
                transcribing: _transcribing,
                onSend: () => unawaited(_send(_input.text)),
                onSpeak: _canSpeak ? () => unawaited(_speak()) : null,
              ),
            ],
          ),
        );
      },
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
    final prompts = [
      (Icons.summarize_outlined, l10n.chatPromptSummarise),
      (Icons.checklist_outlined, l10n.chatPromptPlan),
      (Icons.lightbulb_outline, l10n.chatPromptIdeas),
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
                        child: Icon(icon, size: 20),
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
          // Long-press to copy, rather than making the text selectable.
          // Selection inside a scrolling thread fights the scroll gesture and
          // hands someone a partial paste; what people actually want from a
          // chat message is the whole of it.
          child: GestureDetector(
            onLongPress: () => unawaited(_copy(context, turn.content)),
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
                      // Long-press to copy belongs to the whole bubble; a
                      // selectable child would take the gesture first.
                      selectable: false,
                    );
                  }
                  return Text(
                    turn.content,
                    style: style,
                    // Either side may be in either language — the assistant
                    // answers in whatever the output-language setting asks for.
                    textDirection: nexDirectionOf(turn.content),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    final l10n = AppLocalizations.of(context);
    final host = NexBannerHost.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    nexBump();
    host?.show(message: l10n.copied);
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.transcribing,
    required this.onSend,
    required this.onSpeak,
  });

  final TextEditingController controller;
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
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextField(
                controller: controller,
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
                textDirection: nexDirectionOf(value.text),
                textAlign: TextAlign.start,
                // Same reason as the capture field: the default highlight runs
                // to the end of the line on right-to-left text.
                selectionWidthStyle: BoxWidthStyle.tight,
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
    AssistantActionKind.delete ||
    AssistantActionKind.check ||
    AssistantActionKind.search => '',
  };

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
  }) => showModalBottomSheet<ChatHistoryChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
