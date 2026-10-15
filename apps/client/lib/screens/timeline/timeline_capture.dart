part of '../timeline_screen.dart';

/// Capturing from the timeline: what the capture sheet hands over — a
/// recording to keep, a link to read, a photo or a file to fetch.
extension _TimelineCapture on TimelineScreenState {
  /// Says why a shared file was not kept.
  ///
  /// Names the file and its size next to the limit. "Too large" on its own
  /// invites the reader to think the app is broken; the numbers make it a
  /// rule they can work with, and the first sentence says plainly what kind
  /// of app is refusing.
  void _sayTooLarge(RejectedShare rejection) {
    if (!mounted) return;
    NexBannerHost.of(context)?.show(
      message: AppLocalizations.of(context).shareTooLarge(
        rejection.filename,
        nexFormatBytes(rejection.bytes),
        nexFormatBytes(rejection.limit),
      ),
      kind: NexBannerKind.failed,
    );
  }

  /// Offers the thread a just-captured note clearly continues (W5.3).
  ///
  /// After the save, never before it; one quiet capsule that goes away on its
  /// own; nothing happens without a tap on it. Most captures continue
  /// nothing, and for them this says nothing at all.
  Future<void> _offerThread(String noteId) async {
    if (!widget.preferences.threadSuggestions) return;
    if (!_threadOffered.add(noteId)) return;
    final suggestion = await widget.services.suggestThread(noteId);
    if (suggestion == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final banner = NexBannerHost.of(context);
    if (banner == null) return;
    final thread = suggestion.thread;
    final name = thread?.name ?? suggestion.name!;
    banner.show(
      message: thread != null
          ? l10n.threadSuggestJoin(name)
          : l10n.threadSuggestStart(name),
      actionLabel: thread != null
          ? l10n.threadSuggestAdd
          : l10n.threadSuggestStartAction,
      haptics: false,
      onAction: () => unawaited(() async {
        if (thread != null) {
          await widget.services.addToThread(thread.id, noteId);
        } else {
          await widget.services.createThread(
            name,
            noteIds: [suggestion.withNoteId!, noteId],
          );
        }
        banner.show(message: l10n.threadAdded(name));
      }()),
    );
  }

  /// Reads the page a link note points at, and asks the provider to summarise
  /// it if one is configured.
  ///
  /// Never awaited by the capture path and never able to fail it: the note is
  /// already saved by the time this runs, and every outcome here — offline, a
  /// 404, a page with no title, no AI provider — leaves a link note that still
  /// opens. The two halves are independent, so a page that reads fine but
  /// cannot be summarised still gets its title.
  Future<void> _readLink(String noteId, String url) async {
    final reader = LinkReader();
    LinkPreview preview;
    try {
      preview = await reader.read(url);
    } finally {
      reader.close();
    }
    if (!preview.isEmpty) {
      await widget.services.setLinkMetadata(
        noteId,
        title: preview.title,
        excerpt: preview.excerpt,
      );
      if (mounted) await widget.services.refreshTimeline();
    }

    if (!_aiHeaderAvailable) return;
    // The page's own words are what gets summarised, never the URL — a bare
    // address tells a model nothing, and sending one would spend a request to
    // be told so.
    final source = [
      preview.title,
      preview.excerpt,
    ].whereType<String>().join('\n');
    if (source.trim().isEmpty) return;
    final adapter = _aiAdapter();
    try {
      final summary = await adapter.summarizeText(source);
      if (summary != null && summary.isNotEmpty) {
        await widget.services.summarizeInto(noteId, summary);
        if (mounted) await widget.services.refreshTimeline();
      }
    } catch (_) {
      // A bookmark that could not be summarised is still a bookmark.
    } finally {
      adapter.close();
    }
  }

  /// A photo from Nex's own camera panel, or from the library. The phone's
  /// camera app is the fallback when the panel cannot open a camera.
  ///
  /// From the library, several at once (docs/14-attachments.md): the first
  /// becomes the note, through the same preview as ever, and the rest go on
  /// it as attachments — one note for "these belong together", not one
  /// each.
  Future<List<XFile>> _pickPhotos(ImageSource source) async {
    if (source == ImageSource.camera) {
      final shot = await nexTakePhoto(context);
      return [?shot];
    }
    return ImagePicker().pickMultiImage();
  }

  Future<void> capturePhoto(ImageSource source) async {
    try {
      // Inside the try: this is the call that throws when the OS refuses the
      // camera or the photo library, which is the single most likely failure
      // and the one the old handler could not have caught.
      final recovered = widget.preferences.editorDrafts?.readImage('photo-new');
      final all = recovered == null ? await _pickPhotos(source) : <XFile>[];
      final picked = all.firstOrNull;
      final more = all.skip(1).toList();
      if (recovered == null && picked == null) return;
      final original = recovered ?? await picked!.readAsBytes();
      final editing =
          widget.preferences.editPhotoBeforeCapture || recovered != null;
      if (editing && widget.preferences.editorDrafts != null) {
        unawaited(
          widget.preferences.editorDrafts!.writeImage('photo-new', original),
        );
      }
      if (!mounted) return;
      // Capture goes straight to the library unless editing was requested.
      // An interrupted editing session still gets its recovery screen.
      final cropped = editing
          ? await Navigator.of(context).push<Uint8List>(
              NexPageRoute(
                builder: (_) => PhotoPreviewScreen(
                  image: original,
                  drafts: widget.preferences.editorDrafts,
                ),
              ),
            )
          : original;
      if (cropped == null) {
        for (final key in [
          'photo-new',
          'photo-new-crop',
          'photo-new-annotation',
        ]) {
          widget.preferences.editorDrafts?.clear(key);
        }
        return;
      }
      final encoded = identical(cropped, original)
          ? cropped
          : await compute(encodeEditedPhoto, (
              bytes: cropped,
              wasJpeg:
                  original.length > 2 &&
                  original[0] == 0xff &&
                  original[1] == 0xd8,
            ));
      final isPng =
          cropped.length >= 8 &&
          cropped[0] == 0x89 &&
          cropped[1] == 0x50 &&
          cropped[2] == 0x4E &&
          cropped[3] == 0x47;
      final dest = p.join(
        widget.services.mediaDir,
        'photo-${DateTime.now().microsecondsSinceEpoch}${identical(cropped, original) ? (isPng ? '.png' : (picked == null ? '.jpg' : p.extension(picked.path))) : photoExtension(encoded)}',
      );
      await File(dest).writeAsBytes(encoded, flush: true);
      final note = await widget.services.capturePhoto(
        mediaUri: dest,
        // The bytes are already in hand and a photo fits in memory, so hash
        // them here rather than re-reading the file. The share path cannot:
        // what arrives there is whatever was shared, up to a video.
        // Off the UI isolate: megabytes of pure-Dart SHA-256 (PERF-07).
        mediaHash: await compute(sha256OfBytes, encoded),
      );
      for (final key in [
        'photo-new',
        'photo-new-crop',
        'photo-new-annotation',
      ]) {
        widget.preferences.editorDrafts?.clear(key);
      }
      for (final extra in more) {
        await widget.services.attachBytes(
          note.id,
          await extra.readAsBytes(),
          kind: AttachmentKind.photo,
          extension: p.extension(extra.path).isNotEmpty
              ? p.extension(extra.path)
              : '.jpg',
        );
      }
      landedId = note.id;
      NexMetrics.shared.markCapture();
      widget.services.scheduleEnrichment(note.id);
      if (widget.preferences.haptics) HapticFeedback.lightImpact();
      await widget.services.refreshTimeline();
    } catch (error) {
      // Not `catch (_)` with one sentence. Photo capture fails for at least
      // four unrelated reasons and three of them are things the user can do
      // something about — but only if the app says which one happened.
      if (mounted) _reportCaptureFailure(CaptureFailure.of(error), source);
    }
  }

  void _reportCaptureFailure(CaptureFailure failure, ImageSource source) {
    final l10n = AppLocalizations.of(context);
    nexShowBanner(
      context,
      kind: NexBannerKind.failed,
      haptics: widget.preferences.haptics,
      message: switch (failure) {
        CaptureFailure.permission => l10n.captureFailedPermission,
        CaptureFailure.storage => l10n.captureFailedStorage,
        CaptureFailure.unreadable => l10n.captureFailedUnreadable,
        CaptureFailure.unknown => l10n.captureFailed,
      },
      actionLabel: failure == CaptureFailure.permission
          ? l10n.openSettings
          : l10n.retry,
      onAction: () => unawaited(
        failure == CaptureFailure.permission
            ? openCaptureSettings()
            : capturePhoto(source),
      ),
    );
  }

  /// Saves a finished recording as a note.
  ///
  /// The person has already tapped Keep and the sheet is gone, so a failure
  /// here has to be said out loud (DATA-05): it used to escape as an
  /// unhandled error, nothing appeared on the timeline, and the recording was
  /// swept away an hour later as an orphan. The file stays where it is, and
  /// Retry saves the same recording again.
  Future<void> _keepVoice(String recorded, int durationMs) async {
    try {
      // A recording this app made itself, so its length is bounded by how
      // long someone held the button — reading it back to hash is safe here
      // in a way it is not for a file that arrived from somewhere else.
      final bytes = await File(recorded).readAsBytes();
      final note = await widget.services.captureVoice(
        mediaUri: recorded,
        mediaHash: await compute(sha256OfBytes, bytes),
        durationMs: durationMs,
      );
      landedId = note.id;
      NexMetrics.shared.markCapture();
      widget.services.scheduleEnrichment(note.id);
      if (widget.preferences.haptics) HapticFeedback.lightImpact();
      unawaited(widget.services.refreshTimeline());
    } catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      nexShowBanner(
        context,
        kind: NexBannerKind.failed,
        haptics: widget.preferences.haptics,
        // The permission message is about the camera and photos; the
        // microphone was already granted by the time a recording exists.
        message: switch (CaptureFailure.of(error)) {
          CaptureFailure.storage => l10n.captureFailedStorage,
          CaptureFailure.unreadable => l10n.captureFailedUnreadable,
          CaptureFailure.permission ||
          CaptureFailure.unknown => l10n.captureFailed,
        },
        actionLabel: l10n.retry,
        onAction: () => unawaited(_keepVoice(recorded, durationMs)),
      );
    }
  }

  Future<void> captureFile() async {
    final picked = await OsCaptureBridge.pickFile();
    if (picked == null) return;
    await widget.osCapture?.handle({
      'type': 'shared_file',
      'path': picked.path,
      'filename': picked.filename,
      'mimeType': picked.mimeType,
    });
    NexMetrics.shared.markCapture();
  }
}
