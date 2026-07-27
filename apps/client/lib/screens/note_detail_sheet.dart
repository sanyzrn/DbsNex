import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import '../platform/nex_services.dart';

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

  Future<void> _addTag() async {
    final controller = TextEditingController();
    _color = null;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Add tag'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Tag name'),
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
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  child: const Text('Add'),
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
    final controller = TextEditingController(text: note.caption ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Caption'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Optional description…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
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
    final note = _note;
    if (note == null) {
      return const Padding(
        padding: EdgeInsets.all(NexSpacing.lg),
        child: Text('Note not found'),
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
            Text(
              note.type.wireName.toUpperCase(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: NexSpacing.sm),
            if (note.type == NoteType.text)
              Text(
                note.content ?? '',
                style: Theme.of(context).textTheme.bodyLarge,
              )
            else if (note.type == NoteType.voice) ...[
              Text(
                'Voice · ${((note.durationMs ?? 0) / 1000).ceil()}s',
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
                  'Transcript',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(note.transcriptText!),
              ] else
                Text(
                  'Searchable by tag/date only',
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
                  'Tap image to view full screen',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else
                Text('Photo', style: Theme.of(context).textTheme.bodyLarge),
              if (note.ocrText != null) ...[
                const SizedBox(height: NexSpacing.sm),
                Text('OCR', style: Theme.of(context).textTheme.bodySmall),
                Text(note.ocrText!),
              ],
            ] else ...[
              // File — same sheet, ADR-008 display fields.
              Row(
                children: [
                  Icon(
                    Icons.insert_drive_file_outlined,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: Text(
                      note.content?.trim().isNotEmpty == true
                          ? note.content!
                          : (note.mediaUri != null
                              ? p.basename(note.mediaUri!)
                              : 'File'),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
              if (note.mediaUri != null && File(note.mediaUri!).existsSync()) ...[
                const SizedBox(height: NexSpacing.xs),
                Text(
                  [
                    nexFormatBytes(File(note.mediaUri!).lengthSync()),
                    if (note.mimeType != null) note.mimeType!,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                        fontWeight: FontWeight.w400,
                      ),
                ),
              ],
            ],
            if (note.type != NoteType.text) ...[
              const SizedBox(height: NexSpacing.md),
              Text('Caption', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: NexSpacing.xs),
              if (note.caption != null && note.caption!.trim().isNotEmpty)
                Text(
                  note.caption!,
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              else
                Text(
                  'No caption',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _editCaption,
                  child: Text(
                    note.caption == null || note.caption!.trim().isEmpty
                        ? 'Add caption'
                        : 'Edit caption',
                  ),
                ),
              ),
            ],
            if (_summaryIsMeaningful(note)) ...[
              const SizedBox(height: NexSpacing.md),
              Text('Summary', style: Theme.of(context).textTheme.bodySmall),
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
                  label: const Text('Tag'),
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
                      'Suggested tags (dismissible)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _suggestions = const []),
                    child: const Text('Dismiss'),
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
                'Related notes',
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
                  subtitle: Text('similarity ${hit.score.toStringAsFixed(2)}'),
                ),
            ],
            const SizedBox(height: NexSpacing.md),
            TextButton(
              onPressed: () async {
                await widget.services.summarizeOnDemand(note.id);
                await _reload();
              },
              child: const Text('Summarize'),
            ),
            TextButton(
              onPressed: () async {
                await widget.services.deleteNote(note.id);
                if (!context.mounted) return;
                Navigator.pop(context, DetailResult.deleted);
              },
              child: const Text('Delete'),
            ),
          ],
        ),
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
