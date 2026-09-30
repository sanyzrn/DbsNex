import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Thrown by [showNexCamera] when Nex's own camera cannot be used — no camera,
/// no plugin, or the person chose the system camera instead — so the caller
/// can fall back to the system camera app.
class NexCameraUnavailable implements Exception {
  const NexCameraUnavailable();
}

/// Nex's own camera: a panel that rises over the timeline with the live view,
/// a shutter, a back button and a ⋮ menu for switching camera and flash.
///
/// Returns the photo taken, or null when the panel was closed without one.
/// Throws [NexCameraUnavailable] when the system camera should be used
/// instead. [cameras] is for tests.
Future<XFile?> showNexCamera(
  BuildContext context, {
  Future<List<CameraDescription>> Function()? cameras,
}) async {
  List<CameraDescription> found;
  try {
    found = await (cameras ?? availableCameras)();
  } on Object {
    throw const NexCameraUnavailable();
  }
  if (found.isEmpty) throw const NexCameraUnavailable();
  if (!context.mounted) return null;
  final result = await Navigator.of(context).push<Object>(
    PageRouteBuilder<Object>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black38,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => NexCameraSheet(cameras: found),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: child,
      ),
    ),
  );
  if (result == _useSystemCamera) throw const NexCameraUnavailable();
  return result is XFile ? result : null;
}

const _useSystemCamera = #useSystemCamera;

const _openTimeout = Duration(seconds: 8);

class NexCameraSheet extends StatefulWidget {
  const NexCameraSheet({super.key, required this.cameras});

  final List<CameraDescription> cameras;

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
    // Not awaited: a controller whose opening never finished never finishes
    // disposing either, and the next camera should not wait on it.
    _release(previous);
    final controller = CameraController(
      widget.cameras[_index],
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    bool current() => mounted && generation == _generation;
    try {
      // A camera held by another app can leave this waiting for good; a black
      // panel with no way forward is worse than offering the camera app.
      await controller.initialize().timeout(_openTimeout);
    } on Object {
      _release(controller);
      if (current()) setState(() => _failed = true);
      return;
    }
    try {
      // The panel is portrait, and so are the photos taken in it.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } on Object {
      // Not every camera can; its photos are still upright on the phone.
    }
    await _applyFlash(controller, _lastFlash);
    if (!current()) {
      _release(controller);
      return;
    }
    setState(() => _controller = controller);
  }

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
    final controller = _controller;
    if (state == AppLifecycleState.inactive &&
        controller != null &&
        controller.value.isInitialized) {
      _released = true;
      setState(() => _controller = null);
      _release(controller);
    } else if (state == AppLifecycleState.resumed && _released) {
      _released = false;
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release(_controller);
    super.dispose();
  }

  Future<void> _take() async {
    final controller = _controller;
    if (controller == null || _taking || !controller.value.isInitialized) {
      return;
    }
    setState(() {
      _taking = true;
      _blink = true;
      _menuOpen = false;
    });
    unawaited(HapticFeedback.lightImpact());
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

  void _close() => Navigator.of(context).maybePop();

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
              ? const Duration(milliseconds: 200)
              : Duration.zero,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _drag, 0),
          height: height,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _preview(),
                  AnimatedOpacity(
                    opacity: _blink ? .85 : 0,
                    duration: const Duration(milliseconds: 90),
                    child: const IgnorePointer(
                      child: ColoredBox(color: Colors.white),
                    ),
                  ),
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

  Widget _preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }
    // previewSize is in the sensor's landscape terms; the panel is portrait.
    final size = controller.value.previewSize;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size?.height ?? 3,
          height: size?.width ?? 4,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _unavailable(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 120),
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
          const SizedBox(height: 16),
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
    final rtl = Directionality.of(context) == TextDirection.rtl;
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
                child: Icon(
                  rtl ? Icons.chevron_right : Icons.chevron_left,
                  size: 28,
                ),
              ),
              _Shutter(
                label: l10n.cameraShutter,
                enabled: _controller != null && !_taking,
                onPressed: _take,
              ),
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
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _menuOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: _Menu(
                    children: [
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
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.enabled,
    label: widget.label,
    child: GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _down ? .9 : 1,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 78,
          height: 78,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: .55),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.enabled ? Colors.white : Colors.white54,
            ),
          ),
        ),
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
    borderRadius: BorderRadius.circular(20),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
