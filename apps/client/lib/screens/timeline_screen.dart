import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../platform/nex_services.dart';
import 'note_detail_sheet.dart';
import 'search_screen.dart';
import 'settings_sheet.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.services});

  final NexServices services;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late List<Note> _notes;
  StreamSubscription<List<Note>>? _sub;
  final _scroll = ScrollController();
  bool _loadingMore = false;
  bool _exhausted = false;

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
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
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
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
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
              const Text('Recording…'),
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
                child: const Text('Discard'),
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
    final picker = ImagePicker();
    // FR-1.5: open camera immediately; gallery is an explicit switch option.
    XFile? file = await picker.pickImage(source: ImageSource.camera);
    if (file == null && mounted) {
      final useGallery = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text('No photo captured. Switch to gallery?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Gallery'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nex'),
        actions: [
          IconButton(
            tooltip: 'Search',
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
            tooltip: 'Settings',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => SettingsSheet(services: widget.services),
              );
            },
          ),
        ],
      ),
      body: _notes.isEmpty
          ? Center(
              child: Text(
                'Tap + to capture',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              itemCount: _notes.length + (_loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _notes.length) {
                  return const Padding(
                    padding: EdgeInsets.all(NexSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final note = _notes[index];
                return NoteCard(
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
                );
              },
            ),
      floatingActionButton: SizedBox(
        width: nexMinTapTarget + 12,
        height: nexMinTapTarget + 12,
        child: FloatingActionButton(
          onPressed: _openCapture,
          tooltip: 'Capture',
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
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.short_text),
            title: const Text('Text'),
            onTap: () => Navigator.pop(context, NoteType.text),
          ),
          ListTile(
            leading: const Icon(Icons.mic_none),
            title: const Text('Voice'),
            onTap: () => Navigator.pop(context, NoteType.voice),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Photo'),
            onTap: () => Navigator.pop(context, NoteType.photo),
          ),
        ],
      ),
    );
  }
}

/// Text capture sheet — auto-saves on first content, no Save button (ADR-002).
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
        decoration: const InputDecoration(
          hintText: 'Capture…',
          border: InputBorder.none,
        ),
        onChanged: _onChanged,
      ),
    );
  }
}
