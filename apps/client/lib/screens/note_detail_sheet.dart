import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../platform/file_opener.dart';
import '../platform/sharing.dart';
import '../widgets/nex_dialog.dart';
import '../platform/nex_services.dart';
import '../widgets/tag_picker.dart';

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
    this.focusAddTag = false,
  });

  final NexServices services;
  final String noteId;
  final bool focusAddTag;

  @override
  State<NoteDetailSheet> createState() => _NoteDetailSheetState();
}

class _NoteDetailSheetState extends State<NoteDetailSheet> {
  Note? _note;
  List<TagSuggestion> _suggestions = const [];
  List<SemanticHit> _related = const [];

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

  Future<void> _reload() async {
    final loaded = await widget.services.getById(widget.noteId);
    if (!mounted) return;
    setState(() => _note = loaded);
    final note = _note;
    if (note?.type == NoteType.voice &&
        note?.mediaUri != null &&
        _player == null) {
      _initPlayer(note!.mediaUri!);
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

  /// The text a note can hand to the clipboard: its body, or whatever the
  /// intelligence layer derived from its media.
  String? _copyableText(Note note) {
    for (final candidate in [
      note.content,
      note.transcriptText,
      note.ocrText,
      note.caption,
    ]) {
      final text = candidate?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

  /// Shares the media itself for a file, photo or voice note, and the body for
  /// a text note — sharing a text note as a zero-byte attachment would be
  /// useless to whatever receives it.
  Future<void> _share() async {
    final note = _note;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    final uri = note.mediaUri;
    final text = _copyableText(note);
    if (uri != null && File(uri).existsSync()) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(uri, mimeType: note.mimeType)],
          text: note.caption?.trim().isNotEmpty == true ? note.caption : null,
        ),
      );
      return;
    }
    if (text == null) {
      _toast(l10n.nothingToCopy);
      return;
    }
    await SharePlus.instance.share(ShareParams(text: text));
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
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            minLines: 3,
            keyboardType: TextInputType.multiline,
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
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(hintText: l10n.captionHint),
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
      if (_summaryIsMeaningful(note))
        (l10n.summary, note.summaryText!.trim()),
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
          Text(label, style: theme.textTheme.bodySmall),
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
                    await widget.services.addTag(
                      noteId: note.id,
                      name: s.name,
                    );
                    setState(() {
                      _suggestions =
                          _suggestions.where((x) => x.name != s.name).toList();
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
      return Padding(
        padding: const EdgeInsets.all(NexSpacing.lg),
        child: Text(l10n.noteNotFound),
      );
    }
    final isText = note.type == NoteType.text;
    final hasMedia = note.mediaUri != null;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // A long note is the reason this sheet exists, so it opens at reading
    // height instead of a strip at the bottom the user has to drag upward.
    // Short notes still hug their content — a two-line thought does not need
    // two thirds of the screen.
    final long =
        (note.content ?? note.transcriptText ?? note.ocrText ?? '')
            .trim()
            .length >
        220;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.92,
        minHeight: long ? screenHeight * 0.7 : 0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
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
                  if (note.type == NoteType.text)
                    // Only the body turns. The "Text" label, the action row and the
                    // rest of the sheet keep the interface's direction.
                    NexBodyText(
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
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  _FullScreenPhoto(path: note.mediaUri!),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
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
                      borderRadius: BorderRadius.circular(NexColors.cardRadius),
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
                              icon: const Icon(Icons.folder_outlined, size: 18),
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
                  ],
                  if (note.type != NoteType.text) ...[
                    const SizedBox(height: NexSpacing.md),
                    Text(
                      l10n.caption,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    if (note.caption != null && note.caption!.trim().isNotEmpty)
                      NexBodyText(
                        note.caption!,
                        style: Theme.of(context).textTheme.bodyLarge,
                      )
                    else
                      Text(
                        l10n.noCaption,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                            _reload();
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
          // The actions are pinned below the scroll rather than sitting at the
          // end of it: a long note would otherwise bury them under a screenful
          // of text, and they belong to the note, not to its ending.
          //
          // They sit in the open, as labelled icons. They were behind a single
          // overflow button in the corner, which is the hardest place on a
          // phone to reach and told you nothing about what was inside. Delete
          // keeps its own row: it is the one action that cannot be undone by
          // repeating it, and the timeline owns the actual soft-delete so the
          // undo toast is offered exactly once.
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
                  actions: [
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
                    if (!isText)
                      _DetailAction(
                        icon: Icons.notes_outlined,
                        label: l10n.caption,
                        onPressed: _editCaption,
                      ),
                    _DetailAction(
                      icon: Icons.label_outline,
                      label: l10n.tag,
                      onPressed: _addTag,
                    ),
                    _DetailAction(
                      icon: Icons.auto_awesome_outlined,
                      label: l10n.summarize,
                      onPressed: () async {
                        await widget.services.summarizeOnDemand(note.id);
                        await _reload();
                      },
                    ),
                    _DetailAction(
                      icon: Icons.info_outline,
                      label: l10n.details,
                      onPressed: _showDetails,
                    ),
                  ],
                ),
                const SizedBox(height: NexSpacing.sm),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, DetailResult.deleted),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.delete),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
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

class _FullScreenPhoto extends StatelessWidget {
  const _FullScreenPhoto({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// A horizontally scrolling strip of labelled icon actions.
///
/// Scrolling rather than wrapping: the number of actions depends on the note's
/// type, and a strip that silently grows a second row shifts everything below
/// it as you move between notes.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: actions),
  );
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(NexColors.cardRadius),
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: NexSpacing.contentGap),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(NexColors.cardRadius),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
