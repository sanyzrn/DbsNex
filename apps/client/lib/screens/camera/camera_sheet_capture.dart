part of '../camera_sheet.dart';

extension _NexCameraCapture on _NexCameraSheetState {
  Future<void> _open() async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    if (mounted) _set(() => _failed = false);
    // The wait is spoken: a panel that goes black for as long as the sensor
    // takes reads as broken, not busy. Six seconds in, it also offers the
    // system camera — the same way out the timeout ends in, arrived at
    // while there is still time to take it.
    _systemCameraAt?.cancel();
    if (mounted) _set(() => _offerSystemCamera = false);
    _systemCameraAt = Timer(const Duration(seconds: 6), () {
      if (!mounted || generation != _generation) return;
      if (_controller != null || _failed) return;
      _set(() => _offerSystemCamera = true);
    });
    // Not awaited: a controller whose opening never finished never finishes
    // disposing either, and the next camera should not wait on it.
    _NexCameraSheetState._release(previous);
    bool current() => mounted && generation == _generation;
    // Video needs the microphone; a still does not, and asking for it would
    // put a permission in front of a photo that never needed one.
    var silent = !widget.video;
    var controller = _controllerFor(audio: widget.video);
    try {
      // A camera held by another app can leave this waiting for good; a black
      // panel with no way forward is worse than offering the camera app.
      await controller.initialize().timeout(_openTimeout);
    } on Object {
      _NexCameraSheetState._release(controller);
      if (!widget.video) {
        if (current()) _set(() => _failed = true);
        return;
      }
      // The microphone was refused, or there is none. The camera itself may
      // still open: a silent recording is better than no recording, and the
      // panel says so.
      silent = true;
      controller = _controllerFor(audio: false);
      try {
        await controller.initialize().timeout(_openTimeout);
      } on Object {
        _NexCameraSheetState._release(controller);
        if (current()) _set(() => _failed = true);
        return;
      }
    }
    _silentVideo = silent;
    // On a phone the app is held in portrait (the manifest and
    // lockNexPhoneOrientation), so the panel is portrait and so are the
    // photos taken in it. A tablet or an unfolded foldable is not: from
    // Android 16 the system ignores a fixed orientation on large screens, and
    // a capture locked upright there would save a landscape shot sideways.
    // Left unlocked, the photo follows the way the device is held.
    if (mounted &&
        generation == _generation &&
        !nexLargeScreen(MediaQuery.sizeOf(context))) {
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on Object {
        // Not every camera can; its photos are still upright on the phone.
      }
    }
    await _NexCameraSheetState._applyFlash(controller, _lastFlash);
    if (!current()) {
      _NexCameraSheetState._release(controller);
      return;
    }
    _set(() => _controller = controller);
  }

  CameraController _controllerFor({required bool audio}) => CameraController(
    widget.cameras[_index],
    // Full size for a still in every panel, including the one that can also
    // record: `veryHigh` capped photographs at 1080p, so the day video
    // arrived every picture from the timeline's own camera dropped from the
    // sensor's twelve megapixels to two. The clip is bounded by its bitrate
    // below instead — see [nexCameraVideoBitrate] — and by the three-minute
    // ceiling, so the file stays inside the attachment limit either way.
    ResolutionPreset.max,
    enableAudio: audio,
    videoBitrate: widget.video ? nexCameraVideoBitrate : null,
    audioBitrate: widget.video && audio ? nexCameraAudioBitrate : null,
    imageFormatGroup: ImageFormatGroup.jpeg,
  );

  Future<void> _suspend(CameraController? controller) async {
    if (_suspendingCamera || _closingCamera || controller == null) return;
    _suspendingCamera = true;
    try {
      if (_startingVideo) _stopRequested = true;
      await _videoStart;
      await _stopVideo();
      if (!mounted || _closingCamera || _controller != controller) return;
      if (!controller.value.isInitialized || _released) return;
      _released = true;
      _set(() => _controller = null);
      try {
        await controller.dispose();
      } on Object {
        // The camera may already have been released by the platform.
      }
    } finally {
      _suspendingCamera = false;
      if (mounted &&
          !_closingCamera &&
          _released &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _released = false;
        unawaited(_open());
      }
    }
  }

  // Disposal cannot await, but controller ownership must outlive the start
  // and stop futures. No second stop is issued while a clip is being written.
  Future<void> _releaseAfterVideo(CameraController? controller) async {
    await _videoStart;
    await _stopVideo(deliver: false);
    _NexCameraSheetState._release(controller);
  }

  Future<void> _take() async {
    final controller = _controller;
    if (controller == null ||
        _taking ||
        _recording ||
        _startingVideo ||
        _videoStop != null ||
        _closingCamera ||
        !controller.value.isInitialized) {
      return;
    }
    _set(() {
      _taking = true;
      // A screen-flash is exactly what a photosensitive person asked the
      // system to prevent (F-05): the blink is skipped under reduce-motion.
      if (!MediaQuery.disableAnimationsOf(context)) _blink = true;
      _menuOpen = false;
    });
    // Through the global gate every other haptic answers (F-09).
    nexBump();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 90), () {
        if (mounted) _set(() => _blink = false);
      }),
    );
    try {
      final shot = await controller.takePicture();
      if (mounted &&
          !_closingCamera &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(NexCameraShot(shot));
      } else {
        await _NexCameraSheetState._discard(shot);
      }
    } on Object {
      if (mounted) _set(() => _taking = false);
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2 ||
        _taking ||
        _recording ||
        _startingVideo ||
        _videoStop != null ||
        _closingCamera) {
      return;
    }
    _set(() {
      _index = (_index + 1) % widget.cameras.length;
      _menuOpen = false;
    });
    _lastLens = widget.cameras[_index].lensDirection;
    await _open();
  }

  Future<void> _cycleFlash() async {
    if (_videoStop != null || _closingCamera) return;
    _lastFlash = switch (_lastFlash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    _set(() {});
    final controller = _controller;
    if (controller != null) {
      await _NexCameraSheetState._applyFlash(controller, _lastFlash);
    }
  }

  /// Starts a recording. Releasing the shutter before the sensor answers is
  /// remembered: the recording is stopped the moment it actually begins, so
  /// a quick hold leaves neither a video nor a stuck shutter.
  Future<void> _startVideo() {
    final pending = _videoStart;
    if (pending != null) return pending;
    final flight = _startVideoOnce().whenComplete(() => _videoStart = null);
    _videoStart = flight;
    return flight;
  }

  Future<void> _startVideoOnce() async {
    final controller = _controller;
    if (!widget.video ||
        controller == null ||
        _recording ||
        _startingVideo ||
        _videoStop != null ||
        _closingCamera ||
        _suspendingCamera ||
        _taking ||
        !controller.value.isInitialized) {
      return;
    }
    _set(() {
      _startingVideo = true;
      _stopRequested = false;
      _discardVideo = false;
      _noticeKind = null;
      _menuOpen = false;
    });
    nexBump();
    try {
      await controller.startVideoRecording();
    } on Object {
      _startingVideo = false;
      if (mounted && !_closingCamera) _sayRecordingFailed();
      return;
    }
    if (!mounted ||
        _closingCamera ||
        ModalRoute.of(context)?.isCurrent != true) {
      _startingVideo = false;
      try {
        final file = await controller.stopVideoRecording();
        await _NexCameraSheetState._discard(file);
      } on Object {
        // The platform may have already cancelled the recording.
      }
      return;
    }
    _beginTicking();
    _set(() {
      _startingVideo = false;
      _recording = true;
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
    });
    if (_stopRequested) await _stopVideo();
  }

  void _beginTicking() {
    _ticker?.cancel();
    _limit?.cancel();
    // The clock shows whole seconds, so it is redrawn once a second rather
    // than five times: every tick rebuilt the live preview and the controls
    // with it. The ceiling is a timer of its own, to the millisecond, so the
    // slower clock cannot let a clip run past three minutes.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _startedAt;
      if (!mounted || started == null) return;
      _set(() => _elapsed = DateTime.now().difference(started));
    });
    _limit = Timer(NexCameraSheet.maxVideo, () {
      if (mounted) unawaited(_stopVideo());
    });
  }

  /// Ends the recording and, when it is long enough, hands it back.
  ///
  /// A hold shorter than [NexCameraSheet.minVideo] is a slip of the thumb:
  /// its file is deleted and the panel says why in three words, so no stray
  /// second-long video lands on the timeline.
  Future<void> _stopVideo({bool deliver = true}) {
    if (!deliver) _discardVideo = true;
    final pending = _videoStop;
    if (pending != null) return pending;
    if (_startingVideo) {
      _stopRequested = true;
      return Future<void>.value();
    }
    final controller = _controller;
    if (!_recording || controller == null) return Future<void>.value();
    final flight = _finishVideo(controller).whenComplete(() {
      _videoStop = null;
      if (mounted && !_closingCamera) _set(() {});
    });
    _videoStop = flight;
    return flight;
  }

  Future<void> _finishVideo(CameraController controller) async {
    _ticker?.cancel();
    _limit?.cancel();
    final elapsed = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    _recording = false;
    _startedAt = null;
    _elapsed = Duration.zero;
    if (mounted && !_closingCamera) {
      _set(() {});
      nexBump();
    }
    XFile? file;
    try {
      file = await controller.stopVideoRecording();
    } on Object {
      if (mounted && !_closingCamera) _sayRecordingFailed();
      return;
    }
    bool canDeliver() =>
        mounted &&
        !_closingCamera &&
        !_discardVideo &&
        ModalRoute.of(context)?.isCurrent == true;
    if (!canDeliver() || elapsed < NexCameraSheet.minVideo) {
      await _NexCameraSheetState._discard(file);
      if (canDeliver()) _say(_Notice.tooShort);
      return;
    }
    // The bitrate budget keeps a full clip well inside this, so a file that
    // reaches it came from a camera that ignored the request. Better a line
    // here than a capture path silently refusing it a moment later.
    if (await _NexCameraSheetState._sizeOf(file) >
        NexCameraSheet.maxVideoBytes) {
      await _NexCameraSheetState._discard(file);
      if (canDeliver()) _say(_Notice.tooLarge);
      return;
    }
    if (mounted && canDeliver()) {
      Navigator.of(context).pop(NexCameraShot(file, isVideo: true));
    } else {
      await _NexCameraSheetState._discard(file);
    }
  }

  void _say(_Notice notice) {
    _notice?.cancel();
    _set(() => _noticeKind = notice);
    // Three seconds is enough to read four words, and the line is not a
    // dialog: it must never need dismissing.
    _notice = Timer(const Duration(seconds: 3), () {
      if (mounted) _set(() => _noticeKind = null);
    });
  }

  void _sayRecordingFailed() {
    final l10n = AppLocalizations.of(context);
    // The failure has its own words. It used to borrow the "hold a little
    // longer" line, which described the wrong thing: the hold was long
    // enough, the camera refused it.
    _say(_Notice.failed);
    // The panel says it with a line of its own; the screen reader gets the
    // same sentence once, not on a loop — in the direction the interface is
    // being read in.
    SemanticsService.sendAnnouncement(
      View.of(context),
      l10n.captureFailed,
      Directionality.of(context),
    );
  }

  /// The panel is what replaces the system camera, so it also does the one
  /// thing that camera does besides taking: choosing something already on the
  /// phone. A panel that can record takes a video, a still panel a photo —
  /// the same split the shutter itself draws.
  Future<void> _pickFromGallery() async {
    if (_taking ||
        _recording ||
        _startingVideo ||
        _videoStop != null ||
        _closingCamera) {
      return;
    }
    _set(() => _menuOpen = false);
    XFile? picked;
    try {
      final picker = ImagePicker();
      picked = widget.video
          ? await picker.pickMedia()
          : await picker.pickImage(source: ImageSource.gallery);
    } on Object {
      picked = null;
    }
    if (!mounted || picked == null) return;
    Navigator.of(context).pop(
      NexCameraShot(
        picked,
        isVideo: widget.video && _NexCameraSheetState._isVideo(picked),
      ),
    );
  }

  void _close() {
    _closingCamera = true;
    unawaited(_stopVideo(deliver: false));
    Navigator.of(context).maybePop();
  }
}
