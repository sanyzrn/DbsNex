part of '../vault_screen.dart';

/// What was picked to attach, before it is sealed into the vault.
typedef _Picked = ({
  Uint8List bytes,
  String kind,
  String name,
  String? mime,
  int? durationMs,
});

/// Voice, photos and files in private messages.
///
/// Each attachment is sealed into [VaultFiles] — encrypted, under a key kept
/// in the platform's encrypted store — and the message holds only its id and
/// what to call it. Every plain copy made on the way (a recording in
/// progress, the picker's copy of a photo or file) is deleted once it has
/// been sealed.
extension _VaultAttachments on _VaultScreenState {
  Future<void> _attach() async {
    final l = AppLocalizations.of(context);
    final kind = await nexShowSheet<String>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.mic_none),
            title: Text(l.vaultAttachVoice),
            onTap: () => Navigator.pop(sheet, 'voice'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l.vaultAttachCamera),
            onTap: () => Navigator.pop(sheet, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: Text(l.vaultAttachPhoto),
            onTap: () => Navigator.pop(sheet, 'photo'),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(l.vaultAttachFile),
            onTap: () => Navigator.pop(sheet, 'file'),
          ),
          const SizedBox(height: NexSpacing.sm),
        ],
      ),
    );
    if (kind == null || !mounted) return;
    _touch();
    final _Picked? picked;
    try {
      picked = switch (kind) {
        'voice' => await _recordVoice(),
        'camera' => await _takePhoto(),
        'photo' => await _pickPhoto(),
        _ => await _pickFile(),
      };
    } catch (_) {
      if (mounted) _rebuild(() => error = l.vaultError);
      return;
    }
    if (picked == null || !mounted) return;
    if (picked.bytes.length > VaultFiles.maxBytes) {
      _rebuild(() => error = l.vaultAttachTooLarge);
      return;
    }
    // The picker took the app to the background, which hides the vault.
    if (!unlocked) await (session.isOpen ? _reload() : _unlock());
    if (!mounted || !unlocked) return;
    final caption = messageInput.text.trim();
    await _operate(() async {
      final id = await _vaultFiles.put(picked!.bytes);
      final empty = VaultStore.empty(VaultKind.message);
      try {
        await store.save(
          VaultEntry(
            id: empty.id,
            kind: empty.kind,
            fields: {
              if (caption.isNotEmpty) 'text': caption,
              'file': id,
              'fileKind': picked.kind,
              'fileName': picked.name,
              'fileSize': '${picked.bytes.length}',
              if (picked.mime != null) 'fileMime': picked.mime!,
              if (picked.durationMs != null)
                'durationMs': '${picked.durationMs}',
            },
            updatedAt: empty.updatedAt,
          ),
        );
      } catch (_) {
        await _vaultFiles.delete(id);
        rethrow;
      }
    });
    if (mounted && error == null && messageInput.text.trim() == caption) {
      messageInput.clear();
    }
  }

  Future<_Picked?> _recordVoice() async {
    final l = AppLocalizations.of(context);
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        if (mounted) _rebuild(() => error = l.micDenied);
        return null;
      }
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, VaultFiles.openFolder),
      );
      await dir.create(recursive: true);
      final path = p.join(dir.path, 'voice-${const Uuid().v4()}.m4a');
      final started = Stopwatch()..start();
      await recorder.start(const RecordConfig(), path: path);
      if (!mounted) return null;
      final keep = await nexShowSheet<bool>(
        context: context,
        dismissible: false,
        builder: (_) => RecordingSheet(recorder: recorder),
      );
      final recorded = await recorder.stop();
      started.stop();
      final file = File(recorded ?? path);
      try {
        if (keep != true || !await file.exists()) return null;
        return (
          bytes: await file.readAsBytes(),
          kind: 'voice',
          name: 'voice.m4a',
          mime: 'audio/mp4',
          durationMs: started.elapsedMilliseconds,
        );
      } finally {
        if (await file.exists()) await file.delete();
      }
    } finally {
      await recorder.dispose();
    }
  }

  /// A photo straight from Nex's own camera — the same panel the timeline
  /// uses — sealed into the vault without ever becoming a note.
  Future<_Picked?> _takePhoto() async {
    final shot = await nexTakePhoto(context);
    if (shot == null) return null;
    try {
      return (
        bytes: await shot.readAsBytes(),
        kind: 'photo',
        name: 'photo.jpg',
        mime: 'image/jpeg',
        durationMs: null,
      );
    } finally {
      await discardPickedCopy(shot.path, await getTemporaryDirectory());
    }
  }

  Future<_Picked?> _pickPhoto() async {
    final shot = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (shot == null) return null;
    try {
      return (
        bytes: await shot.readAsBytes(),
        kind: 'photo',
        name: p.basename(shot.path),
        mime: shot.mimeType,
        durationMs: null,
      );
    } finally {
      await discardPickedCopy(shot.path, await getTemporaryDirectory());
    }
  }

  Future<_Picked?> _pickFile() async {
    final file = await openFile();
    if (file == null) return null;
    try {
      if (await file.length() > VaultFiles.maxBytes) {
        return (
          bytes: Uint8List(VaultFiles.maxBytes + 1),
          kind: 'file',
          name: file.name,
          mime: null,
          durationMs: null,
        );
      }
      return (
        bytes: await file.readAsBytes(),
        kind: 'file',
        name: file.name,
        mime: file.mimeType,
        durationMs: null,
      );
    } finally {
      await discardPickedCopy(file.path, await getTemporaryDirectory());
    }
  }

  /// Deletes a message and, when it has one, its sealed attachment.
  Future<void> _deleteMessage(VaultEntry entry) async {
    await store.delete(entry.id);
    final id = entry.value('file');
    if (id.isNotEmpty) {
      try {
        await _vaultFiles.delete(id);
      } catch (_) {
        // The message is gone; an unreadable leftover is noise.
      }
    }
  }
}

