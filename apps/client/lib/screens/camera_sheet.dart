import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;

import '../l10n/app_localizations.dart';
import '../platform/large_screen.dart';

/// Thrown by [showNexCamera] when Nex's own camera cannot be used — no camera,
/// no plugin, or the person chose the system camera instead — so the caller
/// can fall back to the system camera app.
class NexCameraUnavailable implements Exception {
  const NexCameraUnavailable();
}

/// What Nex's camera handed back: a still, or — when the panel was asked for
/// video — a recording made by holding the shutter.
class NexCameraShot {
  const NexCameraShot(this.file, {this.isVideo = false});

  final XFile file;
  final bool isVideo;
}

/// Nex's own camera: a panel that rises over the timeline with the live view,
/// a shutter, a back button and a ⋮ menu for switching camera and flash.
///
/// A tap takes a photo; when [video] is set, holding the shutter records one
/// with sound until it is let go. Returns what was taken, or null when the
/// panel was closed without anything. Throws [NexCameraUnavailable] when the
/// system camera should be used instead. [cameras] is for tests.
Future<NexCameraShot?> showNexCamera(
  BuildContext context, {
  Future<List<CameraDescription>> Function()? cameras,
  bool video = false,
}) async {
  List<CameraDescription> found;
  try {
    found = await (cameras ?? availableCameras)();
  } on Object {
    throw const NexCameraUnavailable();
  }
  if (found.isEmpty) throw const NexCameraUnavailable();
  if (!context.mounted) return null;
  // Every other signature piece gates itself on "remove animations"; the
  // camera is the one that did not (F-05). The route appears in place, and
  // the shutter haptic plus the saved-photo receipt still confirm the
  // capture — nothing informational is lost.
  final still = MediaQuery.disableAnimationsOf(context);
  final result = await Navigator.of(context).push<Object>(
    PageRouteBuilder<Object>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black38,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: still ? Duration.zero : NexMotion.enter,
      reverseTransitionDuration: still ? Duration.zero : NexMotion.exit,
      pageBuilder: (_, _, _) => NexCameraSheet(cameras: found, video: video),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: NexMotion.curve,
            reverseCurve: NexMotion.exitCurve,
          ),
        ),
        child: child,
      ),
    ),
  );
  if (result == _useSystemCamera) throw const NexCameraUnavailable();
  return result is NexCameraShot ? result : null;
}

const _useSystemCamera = #useSystemCamera;

/// A photo or recording from the camera, the way Nex takes one everywhere:
/// its own panel on a phone, the system camera app when the panel cannot open
/// one (or on a desktop). Null when nothing was taken.
///
/// [video] is off by default: the places that only ever wanted a picture (a
/// profile picture, a vault document) keep the still-only panel, and the
/// system camera they fall back to stays a photo camera.
Future<NexCameraShot?> nexTakeShot(
  BuildContext context, {
  bool video = false,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      return await showNexCamera(context, video: video);
    } on NexCameraUnavailable {
      if (!context.mounted) return null;
    }
  }
  final picker = ImagePicker();
  // The system camera records video on a phone; on a desktop it is a photo
  // camera, and asking it for a video there would fail the whole action.
  final records = video && (Platform.isAndroid || Platform.isIOS);
  final picked = records
      ? await picker.pickVideo(source: ImageSource.camera)
      : await picker.pickImage(source: ImageSource.camera);
  return picked == null ? null : NexCameraShot(picked, isVideo: records);
}

/// A photo from the camera, for the places that take only photos. The same
/// panel as [nexTakeShot], with the video gesture left out.
Future<XFile?> nexTakePhoto(BuildContext context) async =>
    (await nexTakeShot(context))?.file;

const _openTimeout = Duration(seconds: 8);

