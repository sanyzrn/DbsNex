import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../documents/docx_markdown.dart';
import '../l10n/app_localizations.dart';
import '../screens/note_detail_sheet.dart';
import 'dismiss_on_overscroll.dart';
import 'assistant_settings.dart';
import 'package:nex_ai/cloud.dart';
import '../platform/assistant_citations.dart';
import '../platform/chat_history.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/theme_presets.dart';
import 'card_strings.dart';
import 'nex_banner.dart';
import 'nex_dialog.dart';
import 'nex_text_field.dart';
import 'keyboard_dismisser.dart';
import 'recording_sheet.dart';

part 'ai_chat/chat_thread.dart';
part 'ai_chat/chat_composer.dart';
part 'ai_chat/chat_panels.dart';
part 'ai_chat/chat_context.dart';
part 'ai_chat/chat_sending.dart';
part 'ai_chat/chat_actions.dart';

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
    Rect? emergeFrom,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // A touch slower and softer than a plain sheet, so it rises together
    // with the drop that pours out of the capture button ahead of it.
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 460),
      reverseDuration: Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    ),
    // Held from the capture button, the sheet grows out of it instead of
    // sliding up. Opened from anywhere else it is an ordinary sheet.
    builder: (context) => NexEmergeFrom(
      origin: emergeFrom,
      color:
          Theme.of(context).floatingActionButtonTheme.backgroundColor ??
          Theme.of(context).colorScheme.primary,
      radius: NexRadius.xl,
      child: AiChatSheet(
        preferences: preferences,
        services: services,
        history: history,
        resume: resume,
        focus: focus,
        scope: scope,
        scopeLabel: scopeLabel,
        client: client,
      ),
    ),
  );

  /// The share of the screen the sheet opens at. The launch animation aims
  /// its drop at this edge.
  static const initialSize = 0.55;

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

  /// Every note this conversation has shown the assistant or that an answer
  /// cited, by id — what turns a cited id back into a chip with a name.
  final Map<String, Note> _notes = {};

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
  String? _retryText;

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
    if (resumed != null) unawaited(_resolveCitations());
    _input.text =
        widget.preferences.editorDrafts?.read(_composerDraftKey)?['text']
            as String? ??
        '';
    _input.addListener(_saveComposerDraft);
    _composerFocus.addListener(_growWhenTyping);
  }

  String get _composerDraftKey =>
      'chat-${widget.resume?.id ?? widget.focus?.id ?? 'new'}';
  void _saveComposerDraft() {
    if (_input.text.isEmpty) {
      widget.preferences.editorDrafts?.clear(_composerDraftKey);
    } else {
      widget.preferences.editorDrafts?.write(_composerDraftKey, {
        'text': _input.text,
      });
    }
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

  /// The notes that best match the latest question, as context lines.
  ///
  /// Replaced on every question rather than accumulated: it answers "what in
  /// the library is about this?", and the answer to the last question is not
  /// the answer to this one.
  String _retrieved = '';

  /// Every note put in front of the model in this conversation, for the
  /// record of what left the device (W3.2).
  final Set<String> _given = {};

  /// [setState], for the extensions in `ai_chat/` that carry this sheet's
  /// behaviour by topic (W4.2): an extension is not a subclass, so it cannot
  /// call the protected method itself.
  void _rebuild(VoidCallback change) => setState(change);

  @override
  void dispose() {
    _composerFocus.removeListener(_growWhenTyping);
    _composerFocus.dispose();
    _sheet.dispose();
    _input.removeListener(_saveComposerDraft);
    _input.dispose();
    _adapter.close();
    super.dispose();
  }

  /// How many matching notes a question brings into the context.
  static const _retrievedCount = 8;

  /// Searches the assistant asked for, and the answer it gets back.
  List<AssistantAction> _lookups = const [];

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // No coloured thread along the screen's edge while the assistant is up:
    // taken out at the owner's request, with nothing else about the sheet
    // changed.
    return DraggableScrollableSheet(
      controller: _sheet,
      // Starts as a question, not a room you moved into.
      initialChildSize: AiChatSheet.initialSize,
      minChildSize: 0.35,
      maxChildSize: 1,
      // Snaps to the two ends so a half-dragged sheet settles somewhere
      // deliberate instead of wherever the finger let go.
      snap: true,
      snapSizes: const [AiChatSheet.initialSize],
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
                        notes: _notes,
                        onOpenNote: _openCited,
                      ),
              ),
              if (_failure != null && _retryText != null && !_sending)
                TextButton.icon(
                  onPressed: () => unawaited(_send(_retryText!, retry: true)),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retry),
                ),
              if (_pending.isNotEmpty)
                _ActionCard(
                  solar: widget.preferences.solarCalendar,
                  persian: l10n.localeName == 'fa',
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
    );
  }
}
