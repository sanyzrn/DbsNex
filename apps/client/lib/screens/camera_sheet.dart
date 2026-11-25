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
import '../widgets/nex_dialog.dart';

part 'camera/camera_sheet_widgets.dart';

part 'camera/camera_sheet_views.dart';

part 'camera/camera_sheet_capture.dart';

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
  final records = video && (Platform.isAndroid || Platform.isIOS)
      ? await _chooseSystemCameraMode(context)
      : false;
  if (records == null || !context.mounted) return null;
  final picker = ImagePicker();
  final picked = records
      ? await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: NexCameraSheet.maxVideo,
        )
      : await picker.pickImage(source: ImageSource.camera);
  return picked == null ? null : NexCameraShot(picked, isVideo: records);
}

Future<bool?> _chooseSystemCameraMode(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return nexShowDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(l10n.cameraUseSystem),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(l10n.cameraShutter),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(l10n.cameraRecordVideo),
        ),
      ],
    ),
  );
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
  Future<void>? _videoStart;
  Future<void>? _videoStop;
  bool _discardVideo = false;
  bool _closingCamera = false;
  bool _suspendingCamera = false;

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

  /// setState, for the parts this sheet is split across.
  void _set(VoidCallback change) => setState(change);

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
    } else if (state == AppLifecycleState.resumed &&
        _released &&
        !_suspendingCamera &&
        !_closingCamera) {
      _released = false;
      unawaited(_open());
    }
  }

  /// Stops a recording, keeps it, then lets the camera go.

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _systemCameraAt?.cancel();
    _ticker?.cancel();
    _limit?.cancel();
    _notice?.cancel();
    _closingCamera = true;
    _discardVideo = true;
    final controller = _controller;
    unawaited(_releaseAfterVideo(controller));
    super.dispose();
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
}
