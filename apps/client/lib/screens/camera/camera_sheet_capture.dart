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
    if (_recording) {
      await _stopVideo();
    } else if (_startingVideo) {
      // The sensor has not answered yet; stop the instant it does. Releasing
      // the controller now would fail that start anyway, and this way the
      // panel is never left with a shutter that thinks it is recording.
      _stopRequested = true;
    }
    if (!mounted || controller == null || _controller != controller) return;
    if (!controller.value.isInitialized || _released) return;
    _released = true;
    _set(() => _controller = null);
    _NexCameraSheetState._release(controller);
  }

  Future<void> _take() async {
    final controller = _controller;
    if (controller == null ||
        _taking ||
        _recording ||
        _startingVideo ||
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
      if (mounted) Navigator.of(context).pop(shot);
    } on Object {
      if (mounted) _set(() => _taking = false);
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    _set(() {
      _index = (_index + 1) % widget.cameras.length;
      _menuOpen = false;
    });
    _lastLens = widget.cameras[_index].lensDirection;
    await _open();
  }

  Future<void> _cycleFlash() async {
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
  Future<void> _startVideo() async {
    final controller = _controller;
    if (!widget.video ||
        controller == null ||
        _recording ||
        _startingVideo ||
        _taking ||
        !controller.value.isInitialized) {
      return;
    }
    _set(() {
      _startingVideo = true;
      _stopRequested = false;
      _noticeKind = null;
      _menuOpen = false;
    });
    nexBump();
    try {
      await controller.startVideoRecording();
    } on Object {
      if (mounted) _set(() => _startingVideo = false);
      return;
    }
    if (!mounted) {
      _NexCameraSheetState._release(controller);
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
  Future<void> _stopVideo({bool deliver = true}) async {
    if (_startingVideo) {
      _stopRequested = true;
      return;
    }
    final controller = _controller;
    if (!_recording || controller == null) return;
    _ticker?.cancel();
    _limit?.cancel();
    final elapsed = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    _set(() {
      _recording = false;
      _startedAt = null;
      _elapsed = Duration.zero;
    });
    nexBump();
    XFile? file;
    try {
      file = await controller.stopVideoRecording();
    } on Object {
      if (mounted) _sayRecordingFailed();
      return;
    }
    if (!deliver || elapsed < NexCameraSheet.minVideo) {
      await _NexCameraSheetState._discard(file);
      if (mounted && deliver) _say(_Notice.tooShort);
      return;
    }
    // The bitrate budget keeps a full clip well inside this, so a file that
    // reaches it came from a camera that ignored the request. Better a line
    // here than a capture path silently refusing it a moment later.
    if (await _NexCameraSheetState._sizeOf(file) >
        NexCameraSheet.maxVideoBytes) {
      await _NexCameraSheetState._discard(file);
      if (mounted && deliver) _say(_Notice.tooLarge);
      return;
    }
    if (mounted) Navigator.of(context).pop(NexCameraShot(file, isVideo: true));
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
    if (_taking || _recording || _startingVideo) return;
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
    if (_recording || _startingVideo) {
      unawaited(_stopVideo(deliver: false));
    }
    Navigator.of(context).maybePop();
  }
}