/// An attachment in a private message: a photo shown, a recording played, a
/// file opened. Decrypted only when looked at.
class _VaultAttachmentView extends StatefulWidget {
  const _VaultAttachmentView({
    super.key,
    required this.entry,
    required this.files,
    required this.onShare,
  });

  final VaultEntry entry;
  final VaultFiles files;

  /// Sends a decrypted copy to another app — the visible way out for a file,
  /// which on its own was a name and a size nobody knew what to do with.
  final VoidCallback onShare;

  @override
  State<_VaultAttachmentView> createState() => _VaultAttachmentViewState();
}

class _VaultAttachmentViewState extends State<_VaultAttachmentView> {
  Future<Uint8List>? _photo;
  AudioPlayer? _player;
  bool _playing = false;
  bool _failed = false;
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positionSub;

  String get _id => widget.entry.value('file');
  String get _kind => widget.entry.value('fileKind');

  @override
  void initState() {
    super.initState();
    if (_kind == 'photo') _photo = widget.files.get(_id);
  }

  @override
  void dispose() {
    unawaited(_positionSub?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    try {
      final player = _player ??= AudioPlayer();
      if (_playing) {
        await player.pause();
        if (mounted) setState(() => _playing = false);
        return;
      }
      if (player.audioSource == null) {
        final copy = await widget.files.openCopy(_id, 'voice.m4a');
        await player.setFilePath(copy.path);
        _positionSub = player.positionStream.listen((at) {
          if (mounted) setState(() => _position = at);
        });
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed && mounted) {
            setState(() {
              _playing = false;
              _position = Duration.zero;
            });
            unawaited(player.seek(Duration.zero));
            unawaited(player.pause());
          }
        });
      }
      if (mounted) setState(() => _playing = true);
      unawaited(player.play());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _open() async {
    try {
      final copy = await widget.files.openCopy(
        _id,
        widget.entry.value('fileName'),
      );
      final outcome = await nexOpenFile(
        copy.path,
        mimeType: widget.entry.value('fileMime').isEmpty
            ? null
            : widget.entry.value('fileMime'),
      );
      // Nothing on the phone opens it: offer it to an app that might.
      if (outcome == FileOpenOutcome.failed) widget.onShare();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _view(Uint8List bytes) => Navigator.of(context).push(
    NexPageRoute<void>(
      builder: (_) => NexPhotoViewer.memory(bytes),
      swipeBackEnabled: false,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_failed) {
      return Text(
        l.vaultAttachUnreadable,
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
      );
    }
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    String clock(int seconds) => nexDigits(
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
      persian: persian,
    );
    switch (_kind) {
      case 'photo':
        return FutureBuilder<Uint8List>(
          future: _photo,
          builder: (context, snap) {
            if (snap.hasError) return Text(l.vaultAttachUnreadable);
            final bytes = snap.data;
            if (bytes == null) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Semantics(
              button: true,
              label: l.vaultOpenPhoto,
              child: GestureDetector(
                onTap: () => _view(bytes),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(NexRadius.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Image.memory(bytes, fit: BoxFit.cover),
                  ),
                ),
              ),
            );
          },
        );
      case 'voice':
        final total = int.tryParse(widget.entry.value('durationMs')) ?? 0;
        final shown = _playing || _position > Duration.zero
            ? _position.inSeconds
            : (total / 1000).round();
        final progress = total <= 0
            ? 0.0
            : (_position.inMilliseconds / total).clamp(0.0, 1.0);
        return Row(
          children: [
            IconButton.filled(
              tooltip: _playing ? l.vaultAttachPause : l.vaultAttachPlay,
              onPressed: _togglePlay,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(NexRadius.xs),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: scheme.onSecondaryContainer.withValues(
                    alpha: 0.15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            Text(
              clock(shown),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSecondaryContainer,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      default:
        final size = int.tryParse(widget.entry.value('fileSize')) ?? 0;
        return Material(
          color: scheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(NexRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _open,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                NexSpacing.sm,
                NexSpacing.sm,
                0,
                NexSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(NexRadius.sm),
                    ),
                    child: Icon(
                      Icons.insert_drive_file_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.entry.value('fileName'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          nexDigits(
                            nexFormatBytes(size),
                            persian:
                                Localizations.localeOf(context).languageCode ==
                                'fa',
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l.share,
                    onPressed: widget.onShare,
                    icon: const Icon(Icons.ios_share_outlined),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}