/// The recording budget, in bits per second.
///
/// The still capture stays at the sensor's full size in every panel — adding
/// video must not cost a photo its resolution, and a lower
/// `resolutionPreset` would cap both — so the clip is bounded by its bitrate
/// instead. 16 Mbit/s of video and 128 kbit/s of audio is about 363 MB for
/// the three-minute ceiling: inside the 500 MiB attachment limit with room to
/// spare, and encoded by the camera at its highest available video quality.
const nexCameraVideoBitrate = 16000000;
const nexCameraAudioBitrate = 128000;

/// The recording clock, as the panel shows it: minutes and seconds, counting
/// past an hour without wrapping.
String nexCameraClock(Duration elapsed) =>
    '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
    '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

class NexCameraSheet extends StatefulWidget {
  const NexCameraSheet({super.key, required this.cameras, this.video = false});

  final List<CameraDescription> cameras;

  /// Whether holding the shutter records a video. A panel opened for a place
  /// that takes stills has no video item, no hold and no microphone request.
  final bool video;

  /// Shorter than this and the hold was a slip of the thumb, not a video.
  static const minVideo = Duration(milliseconds: 900);

  /// The longest a hold records. A held shutter left alone stops here rather
  /// than filling the phone.
  static const maxVideo = Duration(minutes: 3);

  /// The most a clip may weigh: the same 500 MiB the attachment path streams
  /// to disk. A recording that came out bigger is discarded here, with a line
  /// that says so, rather than handed to a capture path that would refuse it
  /// without a word.
  static const maxVideoBytes = 500 * 1024 * 1024;

  /// The share of the screen's height the panel takes.
  static const heightFactor = .62;

  @override
  State<NexCameraSheet> createState() => _NexCameraSheetState();
}

/// Kept for the rest of the session, so the camera opens the way it was left.
CameraLensDirection _lastLens = CameraLensDirection.back;
FlashMode _lastFlash = FlashMode.off;

