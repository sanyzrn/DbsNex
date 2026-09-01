import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../documents/docx_markdown.dart';
import '../l10n/app_localizations.dart';
import '../widgets/dismiss_on_overscroll.dart';
import '../widgets/ai_chat_sheet.dart';
import '../platform/ai_provider.dart';
import '../platform/file_opener.dart';
import '../platform/sharing.dart';
import '../widgets/nex_dialog.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/reminders.dart';
import '../widgets/nex_banner.dart';
import '../widgets/reminder_picker.dart';
import '../widgets/tag_picker.dart';
import '../widgets/text_format_menu.dart';
import '../widgets/translate_sheet.dart';

/// What the sheet reports back when it closes.
///
/// The timeline already switched on this to offer undo after a delete, but the
/// type was never declared and the sheet popped without a value, so the undo
/// path was unreachable.
enum DetailResult { deleted }

class NoteDetailSheet extends StatefulWidget {
  const NoteDetailSheet({
    super.key,
    required this.services,
    required this.noteId,
    this.preferences,
    this.focusAddTag = false,
  });

  final NexServices services;
  final String noteId;

  /// Optional, and only for the Ask action.
  ///
  /// Nullable rather than required because this sheet is opened from several
  /// places and none of the rest of it needs preferences — an argument added
  /// to every call site for one conditional button would be worse than a
  /// button that is simply absent where nobody wired it up.
  final NexPreferences? preferences;
  final bool focusAddTag;

  @override
  State<NoteDetailSheet> createState() => _NoteDetailSheetState();
}

class _NoteDetailSheetState extends State<NoteDetailSheet> {
  Note? _note;
  List<TagSuggestion> _suggestions = const [];
  List<SemanticHit> _related = const [];

  int _pinnedNoteCount = 0;

  /// Whether the first read has come back, whatever it found.
  ///
  /// Separate from `_note != null`, because the interesting case is exactly
  /// the one where both are false: nothing loaded *yet* is not nothing to
  /// load.
  bool _read = false;

  /// True while an on-demand summary is out.
  bool _summarizing = false;

