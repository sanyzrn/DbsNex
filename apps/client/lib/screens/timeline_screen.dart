import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

  @override
  void initState() {
    super.initState();
    _notes = widget.services.search.timeline(limit: 50);
    _sub = widget.services.timelineStream.listen((notes) {
      setState(() {
        _notes = notes;
        _exhausted = false;
      });
    });
    _scroll.addListener(_onScroll);
    widget.preferences.addListener(_onPrefs);
    _osSub = widget.osCapture?.events.listen(_onOsCapture);
    if (widget.openTextCaptureOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _captureText());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _osSub?.cancel();
    widget.preferences.removeListener(_onPrefs);
    _scroll.dispose();
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Future<void> _onOsCapture(Map<Object?, Object?> payload) async {
    if (payload['type'] == 'text_capture' && mounted) {
      await _captureText();
    } else if (mounted) {
      // shared_text / shared_photo already persisted by OsCaptureBridge.
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
    final more = widget.services.loadMore(offset: _notes.length, limit: 50);
    setState(() {
      if (more.isEmpty) {
        _exhausted = true;
      } else {
        _notes = [..._notes, ...more];
      }
      _loadingMore = false;
    });
  }

  Future<void> _openCapture() async {
    final choice = await showModalBottomSheet<NoteType>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const _CaptureChooser(),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case NoteType.text:
        await _captureText();
      case NoteType.voice:
        await _captureVoice();
      case NoteType.photo:
        await _capturePhoto();
      case NoteType.file:
        await _captureFile();
    }
  }

  Future<void> _captureText() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _TextCaptureSheet(services: widget.services),
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
    widget.services.capture.submitVoiceCapture(
      mediaUri: recordedPath,
      mediaBytes: Uint8List.fromList(bytes),
      durationMs: durationMs,
    );
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
    widget.services.capture.submitPhotoCapture(
      mediaUri: dest,
      mediaBytes: Uint8List.fromList(bytes),
    );
    widget.services.refreshTimeline();
  }

  Future<void> _captureFile() async {
    String? path;
    Uint8List? bytes;

    if (!kIsWeb && Platform.isAndroid) {
      const channel = MethodChannel('nex/os_capture');
      final picked = await channel.invokeMethod<String>('pickFile');
      if (picked == null) return;
      path = picked;
      bytes = await File(picked).readAsBytes();
    } else {
      final file = await openFile();
      if (file == null) return;
      path = file.path;
      bytes = await file.readAsBytes();
    }

    final dest = p.join(
      widget.services.mediaDir,
      'file-${DateTime.now().millisecondsSinceEpoch}-${p.basename(path)}',
    );
    await File(dest).writeAsBytes(bytes);
    widget.services.capture.submitFileCapture(
      mediaUri: dest,
      mediaBytes: Uint8List.fromList(bytes),
    );
    widget.services.refreshTimeline();
  }

  void _softDeleteWithUndo(Note note) {
    final l10n = AppLocalizations.of(context);
    widget.services.repo.softDelete(note.id);
    widget.services.refreshTimeline();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.noteDeleted),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            // Soft-delete undo: clear deleted_at by re-inserting isn't ideal;
            // restore via copyWith clearDeletedAt through a small repo helper.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              );
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
      body: _notes.isEmpty
          ? Center(
              child: Text(
                l10n.emptyTimeline,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              semanticChildCount: _notes.length,
              itemCount: _notes.length + (_loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _notes.length) {
                  return const Padding(
                    padding: EdgeInsets.all(NexSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final note = _notes[index];
                return SwipeableNoteCard(
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
                    onTap: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => NoteDetailSheet(
                          services: widget.services,
                          noteId: note.id,
                        ),
                      );
                      widget.services.refreshTimeline();
                    },
                  ),
                );
              },
            ),
      floatingActionButton: SizedBox(
        width: nexMinTapTarget + 12,
        height: nexMinTapTarget + 12,
        child: FloatingActionButton(
          onPressed: _openCapture,
          tooltip: l10n.capture,
          child: const Icon(Icons.add, size: 28),
        ),
      ),
    );
  }
}

class _CaptureChooser extends StatelessWidget {
  const _CaptureChooser();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.short_text),
            title: Text(l10n.text),
            onTap: () => Navigator.pop(context, NoteType.text),
          ),
          ListTile(
            leading: const Icon(Icons.mic_none),
            title: Text(l10n.voice),
            onTap: () => Navigator.pop(context, NoteType.voice),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l10n.photo),
            onTap: () => Navigator.pop(context, NoteType.photo),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(l10n.file),
            onTap: () => Navigator.pop(context, NoteType.file),
          ),
        ],
      ),
    );
  }
}

class _TextCaptureSheet extends StatefulWidget {
  const _TextCaptureSheet({required this.services});

  final NexServices services;

  @override
  State<_TextCaptureSheet> createState() => _TextCaptureSheetState();
}

class _TextCaptureSheetState extends State<_TextCaptureSheet> {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: NexSpacing.md,
        right: NexSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NexSpacing.md,
        top: NexSpacing.sm,
      ),
      child: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: null,
        minLines: 4,
        decoration: InputDecoration(
          hintText: l10n.captureHint,
          border: InputBorder.none,
        ),
        onChanged: _onChanged,
      ),
    );
  }
}
