import 'dart:async';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../utils/image_editing.dart';

/// How long a photo's long edge may be when it reaches the library.
///
/// Camera sensors now outgrow what any screen in this app can show, and the
/// timeline thumbnail, the full-screen viewer and every re-encode are all
/// cheaper on a 3200px image — visually indistinguishable at phone scale from
/// the 48-megapixel original, at a fraction of the storage. The cap is applied
/// once, up front, so the editor itself also works on a smaller image.
const nexPhotoMaxLongEdge = 3200;

/// The edit step shown right after a photo is taken or picked, before it is
/// ever written to disk.
///
/// Returns the edited bytes, or `null` if the user backs out — which discards
/// the whole capture, not just the edits, matching the camera-app convention
/// this follows: the X abandons the photo, the checkmark commits and moves on.
///
/// Beyond the crop rect the old screen offered, this is a real editor:
///
/// * **Free or preset aspect ratios** — original, 1:1, 4:3, 3:4, 16:9, 9:16 —
///   switched live without losing the photo.
/// * **Rotate** left/right and **flip** horizontally/vertically, applied to
///   the actual pixels on a background isolate so the UI never stalls.
/// * **Pinch zoom and pan** over the image while framing the crop.
/// * **A rule-of-thirds grid** and generous corner handles.
/// * **Reset** back to the photo as it arrived.
///
/// Every byte-level transform runs through `compute()`; the original input is
/// never modified, and the final result is re-encoded for storage (JPEG for
/// photographic input, PNG preserved) with the long edge capped at
/// [nexPhotoMaxLongEdge].
class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({
    super.key,
    required this.image,
    this.haptics = true,
  });

  final Uint8List image;

  /// Whether tool taps should tick. The timeline's haptics preference.
  final bool haptics;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

enum _AspectPreset {
  free,
  original,
  square,
  r4_3,
  r3_4,
  r16_9,
  r9_16,
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  final _controller = CropController();

  /// The bytes the editor is currently showing. Replaced by every transform.
  Uint8List _bytes = Uint8List(0);

  /// The loaded photo, normalized (EXIF baked, long edge capped) — what
  /// Reset returns to.
  Uint8List? _original;

  late NexImageInfo _info = const NexImageInfo(
    width: null,
    height: null,
    format: NexImageFormat.other,
  );

  /// The encoding of the photo as it arrived; decides the final file format.
  NexImageFormat _sourceFormat = NexImageFormat.other;

  _AspectPreset _preset = _AspectPreset.free;

  /// Anything at all changed since the photo arrived — a transform, a preset,
  /// or a moved crop rect. When nothing changed, confirming returns the
  /// loaded bytes untouched instead of pushing them through a lossy round
  /// trip it does not need.
  bool _dirty = false;

  /// Whether the crop rect still covers the whole frame. Reset on every
  /// [Crop] status change; [Crop.onMoved] keeps it honest while the user
  /// drags.
  bool _cropCoversFull = true;

  bool _busy = false;
  bool _cropping = false;
  CropStatus _status = CropStatus.nothing;

  @override
  void initState() {
    super.initState();
    _bytes = widget.image;
    _info = nexImageInfo(widget.image);
    _sourceFormat = _info.format;
    unawaited(_normalize());
  }

