import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_services.dart';

/// What the sheet reports back when it closes.
///
/// The timeline already switched on this to offer undo after a delete, but the
/// type was never declared and the sheet popped without a value, so the undo
/// path was unreachable.
enum DetailResult { deleted }

/// The entries of the sheet's overflow menu, so the switch over the chosen
/// entry is exhaustive rather than a string comparison.
enum _NoteMenuAction {
  open,
  share,
  edit,
  copy,
  copyPath,
  addTag,
  caption,
  summarize,
  details,
}

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
  Map<String, String> _relatedTitles = const {};
  String? _color;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAi());
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
    final result = await OpenFilex.open(uri, type: note?.mimeType);
    if (!mounted) return;
    if (result.type != ResultType.done) _toast(l10n.cannotOpen);
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
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          minLines: 3,
          keyboardType: TextInputType.multiline,
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
        content: Column(
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

  /// FR-2 "more options": everything the sheet can do that is not already a
  /// primary control, in one menu instead of two loose text buttons.
  Future<void> _openMenu() async {
    final note = _note;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    final isText = note.type == NoteType.text;
    final hasMedia = note.mediaUri != null;
    final choice = await showModalBottomSheet<_NoteMenuAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasMedia)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(l10n.open),
                onTap: () => Navigator.pop(ctx, _NoteMenuAction.open),
              ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(l10n.share),
              onTap: () => Navigator.pop(ctx, _NoteMenuAction.share),
            ),
            if (isText)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.edit),
                onTap: () => Navigator.pop(ctx, _NoteMenuAction.edit),
              ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.copy),
              onTap: () => Navigator.pop(ctx, _NoteMenuAction.copy),
            ),
            if (hasMedia)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(l10n.revealInFolder),
                onTap: () => Navigator.pop(ctx, _NoteMenuAction.copyPath),
              ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(l10n.addTag),
              onTap: () => Navigator.pop(ctx, _NoteMenuAction.addTag),
            ),
            if (!isText)
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: Text(
                  note.caption == null || note.caption!.trim().isEmpty
                      ? l10n.addCaption
                      : l10n.editCaption,
                ),
                onTap: () => Navigator.pop(ctx, _NoteMenuAction.caption),
              ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(l10n.summarize),
              onTap: () => Navigator.pop(ctx, _NoteMenuAction.summarize),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.details),
              onTap: () => Navigator.pop(ctx, _NoteMenuAction.details),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _NoteMenuAction.open:
        await _openExternally();
      case _NoteMenuAction.share:
        await _share();
      case _NoteMenuAction.edit:
        await _editContent();
      case _NoteMenuAction.copy:
        await _copyText();
      case _NoteMenuAction.copyPath:
        await _copyPath();
      case _NoteMenuAction.addTag:
        await _addTag();
      case _NoteMenuAction.caption:
        await _editCaption();
      case _NoteMenuAction.summarize:
        await widget.services.summarizeOnDemand(note.id);
        await _reload();
      case _NoteMenuAction.details:
        await _showDetails();
    }
  }

  Future<void> _addTag() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    _color = null;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(l10n.addTag),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(hintText: l10n.tagName),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Wrap(
                    spacing: NexSpacing.xs,
                    children: [
                      for (final suggestion in suggestedStarterTags)
                        ActionChip(
                          label: Text(suggestion),
                          onPressed: () => Navigator.pop(ctx, suggestion),
                        ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  Wrap(
                    spacing: NexSpacing.xs,
                    children: [
                      for (final hex in tagAccentPalette)
                        GestureDetector(
                          onTap: () => setLocal(() => _color = hex),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(hex.substring(1), radix: 16) +
                                    0xFF000000,
                              ),
                              shape: BoxShape.circle,
                              border: _color == hex
                                  ? Border.all(
                                      color: Theme.of(ctx).colorScheme.primary,
                                      width: 2,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  child: Text(l10n.addAction),
                ),
              ],
            );
          },
        );
      },
    );
    if (name != null && name.isNotEmpty) {
      await widget.services.addTag(
        noteId: widget.noteId,
        name: name,
        color: _color,
      );
      _reload();
    }
    controller.dispose();
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
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: l10n.captionHint),
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

  bool _summaryIsMeaningful(Note note) {
    final summary = note.summaryText?.trim();
    if (summary == null || summary.isEmpty) return false;
    final source = (note.content ??
            note.transcriptText ??
            note.ocrText ??
            '')
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
    return Padding(
      padding: EdgeInsets.only(
        left: NexSpacing.md,
        right: NexSpacing.md,
        top: NexSpacing.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NexSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.noteType(note.type.wireName),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: l10n.moreOptions,
                  icon: const Icon(Icons.more_horiz),
                  onPressed: _openMenu,
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.sm),
            if (note.type == NoteType.text)
              Text(
                note.content ?? '',
                style: Theme.of(context).textTheme.bodyLarge,
              )
            else if (note.type == NoteType.voice) ...[
              Text(
                l10n.voiceDuration(((note.durationMs ?? 0) / 1000).ceil()),
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
              if (note.transcriptText != null) ...[
                const SizedBox(height: NexSpacing.sm),
                Text(
                  l10n.transcript,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(note.transcriptText!),
              ] else
                Text(
                  l10n.voiceSearchHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ] else if (note.type == NoteType.photo) ...[
              if (note.mediaUri != null && File(note.mediaUri!).existsSync()) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _FullScreenPhoto(path: note.mediaUri!),
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
              if (note.ocrText != null) ...[
                const SizedBox(height: NexSpacing.sm),
                Text(l10n.ocr, style: Theme.of(context).textTheme.bodySmall),
                Text(note.ocrText!),
              ],
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
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            if (note.mediaUri != null &&
                                File(note.mediaUri!).existsSync())
                              Text(
                                [
                                  nexFormatBytes(
                                      File(note.mediaUri!).lengthSync()),
                                  if (note.mimeType != null) note.mimeType!,
                                ].join(' · '),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      fontWeight: FontWeight.w400,
                                    ),
                              ),
                          ],
                        ),
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
              Text(l10n.caption, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: NexSpacing.xs),
              if (note.caption != null && note.caption!.trim().isNotEmpty)
                Text(
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
            if (_summaryIsMeaningful(note)) ...[
              const SizedBox(height: NexSpacing.md),
              Text(l10n.summary, style: Theme.of(context).textTheme.bodySmall),
              Text(note.summaryText!),
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
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.suggestedTags,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _suggestions = const []),
                    child: Text(l10n.dismiss),
                  ),
                ],
              ),
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
                          _suggestions = _suggestions
                              .where((x) => x.name != s.name)
                              .toList();
                        });
                        _reload();
                      },
                    ),
                ],
              ),
            ],
            if (_related.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.md),
              Text(
                l10n.relatedNotes,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
            const SizedBox(height: NexSpacing.md),
            // Delete stays outside the overflow menu: it is the one destructive
            // action, and the timeline owns the actual soft-delete so the undo
            // toast is offered exactly once.
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