  /// Whether the user has asked to see what the intelligence layer produced.
  ///
  /// The layer works on its own, in the background — that is the point of it —
  /// but a note is the user's writing, and a machine's reading of it does not
  /// get to sit on top of that uninvited.
  bool _showAi = false;
  bool _loadingAi = false;
  Map<String, String> _relatedTitles = const {};
  AudioPlayer? _player;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.focusAddTag) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addTag());
    }
    // Deliberately not loading the intelligence layer's output here. It does
    // its work on its own, in the background; showing it is the user's call,
    // and opening a note should not fire two network requests nobody asked
    // for. See [_revealAi].
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  /// Asks for a summary and says what came back.
  ///
  /// The old version was `await summarizeOnDemand(id); await _reload();` — it
  /// discarded the result and reloaded either way, so a summary that could
  /// not be produced looked exactly like one that had not arrived yet, which
  /// looked exactly like a tap that had not registered.
  Future<void> _summarize(String noteId) async {
    setState(() => _summarizing = true);
    Summary? summary;
    try {
      summary = await widget.services.summarizeOnDemand(noteId);
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
    await _reload();
    if (!mounted || summary != null) return;
    // Gated above on the capability and the provider, so reaching here means
    // the request was made and came back with nothing — a refusal, an
    // unusable answer, or a provider that failed. Which of those it was is
    // not distinguishable here; that it did not work is.
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).summarizeFailed,
      kind: NexBannerKind.failed,
      haptics: widget.preferences?.haptics ?? true,
    );
  }

  Future<void> _reload() async {
    final loaded = await widget.services.getById(widget.noteId);
    final pinnedNoteCount = await widget.services.pinnedNoteCount();
    if (!mounted) return;
    setState(() {
      _note = loaded;
      _pinnedNoteCount = pinnedNoteCount;
      _read = true;
    });
    final note = _note;
    // A voice note, and now a music file someone shared in as well. Both are a
    // path to something the bundled player already decodes, and there was
    // never a reason for the second to be a filename and a byte count.
    if (note != null && note.mediaUri != null && _player == null) {
      final playable =
          note.type == NoteType.voice ||
          (note.type == NoteType.file &&
              NexFileKinds.of(path: note.mediaUri, mimeType: note.mimeType) ==
                  NexFileKind.audio);
      if (playable) _initPlayer(note.mediaUri!);
    }
  }

  Future<void> _initPlayer(String uri) async {
    if (!File(uri).existsSync()) return;
    final player = AudioPlayer();
    try {
      await player.setFilePath(uri);
      _player = player;
      _posSub = player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _durSub = player.durationStream.listen((d) {
        if (mounted && d != null) setState(() => _duration = d);
      });
      if (mounted) setState(() {});
    } catch (_) {
      await player.dispose();
    }
  }

  /// Opens the intelligence panel, fetching what it needs the first time.
  Future<void> _revealAi() async {
    setState(() {
      _showAi = true;
      _loadingAi = true;
    });
    await _loadAi();
    if (mounted) setState(() => _loadingAi = false);
  }

  Future<void> _loadAi() async {
    final suggestions = await widget.services.suggestTags(widget.noteId);
    final related = await widget.services.relatedNotes(widget.noteId);
    // Resolve the related notes' titles here rather than in build: build runs
    // every frame and each lookup crosses the isolate boundary.
    final titles = <String, String>{};
    for (final hit in related) {
      final note = await widget.services.getById(hit.noteId);
      final content = note?.content;
      if (content != null) titles[hit.noteId] = content;
    }
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _related = related;
      _relatedTitles = titles;
    });
  }

  /// The text the main copy action hands to the clipboard: whatever
  /// [Note.displayText] shows on screen, so the button copies what the user
  /// is actually looking at — a caption once there is one, not the
  /// transcript/OCR text underneath it. That text keeps its own small copy
  /// icon in the AI panel (see [_copyDerivedText]).
  String? _copyableText(Note note) => note.displayText;

  /// The note's own words, wherever they live.
  ///
  /// [Note.displayText] prefers a caption the user wrote, which is the right
  /// answer for the card and the wrong one here: a photo captioned "receipt"
  /// with a page of Persian read out of it has a page worth translating and a
  /// one-word caption that is not.
  String _translatableText(Note note) {
    for (final candidate in [
      note.content,
      note.transcriptText,
      note.ocrText,
      note.displayText,
    ]) {
      final text = candidate?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  void _toast(String message) {
    nexShowBanner(context, message: message);
  }

  Future<void> _copyText() async {
    final note = _note;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    final text = _copyableText(note);
    if (text == null) {
      _toast(l10n.nothingToCopy);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast(l10n.copied);
  }

  /// Copies one of the AI panel's own texts — a transcript, an OCR read, a
  /// summary — rather than [_copyableText]'s fallback chain, which is the
  /// note's own content first and would copy the wrong thing here.
  Future<void> _copyDerivedText(String text) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast(l10n.copied);
  }

  Future<void> _copyPath() async {
    final note = _note;
    final uri = note?.mediaUri;
    if (uri == null) return;
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: uri));
    if (!mounted) return;
    _toast(l10n.copied);
  }

  /// Hands the note's media to the OS, exactly as a file manager would: the
  /// default handler opens it, or the system asks which app should.
  Future<void> _openExternally() async {
    final note = _note;
    final uri = note?.mediaUri;
    if (uri == null) return;
    final l10n = AppLocalizations.of(context);
    if (!File(uri).existsSync()) {
      _toast(l10n.mediaUnavailable);
      return;
    }
    final result = await nexOpenFile(uri, mimeType: note?.mimeType);
    if (!mounted) return;
    if (result != FileOpenOutcome.opened) _toast(l10n.cannotOpen);
  }

  /// Opens a link note in whatever handles the web on this device.
  ///
  /// `externalApplication` rather than an in-app view: a bookmark is a
  /// promise to hand you back to the page, and a stripped-down web view
  /// without your session, your extensions or your history is not that page.
  Future<void> _openLink() async {
    final url = _note?.linkUrl;
    if (url == null) return;
    final l10n = AppLocalizations.of(context);
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((Object _) => false);
    if (!mounted) return;
    if (!opened) _toast(l10n.cannotOpen);
  }

  /// Ticks one line of a checklist and re-reads the note.
  ///
  /// Straight through to the repository, which rewrites the note's content —
  /// there is no local list being edited here, so nothing can drift out of
  /// step with what is stored.
  Future<void> _toggleItem(int index) async {
    final note = _note;
    if (note == null) return;
    await widget.services.toggleChecklistItem(note.id, index);
    await _reload();
  }

  /// The note's optional headline. Empty clears it, so the one control both
  /// names a note and un-names it.
  /// Shares the media itself for a file, photo or voice note, and the body for
  /// a text note — sharing a text note as a zero-byte attachment would be
  /// useless to whatever receives it.
  Future<void> _share() async {
    final note = _note;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    if (!await nexShareNote(note) && mounted) _toast(l10n.nothingToCopy);
  }

  /// Editing a text note in place. `updateNote` existed on every layer down to
  /// the repository, but no screen ever called it — a captured note could not
  /// be corrected after the fact.
  Future<void> _editContent() async {
    final note = _note;
    if (note == null || note.type != NoteType.text) return;
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: note.content ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editNote),
        content: NexDialogBody(
          // Persian content in an English-locale app used to render
          // left-aligned: the field followed the ambient (LTR) Directionality
          // rather than the script actually typed into it. Re-evaluated on
          // every keystroke, the same way the capture box already does.
          child: StatefulBuilder(
            builder: (context, setDialogState) => TextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              minLines: 3,
              keyboardType: TextInputType.multiline,
              textDirection: nexDirectionOf(controller.text),
              textAlign: TextAlign.start,
              // See the same field in capture_sheet.dart: BoxWidthStyle.max
              // (the default) paints a double-tap word selection out to the
              // end of the line on Persian text.
              selectionWidthStyle: BoxWidthStyle.tight,
              // The same selection menu the capture sheet has: a note is
              // formatted where it is written, and it is written in both.
              contextMenuBuilder: nexFormatContextMenuBuilder(context),
              onChanged: (_) => setDialogState(() {}),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == note.content) return;
    await widget.services.updateNote(note.id, trimmed);
    await widget.services.refreshTimeline();
    await _reload();
  }

  /// The reminder menu: four times someone actually means, and a picker.
  ///
  /// Quick choices rather than a date picker first. "Tomorrow morning" is
  /// what people say, and making them assemble it out of a calendar and a
  /// clock to say it is the reason reminder features go unused.
  Future<void> _pickReminder() async {
    final note = _note;
    if (note == null) return;
    // The picker itself lives in `reminder_picker.dart`: a swipe on the
    // timeline opens the same sheet, and two copies of a date-and-permission
    // flow is two places for it to drift.
    if (await nexPickReminder(
      context: context,
      services: widget.services,
      note: note,
    )) {
      await _reload();
    }
  }

  Future<void> _showDetails() async {
    final note = _note;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    final uri = note.mediaUri;
    final file = uri == null ? null : File(uri);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.details),
        content: NexDialogBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: l10n.noteType(note.type.wireName), value: ''),
              _DetailRow(
                label: l10n.created,
                value: _formatTimestamp(note.createdAt),
              ),
              _DetailRow(
                label: l10n.updated,
                value: _formatTimestamp(note.updatedAt),
              ),
              if (note.tags.isNotEmpty)
                _DetailRow(
                  label: l10n.tags,
                  value: note.tags.map((t) => t.name).join('، '),
                ),
              if (file != null && file.existsSync())
                _DetailRow(
                  label: l10n.size,
                  value: nexFormatBytes(file.lengthSync()),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  static String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// Tagging a note.
  ///
  /// The dialog used to offer five hardcoded starter names and a colour grid,
  /// and no way to reach the tags the user had actually made — so the one list
  /// it needed to show was the one list it did not have.
  Future<void> _addTag() async {
    final note = _note;
    final all = await widget.services.listTags();
    if (!mounted) return;
    final choice = await TagPickerSheet.show(
      context,
      tags: all,
      alreadyOn: note?.tags.map((t) => t.id).toSet() ?? const {},
    );
    if (choice == null || !mounted) return;
    await widget.services.addTag(
      noteId: widget.noteId,
      name: choice.tag?.name ?? choice.name!,
      color: choice.color,
    );
    await widget.services.refreshTimeline();
    await _reload();
  }

  Future<void> _togglePin() async {
    final note = _note;
    if (note == null) return;
    if (note.pinnedAt != null) {
      await widget.services.unpinNote(note.id);
    } else {
      await widget.services.pinNote(note.id);
    }
    await widget.services.refreshTimeline();
    await _reload();
  }

  Future<void> _editCaption() async {
    final note = _note;
    if (note == null || note.type == NoteType.text) return;
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: note.caption ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.caption),
        content: NexDialogBody(
          child: StatefulBuilder(
            builder: (context, setDialogState) => TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              textDirection: nexDirectionOf(controller.text),
              textAlign: TextAlign.start,
              selectionWidthStyle: BoxWidthStyle.tight,
              decoration: InputDecoration(hintText: l10n.captionHint),
              onChanged: (_) => setDialogState(() {}),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await widget.services.setCaption(widget.noteId, value);
    await widget.services.refreshTimeline();
    await _reload();
  }

  /// Everything the intelligence layer produced about this note, behind a tap.
  ///
  /// The layer runs on its own — a recording is transcribed and a long note is
  /// summarised in the background, without being asked — but its output does
  /// not open on top of the user's own writing. One quiet row says what is
  /// there; the tap is what puts it on screen. That also means opening a note
  /// no longer fires two network calls nobody requested.
  Widget _aiPanel(Note note, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final derived = <(String, String)>[
      if (note.transcriptText?.trim().isNotEmpty ?? false)
        (l10n.transcript, note.transcriptText!.trim()),
      if (note.ocrText?.trim().isNotEmpty ?? false)
        (l10n.ocr, note.ocrText!.trim()),
      if (_summaryIsMeaningful(note)) (l10n.summary, note.summaryText!.trim()),
    ];
    // With nothing derived and no provider behind it, the row would promise
    // something the app cannot deliver.
    if (derived.isEmpty && !widget.services.aiIsUsable) {
      return const SizedBox.shrink();
    }

    if (!_showAi) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => unawaited(_revealAi()),
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(
            derived.isEmpty
                ? l10n.aiShow
                : l10n.aiReady(derived.map((d) => d.$1).join(' · ')),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: NexSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(l10n.aiSection, style: theme.textTheme.bodySmall),
            ),
            TextButton(
              onPressed: () => setState(() => _showAi = false),
              child: Text(l10n.hide),
            ),
          ],
        ),
        for (final (label, body) in derived) ...[
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
              InkWell(
                onTap: () => unawaited(_copyDerivedText(body)),
                borderRadius: BorderRadius.circular(NexRadius.lg),
                child: Padding(
                  padding: const EdgeInsets.all(NexSpacing.xs),
                  child: Icon(
                    Icons.copy_outlined,
                    size: 14,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            ],
          ),
          NexBodyText(body),
          const SizedBox(height: NexSpacing.sm),
        ],
        if (_loadingAi)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: NexSpacing.sm),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_suggestions.isNotEmpty) ...[
          Text(l10n.suggestedTags, style: theme.textTheme.bodySmall),
          Wrap(
            spacing: NexSpacing.xs,
            children: [
              for (final s in _suggestions)
                ActionChip(
                  label: Text(s.name),
                  onPressed: () async {
                    await widget.services.addTag(noteId: note.id, name: s.name);
                    setState(() {
                      _suggestions = _suggestions
                          .where((x) => x.name != s.name)
                          .toList();
                    });
                    _reload();
                  },
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
        ],
        if (_related.isNotEmpty) ...[
          Text(l10n.relatedNotes, style: theme.textTheme.bodySmall),
          for (final hit in _related)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                _relatedTitles[hit.noteId] ?? hit.noteId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(l10n.similarity(hit.score.toStringAsFixed(2))),
            ),
        ],
        if (!_loadingAi &&
            derived.isEmpty &&
            _suggestions.isEmpty &&
            _related.isEmpty)
          Text(
            l10n.aiNothingYet,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.secondary,
            ),
          ),
      ],
    );
  }

  bool _summaryIsMeaningful(Note note) {
    final summary = note.summaryText?.trim();
    if (summary == null || summary.isEmpty) return false;
    final source = (note.content ?? note.transcriptText ?? note.ocrText ?? '')
        .trim();
    if (source.isEmpty) return summary.isNotEmpty;
    if (summary == source) return false;
    if (summary.length >= source.length) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final note = _note;
    if (note == null) {
      // "Not found" is a conclusion, and it needs the read to have finished
      // to be one. It used to be shown for any null note, which includes
      // every note that had simply not arrived yet — so opening a perfectly
      // good note on slow storage said it was gone, then produced it. That is
      // a temporary wait told as data loss, about the one thing this app is
      // for.
      return Padding(
        padding: const EdgeInsets.all(NexSpacing.lg),
        child: _read
            ? Text(l10n.noteNotFound)
            : const NexSkeleton(height: 16),
      );
    }
    final isText = note.type == NoteType.text;
    final hasMedia = note.mediaUri != null;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // The sheet is as tall as what is in it, up to almost the whole screen.
    //
    // There used to be a floor as well: past 220 characters of text the sheet
    // was forced to 70% of the screen. That is a step, and a step is exactly
    // what it looked like — a note one word over the line jumped to two thirds
    // of the display and then left the bottom third empty underneath its own
    // last sentence, because the content it was making room for was not that
    // tall. Where the threshold fell also depended on things the reader could
    // not see; a voice note's hidden transcript used to trip it.
    //
    // Nothing is needed in its place. `Flexible` inside a `MainAxisSize.min`
    // column already grows with the text and stops at the cap, so a long note
    // opens tall and a two-line thought hugs itself — which is what the floor
    // was trying to approximate in one jump.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.92),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            // A long note's sheet is almost entirely content, so the handle
            // at the top was the only part of it that could be dragged shut.
            child: NexDismissOnOverscroll(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The type and when it was captured, on one line.
                    //
                    // The date used to be on the timeline card and the time was
                    // nowhere except behind the Details button — so the card
                    // carried the half nobody needed at a glance and hid the
                    // half you go looking for. It is the other way round now:
                    // the card is clean, and this is where you find out when.
                    Row(
                      children: [
                        Text(
                          l10n.noteType(note.type.wireName),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Spacer(),
                        Text(
                          _formatTimestamp(note.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    if (note.type == NoteType.checklist)
                      // The one place a checklist is interactive. On the card it
                      // is a picture of a list; here it is the list.
                      _ChecklistBody(
                        items: note.checklistItems,
                        onToggle: (index) => unawaited(_toggleItem(index)),
                      )
                    else if (note.type == NoteType.link)
                      _LinkBody(note: note, onOpen: _openLink)
                    else if (note.type == NoteType.text)
                      // Only the body turns. The "Text" label, the action row and the
                      // rest of the sheet keep the interface's direction.
                      //
                      // Rendered where the writer reached for the formatting menu and
                      // left exactly as typed where they did not — the same predicate
                      // the card strips by, so the two always agree about what a note
                      // says. A sentence with a stray asterisk in it is a sentence.
                      nexLooksLikeMarkdown(note.content ?? '')
                      // Selection belongs to the area rather than to the text,
                      // which is what lets a link and a `code` span still
                      // answer a tap — `SelectableText` handles every gesture
                      // itself and dispatches none of them onward.
                      ? SelectionArea(
                          child: NexMarkdown(
                            note.content!,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(height: 1.62),
                            selectable: false,
                            onTapLink: _openHref,
                            onCopyCode: (code) =>
                                unawaited(_copyCodeSpan(context, code)),
                          ),
                        )
                      : NexBodyText(
                          note.content ?? '',
                          // Looser leading than the timeline card: this is the surface a
                          // person actually reads a long note on, and 1.5 at 16px runs
                          // the lines together over a screenful of text.
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(height: 1.62),
                        )
                    else if (note.type == NoteType.voice) ...[
                      Text(
                        l10n.voiceDuration(
                          ((note.durationMs ?? 0) / 1000).ceil(),
                        ),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (_player != null) ...[
                        const SizedBox(height: NexSpacing.sm),
                        _VoicePlayerControls(
                          player: _player!,
                          position: _position,
                          duration: _duration,
                        ),
                      ],
                      if (note.transcriptText == null)
                        Text(
                          l10n.voiceSearchHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ] else if (note.type == NoteType.photo) ...[
                      if (note.mediaUri != null &&
                          File(note.mediaUri!).existsSync()) ...[
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              NexPageRoute<void>(
                                builder: (_) =>
                                    _FullScreenPhoto(path: note.mediaUri!),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(NexRadius.md),
                            child: Image.file(
                              File(note.mediaUri!),
                              fit: BoxFit.cover,
                              height: 220,
                              width: double.infinity,
                            ),
                          ),
                        ),
                        const SizedBox(height: NexSpacing.sm),
                        Text(
                          l10n.tapToExpand,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else
                        Text(
                          l10n.mediaUnavailable,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                    ] else ...[
                      // File — same sheet, ADR-008 display fields. Tapping the row
                      // hands it to the OS, so the note behaves like the same file
                      // does in a file manager.
                      InkWell(
                        onTap: _openExternally,
                        borderRadius: BorderRadius.circular(NexRadius.lg),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: NexSpacing.sm,
                            horizontal: NexSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.insert_drive_file_outlined,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: NexSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      note.content?.trim().isNotEmpty == true
                                          ? note.content!
                                          : (note.mediaUri != null
                                                ? p.basename(note.mediaUri!)
                                                : l10n.file),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                    if (note.mediaUri != null &&
                                        File(note.mediaUri!).existsSync())
                                      Text(
                                        [
                                          nexFormatBytes(
                                            File(note.mediaUri!).lengthSync(),
                                          ),
                                          if (note.mimeType != null)
                                            note.mimeType!,
                                        ].join(' · '),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                              fontWeight: FontWeight.w400,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.revealInFolder,
                                onPressed: _copyPath,
                                icon: const Icon(
                                  Icons.folder_outlined,
                                  size: 18,
                                ),
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              Icon(
                                Icons.open_in_new,
                                size: 18,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // A file shown rather than merely listed. The note
                      // itself only ever held the filename — the content is in
                      // a file on disk — so this is the one place in the app
                      // that reads a note's media back.
                      if (note.mediaUri != null)
                        _FileBody(
                          path: note.mediaUri!,
                          kind: NexFileKinds.of(
                            path: note.mediaUri,
                            mimeType: note.mimeType,
                          ),
                          player: _player,
                          position: _position,
                          duration: _duration,
                        ),
                    ],
                    if (note.type != NoteType.text) ...[
                      const SizedBox(height: NexSpacing.md),
                      Text(
                        l10n.caption,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: NexSpacing.xs),
                      if (note.caption != null &&
                          note.caption!.trim().isNotEmpty)
                        NexBodyText(
                          note.caption!,
                          style: Theme.of(context).textTheme.bodyLarge,
                        )
                      else
                        Text(
                          l10n.noCaption,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: _editCaption,
                          child: Text(
                            note.caption == null || note.caption!.trim().isEmpty
                                ? l10n.addCaption
                                : l10n.editCaption,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: NexSpacing.md),
                    Wrap(
                      spacing: NexSpacing.xs,
                      children: [
                        for (final tag in note.tags)
                          TagChip(
                            tag: tag,
                            onRemove: () async {
                              await widget.services.removeTag(
                                noteId: note.id,
                                tagId: tag.id,
                              );
                              // Unlike _addTag, this can take a tag's usage
                              // count to zero — without a refresh here, the
                              // filter row on the timeline never hears about
                              // it and keeps showing a tag nothing wears
                              // anymore until some unrelated capture or
                              // delete happens to trigger one.
                              await widget.services.refreshTimeline();
                              await _reload();
                            },
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(l10n.tag),
                          onPressed: _addTag,
                        ),
                      ],
                    ),
                    _aiPanel(note, l10n),
                  ],
                ),
              ),
            ),
          ),
          // The actions are pinned below the scroll rather than sitting at the
          // end of it: a long note would otherwise bury them under a screenful
          // of text, and they belong to the note, not to its ending.
          //
          // They sit in the open, as icons. They were behind a single
          // overflow button in the corner, which is the hardest place on a
          // phone to reach and told you nothing about what was inside. Delete
          // lives here too now, last and in red — the timeline still owns
          // the actual soft-delete, so the undo toast is offered exactly
          // once regardless of where the button sits.
          Divider(height: 1, color: Theme.of(context).colorScheme.outline),
          Padding(
            padding: EdgeInsets.only(
              left: NexSpacing.md,
              right: NexSpacing.md,
              top: NexSpacing.sm,
              bottom: MediaQuery.viewInsetsOf(context).bottom + NexSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActionRow(
                  groups: [
                    // The note itself: take it somewhere, or change it.
                    [
                      if (hasMedia)
                        _DetailAction(
                          icon: Icons.open_in_new,
                          label: l10n.open,
                          onPressed: _openExternally,
                        ),
                      // Absent on Windows rather than present and broken: the
                      // platform has no share sheet this app can use, and an
                      // action that does nothing teaches the wrong lesson.
                      if (nexCanShare)
                        _DetailAction(
                          icon: Icons.ios_share,
                          label: l10n.share,
                          onPressed: _share,
                        ),
                      _DetailAction(
                        icon: Icons.copy_outlined,
                        label: l10n.copy,
                        onPressed: _copyText,
                      ),
                      if (isText)
                        _DetailAction(
                          icon: Icons.edit_outlined,
                          label: l10n.edit,
                          onPressed: _editContent,
                        ),
                      if (note.type == NoteType.link)
                        _DetailAction(
                          icon: Icons.open_in_new,
                          label: l10n.openLink,
                          onPressed: _openLink,
                        ),
                    ],
                    // Where it sits and when it comes back. Tag and caption
                    // both already have their own affordance further up the
                    // sheet — repeating them here duplicated an action that
                    // was never out of reach.
                    [
                      _DetailAction(
                        icon: note.pinnedAt != null
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        label: note.pinnedAt != null
                            ? l10n.unpin
                            : _pinnedNoteCount >= 5
                            ? l10n.pinLimitReached
                            : l10n.pin,
                        onPressed:
                            note.pinnedAt == null && _pinnedNoteCount >= 5
                            ? null
                            : _togglePin,
                      ),
                      if (NexReminders.supported)
                        _DetailAction(
                          icon: note.dueAt == null
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                          label: l10n.remind,
                          onPressed: _pickReminder,
                        ),
                    ],
                    // The assistant. Tinted as a group and set off by the
                    // divider, because "is this the AI one?" is a question no
                    // single icon in a row of nine can answer on its own.
                    [
                      // Only when there is something behind it. The
                      // assistant's own rule everywhere else in the app: a
                      // button that can only answer "unavailable" is worse
                      // than no button.
                      if (widget.preferences case final preferences?
                          when AiChatSheet.availableFor(preferences))
                        _DetailAction(
                          // The sparkle, which is what this app means by AI
                          // everywhere else — on the chat sheet's own header
                          // and on the daily recap. A speech bubble meant
                          // "chat", and the report was that nobody could tell
                          // it was the assistant.
                          icon: Icons.auto_awesome,
                          label: l10n.askAboutNote,
                          accent: true,
                          onPressed: () => unawaited(
                            AiChatSheet.show(
                              context,
                              preferences: preferences,
                              services: widget.services,
                              history: preferences.chatHistory,
                              focus: note,
                            ),
                          ),
                        ),
                      // The transcript and the extracted text count: a
                      // recording in one language and a photographed sign in
                      // another are exactly the notes someone needs this for,
                      // and neither has typed content to offer.
                      if (widget.preferences case final preferences?
                          when TranslateSheet.availableFor(preferences) &&
                              _translatableText(note).isNotEmpty)
                        _DetailAction(
                          icon: Icons.translate,
                          label: l10n.translate,
                          accent: true,
                          onPressed: () => unawaited(
                            TranslateSheet.show(
                              context,
                              text: _translatableText(note),
                              preferences: preferences,
                              services: widget.services,
                            ),
                          ),
                        ),
                      // Only where it can do something. The action used to be
                      // offered unconditionally, and every path that cannot
                      // produce a summary — the capability switched off, no
                      // provider configured, the adapter unavailable —
                      // returns null from the same call, so tapping it did
                      // nothing at all and taught the reader that a primary
                      // action was broken. Gated on the same pair the
                      // translate action uses, plus the switch that governs
                      // this one specifically.
                      if (widget.preferences case final preferences?
                          when preferences.effectiveAiCapabilities.summarization &&
                              aiTextAvailableWith(preferences.aiProvider))
                        _DetailAction(
                          // Was the sparkle, which now belongs to the
                          // assistant. This one says what it does.
                          icon: Icons.summarize_outlined,
                          label: l10n.summarize,
                          accent: true,
                          // Null while one is already running, so a slow
                          // summary cannot be asked for four more times.
                          onPressed: _summarizing
                              ? null
                              : () => unawaited(_summarize(note.id)),
                        ),
                    ],
                    // What the note is, and getting rid of it.
                    [
                      _DetailAction(
                        icon: Icons.info_outline,
                        label: l10n.details,
                        onPressed: _showDetails,
                      ),
                      _DetailAction(
                        icon: Icons.delete_outline,
                        label: l10n.delete,
                        destructive: true,
                        onPressed: () =>
                            Navigator.pop(context, DetailResult.deleted),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          if (value.isNotEmpty) ...[
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoicePlayerControls extends StatelessWidget {
  const _VoicePlayerControls({
    required this.player,
    required this.position,
    required this.duration,
  });

  final AudioPlayer player;
  final Duration position;
  final Duration duration;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;
    return Column(
      children: [
        Row(
          children: [
            StreamBuilder<PlayerState>(
              stream: player.playerStateStream,
              builder: (context, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton.filled(
                  onPressed: () {
                    if (playing) {
                      player.pause();
                    } else {
                      player.play();
                    }
                  },
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                );
              },
            ),
            Expanded(
              child: Slider(
                value: position.inMilliseconds.clamp(0, totalMs).toDouble(),
                max: totalMs.toDouble(),
                onChanged: (v) =>
                    player.seek(Duration(milliseconds: v.round())),
              ),
            ),
            Text(
              '${_fmt(position)} / ${_fmt(duration)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _FullScreenPhoto extends StatefulWidget {
  const _FullScreenPhoto({required this.path});

  final String path;

  @override
  State<_FullScreenPhoto> createState() => _FullScreenPhotoState();
}

class _FullScreenPhotoState extends State<_FullScreenPhoto> {
  double _dragDy = 0;

  /// Past this much downward drag, releasing closes the viewer instead of
  /// springing back — the photo equivalent of the swipe card's own commit
  /// threshold.
  static const _dismissDistance = 120.0;

  void _onDragUpdate(DragUpdateDetails details) {
    // Only downward: there is nothing above the photo to reveal.
    setState(
      () => _dragDy = (_dragDy + details.delta.dy).clamp(0.0, double.infinity),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final flung = details.velocity.pixelsPerSecond.dy > 800;
    if (_dragDy > _dismissDistance || flung) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _dragDy = 0);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragDy / _dismissDistance).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Color.lerp(Colors.black, Colors.transparent, progress),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        // Opaque rather than the default deferToChild: a contained image
        // rarely fills the whole screen, and a swipe that starts in the
        // black margin around it — not on the image's own pixels — must
        // dismiss too.
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Center(
          child: Transform.translate(
            offset: Offset(0, _dragDy),
            child: InteractiveViewer(
              child: Image.file(File(widget.path), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling strip of labelled icon actions.
///
/// Scrolling rather than wrapping: the number of actions depends on the note's
/// type, and a strip that silently grows a second row shifts everything below
/// it as you move between notes. Each action holds the 48px accessibility
/// floor (see [nexMinTapTarget]), so on a narrow or lower-resolution phone the
/// full strip — up to eight actions — routinely does not fit; shrinking the
/// icons to squeeze more in was tried and rejected for exactly the same
/// reason 48px is the floor everywhere else. A faded edge is the fix: it
/// only ever hints that a scroll is possible, never claims one is not needed,
/// which a same-width `Row` that just quietly clips its last icon does not.
/// The action strip, in groups with a hairline between them.
///
/// One row, not two. A second row would read as two strips and costs vertical
/// space in a sheet that is already competing with the note itself; a divider
/// says the same thing — these belong together, those do not — in one pixel.
///
/// Groups are passed as a list of lists so an empty one disappears without
/// leaving a divider stranded against the edge. Which actions are present
/// depends on the note's type, the platform and whether AI is configured, so
/// empty groups are the normal case rather than an edge one.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.groups});

  final List<List<Widget>> groups;

  @override
  Widget build(BuildContext context) {
    // AlignmentDirectional needs a resolved TextDirection before
    // LinearGradient.createShader can use it — createShader's shaderCallback
    // only receives a Rect, not a BuildContext, so the direction has to be
    // captured here and threaded through explicitly.
    final textDirection = Directionality.of(context);
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [0.0, 0.06, 0.94, 1.0],
      ).createShader(bounds, textDirection: textDirection),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: _withDividers(context)),
      ),
    );
  }

  List<Widget> _withDividers(BuildContext context) {
    final filled = groups.where((group) => group.isNotEmpty).toList();
    final theme = Theme.of(context);
    return [
      for (var i = 0; i < filled.length; i++) ...[
        if (i > 0)
          // It was `outlineVariant` at 0.6 — the quiet token, quieter — on the
          // theory that a seam should be softer than a border. It could not be
          // seen in either theme, which makes it a seam that separates
          // nothing.
          //
          // `outline` is not enough either: measured, it is 2.79:1 against the
          // sheet's own surface in the light theme, under the 3:1 floor for a
          // boundary someone is meant to perceive (WCAG 1.4.11). The
          // secondary-text token at three-quarters clears it on every surface
          // this row is drawn on, in both themes — 3.5:1 at worst.
          //
          // The restraint that was being aimed for lives in the height
          // instead: 24 against a 48-pixel row still reads as a seam rather
          // than cutting the row into boxes.
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        ...filled[i],
      ],
    ];
  }
}

/// Icon-only: [label] still exists, as the tooltip and the semantic name,
/// just not painted. Seven of these in a row used to run past the width of
/// the sheet on anything but the widest phone; the label was the only thing
/// making each one wider than the 48px floor it actually needs.
///
/// No fill, no border: a bare icon with its own ripple reads lighter than a
/// row of outlined chips, and there is nothing here for a border to set
/// apart from — the sheet's background is already the only thing behind it.
class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// The assistant's colour. What the row was missing was not a better glyph
  /// for each AI action but a way to see that three of them are the same kind
  /// of thing — a tint does that across the group where no single icon can.
  final bool accent;

  /// Delete's own colour: the row is otherwise neutral, and this is the one
  /// action here that cannot be undone by repeating it.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onPressed == null
        ? theme.disabledColor
        : accent
        ? theme.colorScheme.primary
        : destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          child: SizedBox(
            width: nexMinTapTarget,
            height: nexMinTapTarget,
            child: Center(child: Icon(icon, size: 20, color: color)),
          ),
        ),
      ),
    );
  }
}

/// A checklist, where ticking is the point.
///
/// Rows in their stored order here, unlike the card, which floats what is
/// still to do to the top: on the card you want the next thing, in the sheet
/// you want the list you wrote.
class _ChecklistBody extends StatelessWidget {
  const _ChecklistBody({required this.items, required this.onToggle});

  final List<ChecklistItem> items;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = checklistProgress(items);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (progress.total > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: Text(
              l10n.checklistProgress(progress.done, progress.total),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (var i = 0; i < items.length; i++)
          InkWell(
            onTap: () => onToggle(i),
            borderRadius: BorderRadius.circular(NexRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A real checkbox, sized to the text beside it. The whole row
                  // is the target, so this is the mark rather than the control.
                  Icon(
                    items[i].done
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 22,
                    color: items[i].done
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: NexBodyText(
                      items[i].text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: items[i].done
                            ? TextDecoration.lineThrough
                            : null,
                        color: items[i].done
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A link note: the page's description if one was read, then the address
/// itself as the row that opens it.
class _LinkBody extends StatelessWidget {
  const _LinkBody({required this.note, required this.onOpen});

  final Note note;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = note.linkUrl ?? '';
    final host = urlHost(url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note.linkExcerpt != null) ...[
          NexBodyText(
            note.linkExcerpt!,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: NexSpacing.md),
        ],
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(NexRadius.md),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(NexSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(NexRadius.md),
            ),
            child: Row(
              children: [
                Icon(Icons.public, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (host != null)
                        Text(host, style: theme.textTheme.titleSmall),
                      // The full address under the host, so it is possible to
                      // see where a link actually goes before following it.
                      Text(
                        url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Everything a file note can show beyond its own name.
///
/// A file note stores a filename and a path, and for most of this app's life
/// that was all the sheet did with one: print the name, hand the path to the
/// operating system. Markdown was the single exception, rendered by a widget
/// wired to that one format by a predicate that could answer exactly one
/// question.
///
/// This is the generalisation. [NexFileKind] answers what the file is; this
/// answers what to do about it. A kind it has no answer for renders nothing
/// and leaves the row above untouched — which is the old behaviour, and the
/// right one for a format nobody here can draw.
class _FileBody extends StatelessWidget {
  const _FileBody({
    required this.path,
    required this.kind,
    required this.player,
    required this.position,
    required this.duration,
  });

  final String path;
  final NexFileKind kind;

  /// Non-null once the sheet has loaded this file into the audio player.
  ///
  /// Owned by the sheet rather than created here: the player outlives any one
  /// rebuild, and a second one on the same note would play the file twice.
  final AudioPlayer? player;
  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (kind.isText) return _FileTextBody(path: path, kind: kind);
    if (kind == NexFileKind.document) return _DocumentBody(path: path);
    if (kind == NexFileKind.image) return _ImageFileBody(path: path);
    if (kind == NexFileKind.audio && player != null) {
      return Padding(
        padding: const EdgeInsets.only(top: NexSpacing.sm),
        child: _VoicePlayerControls(
          player: player!,
          position: position,
          duration: duration,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// An image that arrived as a file rather than through the camera.
///
/// The same picture in the same app looked entirely different depending on
/// which door it came in by: one captured or picked was shown full width and
/// opened into the viewer, and one dropped on the share sheet was a filename
/// and a byte count. Same picture, same gesture, same viewer, either way now.
class _ImageFileBody extends StatelessWidget {
  const _ImageFileBody({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (!File(path).existsSync()) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              NexPageRoute<void>(builder: (_) => _FullScreenPhoto(path: path)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NexRadius.md),
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                height: 220,
                width: double.infinity,
                // A file named `.png` that is not one lands here as a decode
                // failure rather than as a crash. Nothing is drawn, and the
                // row above still says everything the file itself knows.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(l10n.tapToExpand, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Reads a file off disk and shows it as what it is.
///
/// The words are not in the note. A file note stores its filename and a path,
/// so this is the one place in the app that reads a note's media back as text.
///
/// The read is synchronous, and in [initState] rather than in `build`. Both
/// halves are deliberate. Synchronous because [maxBytes] bounds it: half a
/// megabyte off local storage costs a fraction of a frame, and the sheet
/// around it already calls `existsSync` and `lengthSync` to print the file's
/// size. In `initState` because this sheet rebuilds on every action taken in
/// it — captioning, tagging, pinning — and re-reading the file each time would
/// turn a cheap read into a repeated one. A table is parsed there too, for the
/// same reason.
///
/// Three outcomes, all of them said out loud. A file too large is named but
/// not rendered, and says why. A file that cannot be read reports the
/// runtime's own words: a preview that silently shows nothing is
/// indistinguishable from a file that genuinely has nothing in it, and this
/// project has paid for that confusion before.
class _FileTextBody extends StatefulWidget {
  const _FileTextBody({required this.path, required this.kind});

  final String path;

  /// One of the four [NexFileKind.isText] kinds. Each is read the same way and
  /// drawn differently — and the difference matters: a `.txt` must not go
  /// through a Markdown parser, or a shopping list whose line starts with `#`
  /// acquires a heading nobody typed.
  final NexFileKind kind;

  /// Past this, the file is named but not rendered. Generous for prose —
  /// roughly a quarter of a million characters — and small enough that both
  /// reading it and building it stay inside a frame.
  static const maxBytes = 512 * 1024;

  /// Past this many rows a table is drawn short and says so. The byte cap
  /// alone does not bound the widget count: half a megabyte of two-column CSV
  /// is tens of thousands of rows, and every one of them would be built.
  static const maxRows = 200;

  @override
  State<_FileTextBody> createState() => _FileTextBodyState();
}

class _FileTextBodyState extends State<_FileTextBody> {
  String? _text;
  String? _error;
  bool _tooLarge = false;
  List<List<String>> _rows = const [];
  int _omittedRows = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_FileTextBody old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.kind != widget.kind) _load();
  }

  void _load() {
    _text = null;
    _error = null;
    _tooLarge = false;
    _rows = const [];
    _omittedRows = 0;
    try {
      final file = File(widget.path);
      if (!file.existsSync()) return;
      if (file.lengthSync() > _FileTextBody.maxBytes) {
        _tooLarge = true;
        return;
      }
      _text = file.readAsStringSync();
    } catch (error) {
      // Reached by a file that is not UTF-8 as much as by one that cannot be
      // opened — `readAsStringSync` decodes, and a mislabelled binary lands
      // here rather than rendering as mojibake.
      _error = '$error';
      return;
    }
    if (widget.kind != NexFileKind.table) return;
    final parsed = NexDelimitedText.parse(
      _text!,
      delimiter: NexDelimitedText.delimiterFor(
        NexFileKinds.extensionOf(widget.path),
      ),
    );
    if (parsed.length > _FileTextBody.maxRows) {
      _omittedRows = parsed.length - _FileTextBody.maxRows;
      _rows = parsed.sublist(0, _FileTextBody.maxRows);
    } else {
      _rows = parsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_tooLarge) {
      return Padding(
        padding: const EdgeInsets.only(top: NexSpacing.sm),
        child: Text(l10n.filePreviewTooLarge, style: quiet),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: NexSpacing.sm),
        child: Text(l10n.filePreviewUnreadable(_error!), style: quiet),
      );
    }
    final text = _text?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: switch (widget.kind) {
        NexFileKind.markdown => SelectionArea(
          child: NexMarkdown(
            text,
            selectable: false,
            onTapLink: _openHref,
            onCopyCode: (code) => unawaited(_copyCodeSpan(context, code)),
          ),
        ),
        // The same leading as a text note's body in this same sheet: a plain
        // file someone shared and a note someone typed are both prose, and
        // there is no reason to read them at two different densities.
        NexFileKind.plainText => NexBodyText(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.62),
        ),
        NexFileKind.table when _rows.isNotEmpty => _DelimitedTable(
          rows: _rows,
          omitted: _omittedRows,
        ),
        // A table whose parse produced nothing is still a text file, and
        // showing its source beats showing an empty frame.
        NexFileKind.table || NexFileKind.code => _CodeBlock(text),
        _ => const SizedBox.shrink(),
      },
    );
  }

}

/// Copies a tapped `code` span and says so.
///
/// Silently would not do: a tap that copied and a tap that missed look exactly
/// the same, and the second is the more likely of the two on a span two
/// characters wide.
Future<void> _copyCodeSpan(BuildContext context, String code) async {
  final message = AppLocalizations.of(context).copied;
  await Clipboard.setData(ClipboardData(text: code));
  if (!context.mounted) return;
  nexShowBanner(context, message: message);
}

/// Follows a link out of rendered Markdown — a note's own body, or a file
/// shown inside one.
///
/// A schemeless href is ignored rather than guessed at: `[x](notes/plan.md)`
/// is a relative path in somebody's repository, and handing it to the OS as a
/// URL opens nothing at best.
Future<void> _openHref(String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null || !uri.hasScheme) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No handler for this scheme on this device. The link stays a link.
  }
}

/// A `.docx`, read into Markdown and rendered like any other document in a
/// note.
///
/// Off the main thread, unlike every other preview here. A `.docx` is
/// compressed, so the file's size says little about how much work opening it
/// is: unzipping and parsing a few hundred kilobytes of XML is not a fraction
/// of a frame the way reading half a megabyte of plain text is. So this one
/// waits, and shows that it is waiting.
///
/// Only `.docx` for now. The other document kinds — PDF above all — reach this
/// widget and render nothing, exactly as they did before, because showing them
/// needs a renderer this app does not carry.
class _DocumentBody extends StatefulWidget {
  const _DocumentBody({required this.path});

  final String path;

  @override
  State<_DocumentBody> createState() => _DocumentBodyState();
}

class _DocumentBodyState extends State<_DocumentBody> {
  NexDocxText? _document;
  String? _error;
  bool _tooLarge = false;
  bool _unreadable = false;
  bool _loading = false;

  /// The only document format with a reader here. Everything else stays a
  /// named file, which is what it was.
  bool get _readable => NexFileKinds.extensionOf(widget.path) == 'docx';

  @override
  void initState() {
    super.initState();
    // Assigned rather than set: `setState` inside `initState` — or inside
    // `didUpdateWidget` — fires during a build, which Flutter rejects. A
    // rebuild is already coming in both cases.
    _loading = _readable;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_DocumentBody old) {
    super.didUpdateWidget(old);
    if (old.path == widget.path) return;
    _document = null;
    _error = null;
    _tooLarge = false;
    _unreadable = false;
    _loading = _readable;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!_readable) return;
    final path = widget.path;
    NexDocxText? read;
    String? error;
    var tooLarge = false;
    try {
      final file = File(path);
      if (file.existsSync()) {
        if (file.lengthSync() > NexDocx.maxBytes) {
          tooLarge = true;
        } else {
          final bytes = await file.readAsBytes();
          // The one preview in this sheet that leaves the main thread. See
          // the class comment: a `.docx` is compressed, so its size on disk
          // says very little about the work of opening it.
          read = await Isolate.run(() => NexDocx.read(bytes));
        }
      }
    } catch (caught) {
      error = '$caught';
    }
    // The path can have changed while the isolate was working — the sheet is
    // reused across notes — and writing this answer onto a different file
    // would be worse than dropping it.
    if (!mounted || widget.path != path) return;
    setState(() {
      _document = read;
      _error = error;
      _tooLarge = tooLarge;
      _unreadable = !tooLarge && error == null && read == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_readable) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget say(String message) => Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Text(message, style: quiet),
    );

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: NexSpacing.sm),
        child: NexSkeleton(height: 16),
      );
    }
    if (_tooLarge) return say(l10n.filePreviewTooLarge);
    if (_error != null) return say(l10n.filePreviewUnreadable(_error!));
    if (_unreadable) return say(l10n.documentUnreadable);
    final document = _document;
    if (document == null || document.markdown.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionArea(
            child: NexMarkdown(
              document.markdown,
              selectable: false,
              onTapLink: _openHref,
              onCopyCode: (code) => unawaited(_copyCodeSpan(context, code)),
            ),
          ),
          // A document that stops early with nothing said about it reads as a
          // document that is that short.
          if (document.truncated) say(l10n.documentTruncated),
        ],
      ),
    );
  }
}

/// Source and configuration, in the same block the Markdown renderer already
/// uses for a fenced block — so a `.dart` file and a code fence inside a `.md`
/// file look like the same thing, because they are.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge ?? const TextStyle();
    return Container(
      padding: const EdgeInsets.all(NexSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      // Source does not wrap. A line broken at the container's edge is a
      // different line from the one in the file, and where indentation carries
      // meaning it is a misleading one — so long lines scroll sideways, the
      // way every editor shows them.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          text,
          // Left to right whatever the interface is doing, and whatever the
          // strings inside the file are: source is written left to right, and
          // letting a Persian comment turn the block would put the indentation
          // of every line on the wrong side.
          textDirection: TextDirection.ltr,
          style: base.copyWith(
            // By family name rather than a bundled font, for the same reason
            // the Markdown renderer does it: the app ships one typeface for
            // its own text, and code that falls back to the platform's mono is
            // closer to right than code set in the body face.
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Courier New', 'monospace'],
            fontSize: (base.fontSize ?? 16) - 1,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

/// A `.csv` or `.tsv`, drawn as the table it is.
///
/// Borders, weights and padding are the ones the Markdown renderer uses for a
/// Markdown table, deliberately: a spreadsheet exported to CSV and a table
/// typed into a note are the same object to a reader.
class _DelimitedTable extends StatelessWidget {
  const _DelimitedTable({required this.rows, required this.omitted});

  final List<List<String>> rows;

  /// How many rows were left undrawn. Said out loud rather than trailing off:
  /// a table that stops at row 200 with no explanation reads as a file that
  /// ends at row 200.
  final int omitted;

  /// Past this, a cell wraps instead of stretching its column across the
  /// screen. One paragraph in one cell should not set the width of the table.
  static const _maxCellWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.bodyLarge;
    final columns = rows.fold<int>(
      0,
      (widest, row) => row.length > widest ? row.length : widest,
    );
    if (columns == 0) return const SizedBox.shrink();
    // The same whole-document rule as the Markdown renderer: the direction
    // comes from what is written, not from the interface language, so a
    // Persian spreadsheet starts its first column on the right.
    final direction =
        nexDirectionOf(rows.first.join(' ')) ?? Directionality.of(context);
    return Directionality(
      textDirection: direction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: scheme.outlineVariant),
              children: [
                for (var r = 0; r < rows.length; r++)
                  TableRow(
                    children: [
                      for (var c = 0; c < columns; c++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: NexSpacing.sm,
                            vertical: NexSpacing.xs,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _maxCellWidth,
                            ),
                            child: Text(
                              // Ragged rows are left ragged by the parser
                              // rather than padded, so the short ones are
                              // filled in here — at the edge, where inventing
                              // an empty cell is a drawing decision and not a
                              // claim about the file.
                              c < rows[r].length ? rows[r][c] : '',
                              style: r == 0
                                  ? base?.copyWith(fontWeight: FontWeight.w700)
                                  : base,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (omitted > 0)
            Padding(
              padding: const EdgeInsets.only(top: NexSpacing.xs),
              child: Text(
                l10n.tableTruncated(rows.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