  /// Bakes EXIF orientation and applies the long-edge cap before the editor
  /// opens. This is what [Reset] restores.
  Future<void> _normalize() async {
    setState(() => _busy = true);
    try {
      final normalized = await compute(
        nexTransformImageRequest,
        NexTransformRequest(
          bytes: widget.image,
          maxLongEdge: nexPhotoMaxLongEdge,
        ),
      );
      if (!mounted) return;
      setState(() {
        _bytes = normalized;
        _original = normalized;
        _info = nexImageInfo(normalized);
        _busy = false;
      });
    } catch (_) {
      // A photo that cannot be decoded is not something the editor can
      // recover: fall back to showing the raw bytes and let the crop step
      // report its own failure honestly.
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tick() {
    if (widget.haptics) HapticFeedback.selectionClick();
  }

  /// The fixed ratio the current preset demands, or null when the crop rect
  /// is free-form.
  double? get _presetRatio {
    final info = _info;
    return switch (_preset) {
      _AspectPreset.free => null,
      _AspectPreset.original =>
        (info.width != null && info.height != null && info.height! > 0)
            ? info.width! / info.height!
            : null,
      _AspectPreset.square => 1,
      _AspectPreset.r4_3 => 4 / 3,
      _AspectPreset.r3_4 => 3 / 4,
      _AspectPreset.r16_9 => 16 / 9,
      _AspectPreset.r9_16 => 9 / 16,
    };
  }

  Future<void> _applyTransform({
    int quarterTurns = 0,
    bool flipHorizontal = false,
    bool flipVertical = false,
  }) async {
    if (_busy || _cropping) return;
    _tick();
    setState(() => _busy = true);
    try {
      final transformed = await compute(
        nexTransformImageRequest,
        NexTransformRequest(
          bytes: _bytes,
          quarterTurns: quarterTurns,
          flipHorizontal: flipHorizontal,
          flipVertical: flipVertical,
          maxLongEdge: nexPhotoMaxLongEdge,
        ),
      );
      if (!mounted) return;
      setState(() {
        _bytes = transformed;
        _info = nexImageInfo(transformed);
        _dirty = true;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    final original = _original;
    if (original == null || !_dirty || _busy) return;
    _tick();
    setState(() {
      _bytes = original;
      _info = nexImageInfo(original);
      _preset = _AspectPreset.free;
      _dirty = false;
    });
  }

  Future<void> _pickPreset() async {
    if (_busy || _cropping) return;
    final l10n = AppLocalizations.of(context);
    final chosen = await showModalBottomSheet<_AspectPreset>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.lg,
                NexSpacing.xs,
                NexSpacing.lg,
                NexSpacing.sm,
              ),
              child: Text(
                l10n.photoEditorAspect,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final preset in _AspectPreset.values)
              ListTile(
                leading: _AspectGlyph(preset: preset),
                title: Text(_presetLabel(l10n, preset)),
                trailing: preset == _preset
                    ? const Icon(Icons.check)
                    : null,
                selected: preset == _preset,
                onTap: () => Navigator.pop(ctx, preset),
              ),
            const SizedBox(height: NexSpacing.sm),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted || chosen == _preset) return;
    _tick();
    setState(() {
      _preset = chosen;
      _dirty = true;
    });
    _controller.aspectRatio = _presetRatio;
  }

  String _presetLabel(AppLocalizations l10n, _AspectPreset preset) =>
      switch (preset) {
        _AspectPreset.free => l10n.photoEditorFree,
        _AspectPreset.original => l10n.photoEditorOriginal,
        _AspectPreset.square => l10n.photoEditorSquare,
        _AspectPreset.r4_3 => '4:3',
        _AspectPreset.r3_4 => '3:4',
        _AspectPreset.r16_9 => '16:9',
        _AspectPreset.r9_16 => '9:16',
      };

  void _confirm() {
    if (_busy || _cropping || _status != CropStatus.ready) return;
    // Nothing was touched: the normalized bytes are already exactly what the
    // library should store. Skipping the crop pass avoids a needless
    // PNG-encode → decode → JPEG-encode round trip on the common "just use
    // the photo" path.
    if (!_dirty && _cropCoversFull) {
      Navigator.of(context).pop(_bytes);
      return;
    }
    setState(() => _cropping = true);
    _controller.crop();
  }

  /// Whether [rect] — a crop rect in image pixel coordinates — covers the
  /// whole photo. Used to skip the crop pass when nothing was framed.
  bool _isFullFrame(Rect rect) {
    final info = _info;
    if (info.width == null || info.height == null) return false;
    const eps = 1.0;
    return (rect.left - 0).abs() < eps &&
        (rect.top - 0).abs() < eps &&
        (rect.right - info.width!).abs() < eps &&
        (rect.bottom - info.height!).abs() < eps;
  }

  Future<void> _onCropped(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        if (!mounted) return;
        setState(() => _busy = true);
        try {
          final finalBytes = await compute(
            nexEncodeRequest,
            NexEncodeRequest(
              bytes: croppedImage,
              sourceFormat: _sourceFormat,
              maxLongEdge: nexPhotoMaxLongEdge,
            ),
          );
          if (mounted) Navigator.of(context).pop(finalBytes);
        } catch (_) {
          if (mounted) {
            setState(() {
              _busy = false;
              _cropping = false;
            });
            _toast(AppLocalizations.of(context).captureFailed);
          }
        }
      case CropFailure():
        if (!mounted) return;
        setState(() {
          _busy = false;
          _cropping = false;
        });
        _toast(AppLocalizations.of(context).captureFailed);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The crop view parses its image in a background isolate; until it is
    // ready there is nothing to frame, and the transform tools would only
    // pile work onto a view that cannot show it yet.
    final ready = _status == CropStatus.ready;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.photoEditorTitle),
        leading: IconButton(
          tooltip: l10n.cropCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: l10n.cropConfirm,
            icon: _cropping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            onPressed: _cropping || !ready ? null : _confirm,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // Keyed on the bytes: every transform is a new image, and a
                // fresh Crop (fresh frame, fresh rect) is exactly the editor
                // behaviour a rotation should have. The aspect ratio is
                // passed along so the fresh frame starts framed for whatever
                // preset is active; live preset changes go through the
                // controller instead, which resizes the rect in place.
                Crop(
                  key: ValueKey(_bytes),
                  image: _bytes,
                  controller: _controller,
                  aspectRatio: _presetRatio,
                  onCropped: _onCropped,
                  onStatusChanged: (status) {
                    if (mounted) setState(() => _status = status);
                  },
                  // Free starts on the whole photo, not a centered square.
                  initialRectBuilder:
                      _preset == _AspectPreset.free &&
                          _presetRatio == null
                      ? InitialRectBuilder.withBuilder((viewport, image) {
                          return image;
                        })
                      : null,
                  // `rectToCrop` arrives in image pixel coordinates, so the
                  // whole-frame check compares it against the photo's own
                  // dimensions.
                  onMoved: (viewportRect, rectToCrop) {
                    if (!mounted) return;
                    final full = _isFullFrame(rectToCrop);
                    if (full != _cropCoversFull) {
                      setState(() => _cropCoversFull = full);
                    }
                  },
                  baseColor: Colors.black,
                  maskColor: Colors.black.withValues(alpha: 0.65),
                  radius: NexRadius.sm,
                  cornerDotBuilder: (size, edgeAlignment) => _CornerDot(
                    size: size,
                    alignment: edgeAlignment,
                  ),
                  overlayBuilder: (context, rect) => CustomPaint(
                    size: rect.size,
                    painter: const _ThirdsGridPainter(),
                  ),
                ),
                if (_busy)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _EditorToolbar(
            preset: _preset,
            dirty: _dirty,
            busy: _busy || _cropping || !ready,
            onAspect: () => unawaited(_pickPreset()),
            onRotateLeft: () => unawaited(
              _applyTransform(quarterTurns: -1),
            ),
            onRotateRight: () => unawaited(
              _applyTransform(quarterTurns: 1),
            ),
            onFlipHorizontal: () =>
                unawaited(_applyTransform(flipHorizontal: true)),
            onFlipVertical: () => unawaited(_applyTransform(flipVertical: true)),
            onReset: _reset,
          ),
        ],
      ),
    );
  }
}

