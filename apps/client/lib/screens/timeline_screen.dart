import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/os_capture_bridge.dart';
import 'note_detail_sheet.dart';
import 'search_screen.dart';
import 'settings_sheet.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.services,
    required this.preferences,
    this.osCapture,
    this.openTextCaptureOnLaunch = false,
  });

  final NexServices services;
  final NexPreferences preferences;
  final OsCaptureBridge? osCapture;
  final bool openTextCaptureOnLaunch;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late List<Note> _notes;
  StreamSubscription<List<Note>>? _sub;
  StreamSubscription<Map<Object?, Object?>>? _osSub;
  final _scroll = ScrollController();
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _openCardId;
  String? _selectedTagId;
  AudioPlayer? _timelinePlayer;
  String? _playingNoteId;

  @override
  void initState() {
    super.initState();
    _notes = widget.services.search.timeline(limit: 50, tagId: _selectedTagId);
    _sub = widget.services.timelineStream.listen((_) {
      if (!mounted) return;
      _reloadNotes(keepCount: true);
    });
    _scroll.addListener(_onScroll);
    widget.preferences.addListener(_onPrefs);
    _osSub = widget.osCapture?.events.listen(_onOsCapture);
    if (widget.openTextCaptureOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCapture());
    }
  }

  void _reloadNotes({bool keepCount = false}) {
    final limit = keepCount ? (_notes.length < 50 ? 50 : _notes.length) : 50;
    setState(() {
      _notes = widget.services.search.timeline(
        limit: limit,
        tagId: _selectedTagId,
      );
      _exhausted = false;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _osSub?.cancel();
    widget.preferences.removeListener(_onPrefs);
    _scroll.dispose();
    _timelinePlayer?.dispose();
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Future<void> _onOsCapture(Map<Object?, Object?> payload) async {
    if (payload['type'] == 'text_capture' && mounted) {
      await _openCapture();
    } else if (mounted) {
      widget.services.refreshTimeline();
    }
  }

  void _onScroll() {
    if (_loadingMore || _exhausted) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final more = widget.services.search.timeline(
      offset: _notes.length,
      limit: 50,
      tagId: _selectedTagId,
    );
    setState(() {
      if (more.isEmpty) {
        _exhausted = true;
      } else {
        _notes = [..._notes, ...more];
      }
      _loadingMore = false;
    });
  }

  Future<void> _toggleVoicePlay(Note note) async {
    final uri = note.mediaUri;
    if (uri == null || !File(uri).existsSync()) return;
    if (_playingNoteId == note.id) {
      await _timelinePlayer?.stop();
      setState(() => _playingNoteId = null);
      return;
    }
    _timelinePlayer ??= AudioPlayer();
    try {
      await _timelinePlayer!.stop();
      await _timelinePlayer!.setFilePath(uri);
      setState(() => _playingNoteId = note.id);
      unawaited(
        _timelinePlayer!.play().then((_) async {
          await _timelinePlayer!.playerStateStream.firstWhere(
            (s) => s.processingState == ProcessingState.completed,
          );
          if (mounted && _playingNoteId == note.id) {
            setState(() => _playingNoteId = null);
          }
        }),
      );
    } catch (_) {
      if (mounted) setState(() => _playingNoteId = null);
    }
  }

  /// Mockup pattern: one sheet with focused text field + Voice/Photo/File.
  Future<void> _openCapture() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CaptureSheet(
        services: widget.services,
        onVoice: () {
          Navigator.pop(ctx);
          _captureVoice();
        },
        onPhoto: () {
          Navigator.pop(ctx);
          _capturePhoto();
        },
        onFile: () {
          Navigator.pop(ctx);
          _captureFile();
        },
      ),
    );
  }

  Future<void> _captureVoice() async {
    final l10n = AppLocalizations.of(context);
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.micPermission)),
        );
      }
      return;
    }
    final path = p.join(
      widget.services.mediaDir,
      'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    final started = DateTime.now();
    await recorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    final keep = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.recording),
              const SizedBox(height: NexSpacing.lg),
              SizedBox(
                width: nexMinTapTarget * 2,
                height: nexMinTapTarget * 2,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Icon(Icons.stop, size: 32),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.discard),
              ),
            ],
          ),
        );
      },
    );
    final recordedPath = await recorder.stop();
    await recorder.dispose();
    if (keep != true || recordedPath == null) {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      return;
    }
    final bytes = await File(recordedPath).readAsBytes();
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    final note = widget.services.capture.submitVoiceCapture(
      mediaUri: recordedPath,
      mediaBytes: Uint8List.fromList(bytes),
      durationMs: durationMs,
    );
    widget.services.scheduleEnrichment(note.id);
    widget.services.refreshTimeline();
  }

  Future<void> _capturePhoto() async {
    final l10n = AppLocalizations.of(context);
    final picker = ImagePicker();
    XFile? file = await picker.pickImage(source: ImageSource.camera);
    if (file == null && mounted) {
      final useGallery = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(l10n.gallerySwitch),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.gallery),
            ),
          ],
        ),
      );
      if (useGallery == true) {
        file = await picker.pickImage(source: ImageSource.gallery);
      }
    }
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final dest = p.join(
      widget.services.mediaDir,
      'photo-${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}',
    );
    await File(dest).writeAsBytes(bytes);
    final note = widget.services.capture.submitPhotoCapture(
      mediaUri: dest,
      mediaBytes: Uint8List.fromList(bytes),
    );
    widget.services.scheduleEnrichment(note.id);
    widget.services.refreshTimeline();
  }

  Future<void> _captureFile() async {
    Uint8List? bytes;
    String? originalName;
    String? mimeType;

    if (!kIsWeb && Platform.isAndroid) {
      final picked = await OsCaptureBridge.pickFile();
      if (picked == null) return;
      originalName = picked.filename;
      mimeType = picked.mimeType;
      bytes = await File(picked.path).readAsBytes();
    } else {
      final file = await openFile();
      if (file == null) return;
      originalName = p.basename(file.path);
      bytes = await file.readAsBytes();
      mimeType = file.mimeType;
    }

    final dest = p.join(
      widget.services.mediaDir,
      'file-${DateTime.now().millisecondsSinceEpoch}-$originalName',
    );
    await File(dest).writeAsBytes(bytes);
    final note = widget.services.capture.submitFileCapture(
      mediaUri: dest,
      mediaBytes: Uint8List.fromList(bytes),
      originalFilename: originalName,
      mimeType: mimeType,
    );
    widget.services.scheduleEnrichment(note.id);
    widget.services.refreshTimeline();
  }

  void _softDeleteWithUndo(Note note) {
    final l10n = AppLocalizations.of(context);
    setState(() => _openCardId = null);
    widget.services.repo.softDelete(note.id);
    widget.services.refreshTimeline();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.noteDeleted),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            widget.services.repo.undelete(note.id);
            widget.services.refreshTimeline();
          },
        ),
      ),
    );
  }

  Future<void> _swipeAddTag(Note note) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NoteDetailSheet(
        services: widget.services,
        noteId: note.id,
        focusAddTag: true,
      ),
    );
    widget.services.refreshTimeline();
  }

  NexSwipeAction _mapAction(SwipeAction action) => switch (action) {
        SwipeAction.delete => NexSwipeAction.delete,
        SwipeAction.addTag => NexSwipeAction.addTag,
      };

  List<Widget> _buildTimelineChildren(BuildContext context) {
    final children = <Widget>[];
    String? lastLabel;
    for (var i = 0; i < _notes.length; i++) {
      final note = _notes[i];
      final label = nexDayLabel(note.createdAt);
      if (label != lastLabel) {
        lastLabel = label;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.md + 4,
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.sm,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      }
      children.add(
        SwipeableNoteCard(
          cardId: note.id,
          openCardId: _openCardId,
          onOpenChanged: (id) => setState(() => _openCardId = id),
          resolveAction: ({required bool isLeading}) => _mapAction(
            widget.preferences.actionFor(isLeading: isLeading),
          ),
          onDelete: () => _softDeleteWithUndo(note),
          onAddTag: () => _swipeAddTag(note),
          child: NoteCard(
            note: note,
            isVoicePlaying: _playingNoteId == note.id,
            onPlayVoice: note.type == NoteType.voice
                ? () => _toggleVoicePlay(note)
                : null,
            onTap: () async {
              if (_openCardId != null) {
                setState(() => _openCardId = null);
                return;
              }
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                useSafeArea: true,
                builder: (_) => SizedBox(
                  width: double.infinity,
                  child: NoteDetailSheet(
                    services: widget.services,
                    noteId: note.id,
                  ),
                ),
              );
              widget.services.refreshTimeline();
            },
          ),
        ),
      );
    }
    if (_loadingMore) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(NexSpacing.md),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tags = widget.services.tags.listTags();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            tooltip: l10n.search,
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SearchScreen(services: widget.services),
                ),
              ).then((_) {
                if (mounted) _reloadNotes(keepCount: true);
              });
            },
          ),
          IconButton(
            tooltip: l10n.settings,
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => SettingsSheet(
                  services: widget.services,
                  preferences: widget.preferences,
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TagFilterRow(
            tags: tags,
            selectedTagId: _selectedTagId,
            onSelected: (id) {
              setState(() => _selectedTagId = id);
              _reloadNotes();
            },
          ),
          Expanded(
            child: _notes.isEmpty
                ? Center(
                    child: Text(
                      l10n.emptyTimeline,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 118),
                    children: _buildTimelineChildren(context),
                  ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Theme(
        data: theme.copyWith(
          floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
            sizeConstraints: const BoxConstraints.tightFor(
              width: nexCaptureFabSize,
              height: nexCaptureFabSize,
            ),
          ),
        ),
        child: FloatingActionButton(
          onPressed: _openCapture,
          tooltip: l10n.capture,
          child: const Icon(Icons.add, size: 32),
        ),
      ),
    );
  }
}