class _NexCameraSheetState extends State<NexCameraSheet>
    with WidgetsBindingObserver {
  CameraController? _controller;
  late int _index = _initialIndex();
  bool _failed = false;
  bool _released = false;
  bool _taking = false;
  bool _menuOpen = false;
  bool _blink = false;
  double _drag = 0;

  // ── video ──────────────────────────────────────────────────────────────
  bool _recording = false;
  bool _startingVideo = false;

  /// Let go before the sensor had started: stop as soon as it has.
  bool _stopRequested = false;

  /// Recording without sound — the microphone was refused, the camera was not.
  bool _silentVideo = false;

  /// The one-shot timer that ends a held recording exactly at [maxVideo].
  Timer? _limit;

  /// What the panel has to say about the last recording, until its timer
  /// clears it.
  _Notice? _noticeKind;
  DateTime? _startedAt;
  Timer? _ticker;
  Timer? _notice;
  Duration _elapsed = Duration.zero;

  /// When a wait that is still trying stops looking like a wait and starts
  /// offering the way out: most cameras are up long before this, and the
  /// ones that reach it are usually heading for the timeout.
  Timer? _systemCameraAt;
  bool _offerSystemCamera = false;

  int _initialIndex() {
    final index = widget.cameras.indexWhere(
      (camera) => camera.lensDirection == _lastLens,
    );
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  /// Which [_open] is current; an older one that finishes late steps aside.
  int _generation = 0;

  Future<void> _open() async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    if (mounted) setState(() => _failed = false);
    // The wait is spoken: a panel that goes black for as long as the sensor
    // takes reads as broken, not busy. Six seconds in, it also offers the
    // system camera — the same way out the timeout ends in, arrived at
    // while there is still time to take it.
    _systemCameraAt?.cancel();
    if (mounted) setState(() => _offerSystemCamera = false);
    _systemCameraAt = Timer(const Duration(seconds: 6), () {
      if (!mounted || generation != _generation) return;
      if (_controller != null || _failed) return;
      setState(() => _offerSystemCamera = true);
    });
    // Not awaited: a controller whose opening never finished never finishes
    // disposing either, and the next camera should not wait on it.
    _release(previous);
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
      _release(controller);
      if (!widget.video) {
        if (current()) setState(() => _failed = true);
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
        _release(controller);
        if (current()) setState(() => _failed = true);
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
    await _applyFlash(controller, _lastFlash);
    if (!current()) {
      _release(controller);
      return;
    }
    setState(() => _controller = controller);
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

  /// Lets a camera go without waiting for it, and without its failures
  /// reaching anyone: a camera that could not open often cannot close either.
  static void _release(CameraController? controller) {
    if (controller == null) return;
    controller.dispose().catchError((Object _) {});
  }

  static Future<void> _applyFlash(
    CameraController controller,
    FlashMode mode,
  ) async {
    try {
      await controller.setFlashMode(mode);
    } on Object {
      // A front camera usually has no flash; the choice is kept for the next
      // camera that does.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera is released while Nex is in the background, as Android
    // expects, and opened again on return. Only an open camera: Android's own
    // permission dialog also makes the app inactive, while it is opening.
    if (state == AppLifecycleState.inactive) {
      // One path, in this order: the recording ends *before* the camera is
      // let go. Releasing first disposed the controller under a
      // `stopVideoRecording` that was still in flight, so the clip was lost
      // exactly when it mattered most — a phone call arriving mid-recording.
      unawaited(_suspend(_controller));
    } else if (state == AppLifecycleState.resumed && _released) {
      _released = false;
      unawaited(_open());
    }
  }

  /// Stops a recording, keeps it, then lets the camera go.
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
    setState(() => _controller = null);
    _release(controller);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _systemCameraAt?.cancel();
    _ticker?.cancel();
    _limit?.cancel();
    _notice?.cancel();
    _release(_controller);
    super.dispose();
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
    setState(() {
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
        if (mounted) setState(() => _blink = false);
      }),
    );
    try {
      final shot = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(shot);
    } on Object {
      if (mounted) setState(() => _taking = false);
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    setState(() {
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
    setState(() {});
    final controller = _controller;
    if (controller != null) await _applyFlash(controller, _lastFlash);
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
    setState(() {
      _startingVideo = true;
      _stopRequested = false;
      _noticeKind = null;
      _menuOpen = false;
    });
    nexBump();
    try {
      await controller.startVideoRecording();
    } on Object {
      if (mounted) setState(() => _startingVideo = false);
      return;
    }
    if (!mounted) {
      _release(controller);
      return;
    }
    _beginTicking();
    setState(() {
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
      setState(() => _elapsed = DateTime.now().difference(started));
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
    setState(() {
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
      await _discard(file);
      if (mounted && deliver) _say(_Notice.tooShort);
      return;
    }
    // The bitrate budget keeps a full clip well inside this, so a file that
    // reaches it came from a camera that ignored the request. Better a line
    // here than a capture path silently refusing it a moment later.
    if (await _sizeOf(file) > NexCameraSheet.maxVideoBytes) {
      await _discard(file);
      if (mounted && deliver) _say(_Notice.tooLarge);
      return;
    }
    if (mounted) Navigator.of(context).pop(NexCameraShot(file, isVideo: true));
  }

  static Future<int> _sizeOf(XFile file) async {
    try {
      return await File(file.path).length();
    } on Object {
      // A file the app cannot measure is not one it should throw away.
      return 0;
    }
  }

  /// A recording the app will not show is still its own to tidy; a camera
  /// that already removed it changes nothing.
  static Future<void> _discard(XFile file) async {
    try {
      await File(file.path).delete();
    } on Object {
      // Nothing to do: the clip is gone either way.
    }
  }

  /// One line under the clock for a few seconds.
  void _say(_Notice notice) {
    _notice?.cancel();
    setState(() => _noticeKind = notice);
    // Three seconds is enough to read four words, and the line is not a
    // dialog: it must never need dismissing.
    _notice = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _noticeKind = null);
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
    setState(() => _menuOpen = false);
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
    Navigator.of(context)
        .pop(NexCameraShot(picked, isVideo: widget.video && _isVideo(picked)));
  }

  /// Whether a picked file is a recording. The picker names its temporary
  /// copy with the original extension, and a video panel is the only place
  /// the answer can change anything.
  static bool _isVideo(XFile file) {
    final path = file.path.toLowerCase();
    return const [
      '.mp4',
      '.mov',
      '.m4v',
      '.3gp',
      '.3gpp',
      '.webm',
      '.mkv',
      '.avi',
    ].any(path.endsWith);
  }

  /// Closes the panel. A recording in flight is stopped and thrown away: the
  /// person closed the camera, not a video they wanted to keep.
  void _close() {
    if (_recording || _startingVideo) {
      unawaited(_stopVideo(deliver: false));
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height * NexCameraSheet.heightFactor;
    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        // Pulled down far or fast enough, it goes; otherwise it springs back.
        onVerticalDragUpdate: (details) =>
            setState(() => _drag = (_drag + details.delta.dy).clamp(0, height)),
        onVerticalDragEnd: (details) {
          if (_drag > height * .25 ||
              details.velocity.pixelsPerSecond.dy > 700) {
            _close();
          } else {
            setState(() => _drag = 0);
          }
        },
        child: AnimatedContainer(
          duration: _drag == 0
              ? NexMotion.of(context, NexMotion.standard)
              : Duration.zero,
          curve: NexMotion.curve,
          transform: Matrix4.translationValues(0, _drag, 0),
          height: height,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(NexRadius.xl),
            ),
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _preview(context),
                  AnimatedOpacity(
                    opacity: _blink ? .85 : 0,
                    duration: const Duration(milliseconds: 90),
                    child: const IgnorePointer(
                      child: ColoredBox(color: Colors.white),
                    ),
                  ),
                  if (widget.video) _videoStatus(context, media),
                  if (_failed) _unavailable(context),
                  if (_menuOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _menuOpen = false),
                      ),
                    ),
                  _controls(context, media.viewPadding.bottom),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The line at the top of the panel: the gesture the first time, and while
  /// recording the clock and the red dot — the two things a person needs to
  /// know it is running and for how long.
  Widget _videoStatus(BuildContext context, MediaQueryData media) {
    final l10n = AppLocalizations.of(context);
    final recording = _recording || _startingVideo;
    final clock = nexDigits(
      nexCameraClock(_elapsed),
      persian: l10n.localeName == 'fa',
    );
    final note = switch (_noticeKind) {
      _Notice.tooShort => l10n.cameraVideoTooShort,
      _Notice.tooLarge => l10n.cameraVideoTooLarge,
      _Notice.failed => l10n.captureFailed,
      null => _silentVideo ? l10n.cameraSilentVideo : null,
    };
    return Positioned(
      left: NexSpacing.md,
      right: NexSpacing.md,
      top: media.viewPadding.top + NexSpacing.sm,
      child: IgnorePointer(
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: NexMotion.of(context, NexMotion.fast),
              child: recording
                  ? Semantics(
                      key: const ValueKey('camera-recording-clock'),
                      liveRegion: true,
                      label: l10n.cameraRecordingElapsed(clock),
                      excludeSemantics: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.sm,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(NexRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _RecordingDot(),
                            const SizedBox(width: NexSpacing.xs),
                            Text(
                              clock,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            if (_silentVideo) ...[
                              const SizedBox(width: NexSpacing.xs),
                              const Icon(
                                Icons.mic_off_outlined,
                                color: Colors.white70,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : Text(
                      note ?? l10n.cameraHoldForVideo,
                      key: ValueKey(note == null ? 'hint' : 'note'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: note == null ? .6 : .9,
                        ),
                        fontSize: 13,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      // Not reached when the camera has failed: [_unavailable] takes the
      // panel then. This is the wait — faint, and saying so.
      return _failed ? const SizedBox.expand() : _waiting(context);
    }
    // previewSize is in the sensor's landscape terms. On a phone the panel is
    // portrait; on a large screen it is whichever way the device is held.
    final size = controller.value.previewSize;
    final landscape =
        nexLargeScreen(MediaQuery.sizeOf(context)) &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final long = size?.width ?? 4;
    final short = size?.height ?? 3;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: landscape ? long : short,
          height: landscape ? short : long,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  /// The panel while the sensor is still being asked for: a skeleton in
  /// its own dimness and the words, in the same voice the microphone
  /// permission speaks in. Six seconds in, the system camera is offered
  /// here rather than only after the timeout has already eaten the wait.
  Widget _waiting(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.xl,
        NexSpacing.xl,
        NexSpacing.xl,
        120,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_camera_outlined,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 40,
                ),
                const SizedBox(height: NexSpacing.md),
                // The skeleton: the panel's own shape, ghosted, where the picture
                // is about to be.
                Container(
                  width: 132,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(NexRadius.md),
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                Text(
                  l10n.cameraStarting,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                if (_offerSystemCamera) ...[
                  const SizedBox(height: NexSpacing.md),
                  FilledButton.tonal(
                    onPressed: () =>
                        Navigator.of(context).pop(_useSystemCamera),
                    child: Text(l10n.cameraUseSystem),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _unavailable(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.xl,
        NexSpacing.xl,
        NexSpacing.xl,
        120,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white70,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.cameraUnavailable,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: NexSpacing.md),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(_useSystemCamera),
            child: Text(l10n.cameraUseSystem),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, double bottomInset) {
    final l10n = AppLocalizations.of(context);
    return Positioned.fill(
      left: 20,
      right: 20,
      bottom: bottomInset + 20,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RoundButton(
                tooltip: l10n.cameraClose,
                onPressed: _close,
                // chevron_left mirrors itself under RTL; swapping it here
                // as well flipped it twice (LOC-10).
                child: const Icon(Icons.chevron_left, size: 28),
              ),
              _Shutter(
                label: _recording
                    ? l10n.cameraStopRecording
                    : l10n.cameraShutter,
                holdLabel: widget.video ? l10n.cameraHoldForVideo : null,
                enabled: _controller != null && !_taking,
                recording: _recording || _startingVideo,
                onPressed: _recording ? () => unawaited(_stopVideo()) : _take,
                onHoldStart: widget.video
                    ? () => unawaited(_startVideo())
                    : null,
                onHoldEnd: widget.video ? () => unawaited(_stopVideo()) : null,
              ),
              if (_recording || _startingVideo)
                // While recording the only choice that matters is the one
                // that stops it, and it is here as well as on the shutter so
                // the gesture is not the only way.
                _RoundButton(
                  tooltip: l10n.cameraStopRecording,
                  onPressed: () => unawaited(_stopVideo()),
                  child: const Icon(Icons.stop_rounded),
                )
              else
                _RoundButton(
                  tooltip: l10n.cameraOptions,
                  onPressed: () => setState(() => _menuOpen = !_menuOpen),
                  child: const Icon(Icons.more_vert),
                ),
            ],
          ),
          // Above the ⋮ button it belongs to.
          PositionedDirectional(
            end: 0,
            bottom: 90,
            child: IgnorePointer(
              ignoring: !_menuOpen,
              child: AnimatedScale(
                scale: _menuOpen ? 1 : .8,
                alignment: Directionality.of(context) == TextDirection.rtl
                    ? Alignment.bottomLeft
                    : Alignment.bottomRight,
                duration: NexMotion.of(context, NexMotion.standard),
                curve: NexMotion.curve,
                child: AnimatedOpacity(
                  opacity: _menuOpen ? 1 : 0,
                  duration: NexMotion.of(context, NexMotion.fast),
                  child: _Menu(
                    children: [
                      _MenuItem(
                        icon: Icons.photo_library_outlined,
                        label: l10n.cameraGallery,
                        onTap: () => unawaited(_pickFromGallery()),
                      ),
                      if (widget.video && _controller != null)
                        _MenuItem(
                          icon: Icons.videocam_outlined,
                          label: l10n.cameraRecordVideo,
                          onTap: () {
                            setState(() => _menuOpen = false);
                            unawaited(_startVideo());
                          },
                        ),
                      if (widget.cameras.length > 1)
                        _MenuItem(
                          icon: Icons.cameraswitch_outlined,
                          label: l10n.cameraSwitch,
                          onTap: _switchCamera,
                        ),
                      _MenuItem(
                        icon: switch (_lastFlash) {
                          FlashMode.auto => Icons.flash_auto,
                          FlashMode.always => Icons.flash_on,
                          _ => Icons.flash_off,
                        },
                        label: switch (_lastFlash) {
                          FlashMode.auto => l10n.cameraFlashAuto,
                          FlashMode.always => l10n.cameraFlashOn,
                          _ => l10n.cameraFlashOff,
                        },
                        onTap: _cycleFlash,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.black.withValues(alpha: .45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 48,
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
}

class _Shutter extends StatefulWidget {
  const _Shutter({
    required this.label,
    required this.holdLabel,
    required this.enabled,
    required this.recording,
    required this.onPressed,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final String label;

  /// Said to a screen reader, and shown under the dial: what a hold does.
  final String? holdLabel;

  final bool enabled;
  final bool recording;
  final VoidCallback onPressed;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  /// How long the finger rests before the hold becomes a recording. Short
  /// enough to feel like a hold, long enough that a tap is never one.
  static const holdAfter = Duration(milliseconds: 280);

  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> {
  bool _down = false;
  bool _holding = false;
  Timer? _hold;
  Offset? _origin;

  void _press(PointerDownEvent event) {
    if (!widget.enabled) return;
    _origin = event.position;
    setState(() => _down = true);
    if (widget.onHoldStart == null) return;
    _hold = Timer(_Shutter.holdAfter, () {
      if (!mounted) return;
      _holding = true;
      widget.onHoldStart!();
    });
  }

  void _lift(PointerUpEvent event) {
    _hold?.cancel();
    _hold = null;
    if (!_down) return;
    setState(() => _down = false);
    if (_holding) {
      _holding = false;
      widget.onHoldEnd?.call();
      return;
    }
    // Moved off the dial before lifting: not a tap.
    final origin = _origin;
    if (origin != null && (event.position - origin).distance > 24) return;
    if (widget.enabled) widget.onPressed();
  }

  void _cancel(PointerCancelEvent event) {
    _hold?.cancel();
    _hold = null;
    if (!_down) return;
    setState(() => _down = false);
    if (_holding) {
      _holding = false;
      widget.onHoldEnd?.call();
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled,
    label: widget.label,
    hint: widget.holdLabel,
    child: Listener(
      onPointerDown: _press,
      onPointerUp: _lift,
      onPointerCancel: _cancel,
      child: AnimatedScale(
        scale: _down ? .9 : 1,
        duration: NexMotion.of(context, NexMotion.fast),
        child: Container(
          width: 78,
          height: 78,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: .55),
            border: widget.recording
                ? Border.all(color: const Color(0xFFE5484D), width: 3)
                : null,
          ),
          child: AnimatedContainer(
            duration: NexMotion.of(context, NexMotion.fast),
            decoration: BoxDecoration(
              shape: widget.recording ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: widget.recording
                  ? BorderRadius.circular(NexRadius.sm)
                  : null,
              color: !widget.enabled
                  ? Colors.white54
                  : widget.recording
                  ? const Color(0xFFE5484D)
                  : Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The red dot beside the clock. Still under reduce-motion.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: .35, end: 1).animate(_controller),
    child: Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFFE5484D),
        shape: BoxShape.circle,
      ),
    ),
  );
}

class _Menu extends StatelessWidget {
  const _Menu({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .72),
    borderRadius: BorderRadius.circular(NexRadius.lg),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// What the panel has to say about the last recording.
enum _Notice { tooShort, tooLarge, failed }

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.md,
        vertical: 12,
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    ),
  );
}