/// The editor's bottom controls, on black.
class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.preset,
    required this.dirty,
    required this.busy,
    required this.onAspect,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
    required this.onReset,
  });

  final _AspectPreset preset;
  final bool dirty;
  final bool busy;
  final VoidCallback onAspect;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onFlipHorizontal;
  final VoidCallback onFlipVertical;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
          child: Row(
            children: [
              _ToolButton(
                label: l10n.photoEditorAspect,
                active: preset != _AspectPreset.free,
                onTap: busy ? null : onAspect,
                child: const Icon(Icons.aspect_ratio, size: 22),
              ),
              _ToolButton(
                label: l10n.photoEditorRotate,
                onTap: busy ? null : onRotateLeft,
                child: const Icon(Icons.rotate_left, size: 24),
              ),
              _ToolButton(
                label: l10n.photoEditorRotate,
                onTap: busy ? null : onRotateRight,
                child: const Icon(Icons.rotate_right, size: 24),
              ),
              _ToolButton(
                label: l10n.photoEditorFlip,
                onTap: busy ? null : onFlipHorizontal,
                child: const Icon(Icons.flip, size: 22),
              ),
              _ToolButton(
                label: l10n.photoEditorFlipVertical,
                onTap: busy ? null : onFlipVertical,
                child: Transform.rotate(
                  angle: 1.5708,
                  child: const Icon(Icons.flip, size: 22),
                ),
              ),
              _ToolButton(
                label: l10n.photoEditorReset,
                enabled: dirty && !busy,
                onTap: onReset,
                child: const Icon(Icons.restart_alt, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labelled tool in the editor toolbar. Labels sit under the icon so the
/// tool reads at a glance; the whole cell is a 48px+ target.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.onTap,
    required this.child,
    this.active = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool active;

  /// Distinct from [onTap] being null: disabled-but-tappable-looking.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Colors.white38
        : active
        ? const Color(0xFF93C5FD)
        : Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        child: SizedBox(
          width: 64,
          height: nexMinTapTarget + 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(data: IconThemeData(color: color), child: child),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A corner handle: a filled dot inside a hairline ring, drawn on black.
class _CornerDot extends StatelessWidget {
  const _CornerDot({required this.size, required this.alignment});

  final double size;
  final EdgeAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 1.5),
      ),
    );
    return switch (alignment) {
      EdgeAlignment.topLeft => Align(
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: const Offset(-size / 2, -size / 2),
            child: dot,
          ),
        ),
      EdgeAlignment.topRight => Align(
          alignment: Alignment.topRight,
          child: Transform.translate(
            offset: const Offset(size / 2, -size / 2),
            child: dot,
          ),
        ),
      EdgeAlignment.bottomLeft => Align(
          alignment: Alignment.bottomLeft,
          child: Transform.translate(
            offset: const Offset(-size / 2, size / 2),
            child: dot,
          ),
        ),
      EdgeAlignment.bottomRight => Align(
          alignment: Alignment.bottomRight,
          child: Transform.translate(
            offset: const Offset(size / 2, size / 2),
            child: dot,
          ),
        ),
    };
  }
}

/// The rule-of-thirds grid inside the crop area.
class _ThirdsGridPainter extends CustomPainter {
  const _ThirdsGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ThirdsGridPainter oldDelegate) => false;
}

/// The little frame each aspect preset is shown with in the picker.
class _AspectGlyph extends StatelessWidget {
  const _AspectGlyph({required this.preset});

  final _AspectPreset preset;

  @override
  Widget build(BuildContext context) {
    final (width, height) = switch (preset) {
      _AspectPreset.free => (18.0, 14.0),
      _AspectPreset.original => (18.0, 12.0),
      _AspectPreset.square => (16.0, 16.0),
      _AspectPreset.r4_3 => (18.0, 13.5),
      _AspectPreset.r3_4 => (13.5, 18.0),
      _AspectPreset.r16_9 => (18.0, 10.1),
      _AspectPreset.r9_16 => (10.1, 18.0),
    };
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            width: 1.6,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