/// Unified capture sheet (mockup): text field focused + Voice/Photo/File.
class _CaptureSheet extends StatefulWidget {
  const _CaptureSheet({
    required this.services,
    required this.onVoice,
    required this.onPhoto,
    required this.onFile,
  });

  final NexServices services;
  final VoidCallback onVoice;
  final VoidCallback onPhoto;
  final VoidCallback onFile;

  @override
  State<_CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<_CaptureSheet> {
  final _controller = TextEditingController();
  String? _noteId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (value.isEmpty) return;
    if (_noteId == null) {
      final note = widget.services.capture.submitTextCapture(value);
      _noteId = note?.id;
    } else {
      widget.services.repo.updateContent(_noteId!, value);
    }
    widget.services.refreshTimeline();
  }

  void _send() {
    final value = _controller.text;
    if (value.isNotEmpty && _noteId == null) {
      widget.services.capture.submitTextCapture(value);
      widget.services.refreshTimeline();
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: NexSpacing.md,
        right: NexSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NexSpacing.md,
        top: NexSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: null,
            minLines: 3,
            decoration: InputDecoration(
              hintText: l10n.captureHint,
              border: InputBorder.none,
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => _send(),
          ),
          const Divider(height: 1),
          const SizedBox(height: NexSpacing.sm),
          Row(
            children: [
              TextButton.icon(
                onPressed: widget.onVoice,
                icon: const Icon(Icons.mic_none, size: 18),
                label: Text(l10n.voice),
              ),
              TextButton.icon(
                onPressed: widget.onPhoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(l10n.photo),
              ),
              TextButton.icon(
                onPressed: widget.onFile,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(l10n.file),
              ),
              const Spacer(),
              IconButton.filled(
                onPressed: _send,
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.onSurface,
                  foregroundColor: theme.colorScheme.surface,
                ),
                icon: const Icon(Icons.arrow_upward),
                tooltip: l10n.capture,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
