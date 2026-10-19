import '../platform/crash_reporter.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/editor_drafts.dart';
import '../platform/photo_encoding.dart';
import '../widgets/draft_guard.dart';
import '../widgets/nex_banner.dart';
import '../widgets/photo_editor_theme.dart';
import 'photo_annotate_screen.dart';

/// Crop step shown right after a photo is taken or picked, before it is ever
/// written to disk.
///
/// Returns the cropped bytes, or `null` if the user backs out — which
/// discards the whole capture, not just the crop, matching the camera-app
/// convention this follows: the X abandons the photo, the checkmark commits
/// the crop and moves on.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({
    super.key,
    required this.image,
    this.drafts,
    this.draftKey = 'photo-new',
  });

  final Uint8List image;
  final EditorDrafts? drafts;
  final String draftKey;

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen>
    with NexDraftGuard<PhotoCropScreen> {
  @override
  bool get hasUnsavedChanges => _ready || _rotating || _cropping;
  final _controller = CropController();

  /// The photo as it is to be seen — upright, see [uprightPhoto] — and what
  /// every turn and flip starts from, so four turns are one re-encoding.
  /// Null until it has been read.
  Uint8List? _base;

  /// What the cropper shows: [_base] turned and flipped.
  Uint8List _current = Uint8List(0);
  int _turns = 0;
  bool _flipped = false;
  bool _cropping = false;
  bool _rotating = false;
  // False from the very first frame until `Crop`'s own async parse of
  // `_current` finishes (again after every rotation) — calling
  // `CropController.crop()` before that hits a package-internal assertion,
  // since there is nothing parsed yet to crop.
  bool _ready = false;
  // Which action asked for the crop: the checkmark returns straight to the
  // caller, the pencil detours through the (optional) annotate screen first.
  bool _pendingAnnotate = false;
  final _ratioScroll = ScrollController();
  Rect? _restoredArea;
  Rect? _area;
  String get _key => '${widget.draftKey}-crop';
  void _snapshot() => widget.drafts?.write(_key, {
    'ratio': _aspectRatio,
    'turns': _turns,
    'flipped': _flipped,
    if (_area != null)
      'area': [_area!.left, _area!.top, _area!.right, _area!.bottom],
  });
  @override
  void discardDraft() {
    widget.drafts?.clear(_key);
    widget.drafts?.clear('${widget.draftKey}-annotation');
  }

  @override
  void dispose() {
    _ratioScroll.dispose();
    super.dispose();
  }

  double? _aspectRatio;

  void _setAspectRatio(double? value) {
    if (!_ready || _cropping || _rotating) return;
    _controller.aspectRatio = value;
    setState(() => _aspectRatio = value);
    _snapshot();
  }

  void _reset() {
    final base = _base;
    if (_cropping || _rotating || base == null) return;
    setState(() {
      discardDraft();
      _restoredArea = null;
      _area = null;
      _turns = 0;
      _flipped = false;
      _current = base;
      _aspectRatio = null;
      _ready = false;
    });
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.drafts?.read(_key);
    _aspectRatio = (draft?['ratio'] as num?)?.toDouble();
    _turns = (draft?['turns'] as num?)?.toInt() ?? 0;
    _flipped = draft?['flipped'] == true;
    final area = draft?['area'];
    if (area is List && area.length == 4) {
      _restoredArea = Rect.fromLTRB(
        (area[0] as num).toDouble(),
        (area[1] as num).toDouble(),
        (area[2] as num).toDouble(),
        (area[3] as num).toDouble(),
      );
    }
    unawaited(_prepare());
  }

  /// Reads the photo upright, off the UI thread, and picks up a turned or
  /// flipped draft where it was left.
  Future<void> _prepare() async {
    // Most photos are upright already, and their tag is in the header: the
    // cropper opens at once for those, with no trip off the UI thread.
    if (!photoNeedsUpright(widget.image) && _turns % 4 == 0 && !_flipped) {
      _base = widget.image;
      _current = widget.image;
      return;
    }
    Uint8List base;
    try {
      base = await compute(uprightPhoto, widget.image);
    } catch (_) {
      base = widget.image;
    }
    var current = base;
    if (_turns % 4 != 0 || _flipped) {
      try {
        current = await compute(transformPhoto, (
          bytes: base,
          turns: _turns,
          flip: _flipped,
        ));
      } catch (_) {
        _turns = 0;
        _flipped = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _base = base;
      _current = current;
    });
  }

  Future<void> _rotate() => _transform(turns: _turns + 1, flip: _flipped);

  Future<void> _flip() => _transform(turns: _turns, flip: !_flipped);

  Future<void> _transform({required int turns, required bool flip}) async {
    final base = _base;
    if (_rotating || _cropping || !_ready || base == null) return;
    setState(() => _rotating = true);
    Uint8List rotated;
    try {
      rotated = await compute(transformPhoto, (
        bytes: base,
        turns: turns,
        flip: flip,
      ));
    } catch (error) {
      unawaited(NexCrashLog.handled('photo.rotate', error));
      if (!mounted) return;
      setState(() => _rotating = false);
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).captureFailed,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      // A fresh key rather than `CropController.image = rotated` — the
      // in-place reset recomputes `Crop`'s internal viewport against
      // `MediaQuery.of(context).size` (the whole screen) instead of the
      // constraints its own body actually has, which left its gesture layer
      // wide enough to swallow taps on the app bar's own buttons after a
      // rotation. Remounting runs it through the exact same initial layout
      // path as the first parse, which does not have that problem.
      //
      // The remount does mean `_ready` needs resetting by hand: unlike
      // `CropController.image =`, a fresh `_CropEditorState` never announces
      // `CropStatus.loading` on its own, so without this the stale `true`
      // from the widget it is replacing would let a crop through before the
      // new instance has parsed anything at all.
      _turns = turns % 4;
      _flipped = flip;
      _restoredArea = null;
      _area = null;
      _current = rotated;
      _ready = false;
      _rotating = false;
    });
    _snapshot();
  }

  void _startCrop({required bool annotate}) {
    setState(() {
      _cropping = true;
      _pendingAnnotate = annotate;
    });
    _controller.crop();
  }

  Future<void> _onCropped(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        // In the photo's own format: a JPEG crop stays a JPEG. It used to be
        // turned into a PNG here — seconds of work on a camera photo, and a
        // file several times the size — for the save step to turn back into
        // a JPEG; the save names the file from its bytes.
        final png = croppedImage;
        if (!mounted) return;
        if (!_pendingAnnotate) {
          Navigator.of(context).pop(png);
          return;
        }
        final annotated = await Navigator.of(context).push<Uint8List>(
          NexPageRoute(
            swipeBackEnabled: false,
            builder: (_) => PhotoAnnotateScreen(
              image: png,
              drafts: widget.drafts,
              draftKey: widget.draftKey,
            ),
          ),
        );
        if (!mounted) return;
        if (annotated == null) {
          setState(() {
            // Back from drawing: the crop stays made, and it is what turns
            // and flips start from now.
            _base = png;
            _turns = 0;
            _flipped = false;
            _current = png;
            _cropping = false;
            _ready = false;
          });
        } else {
          Navigator.of(context).pop(annotated);
        }
      case CropFailure(:final cause):
        if (!mounted) return;
        setState(() => _cropping = false);
        nexShowBanner(context, message: '$cause');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = _cropping || _rotating || !_ready;
    return NexPhotoEditorTheme(
      child: guardDraft(
        Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(l10n.cropPhotoTitle),
            leading: IconButton(
              tooltip: l10n.cropCancel,
              icon: const Icon(Icons.close),
              onPressed: requestDiscard,
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.sm,
                NexSpacing.md,
                NexSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The shapes, as a row of pills that scrolls sideways on a
                  // narrow phone and sits centred on a wide one.
                  // A finger's height at least, and taller with the text: a
                  // fixed 40 was under the touch floor and clipped the
                  // labels at large text sizes.
                  SizedBox(
                    height: math.max(
                      nexMinTapTarget,
                      MediaQuery.textScalerOf(context).scale(20) +
                          NexSpacing.sm * 3,
                    ),
                    child: Center(
                      child: ListView(
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        children: [
                          _RatioOption(
                            label: l10n.cropFree,
                            selected: _aspectRatio == null,
                            onTap: busy ? null : () => _setAspectRatio(null),
                          ),
                          for (final (label, value) in const [
                            ('1:1', 1.0),
                            ('4:3', 4 / 3),
                            ('3:4', 3 / 4),
                            ('16:9', 16 / 9),
                            ('9:16', 9 / 16),
                          ])
                            _RatioOption(
                              label: label,
                              selected: _aspectRatio == value,
                              onTap: busy ? null : () => _setAspectRatio(value),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      NexPhotoTool(
                        icon: Icons.rotate_90_degrees_cw_outlined,
                        label: l10n.cropRotate,
                        onPressed: busy ? null : () => unawaited(_rotate()),
                      ),
                      NexPhotoTool(
                        icon: Icons.flip_outlined,
                        label: l10n.cropFlip,
                        selected: _flipped,
                        onPressed: busy ? null : () => unawaited(_flip()),
                      ),
                      NexPhotoTool(
                        icon: Icons.draw_outlined,
                        label: l10n.cropAnnotate,
                        onPressed: busy
                            ? null
                            : () => _startCrop(annotate: true),
                      ),
                      NexPhotoTool(
                        icon: Icons.restart_alt,
                        label: l10n.cropReset,
                        onPressed: busy ? null : _reset,
                      ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => _startCrop(annotate: false),
                      icon: _cropping
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(l10n.cropConfirm),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: math
                    .max(
                      MediaQuery.systemGestureInsetsOf(context).left,
                      MediaQuery.systemGestureInsetsOf(context).right,
                    )
                    .clamp(24.0, 80.0),
                vertical: 12,
              ),
              child: _base == null
                  // Turning a camera photo upright takes a moment; the
                  // cropper waits for the upright one rather than showing
                  // it sideways first. The photo itself stands in, dimmed —
                  // the system draws it upright already.
                  ? Center(
                      child: Opacity(
                        opacity: 0.5,
                        child: Image.memory(widget.image, fit: BoxFit.contain),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(size: constraints.biggest),
                        child: ClipRect(
                          child: Crop(
                            key: ValueKey(_current),
                            image: _current,
                            aspectRatio: _aspectRatio,
                            controller: _controller,
                            initialRectBuilder: _restoredArea == null
                                ? null
                                : InitialRectBuilder.withArea(_restoredArea!),
                            onMoved: (_, area) {
                              _area = area;
                              _snapshot();
                            },
                            onCropped: (result) =>
                                unawaited(_onCropped(result)),
                            // `_crop()` reports `.ready` again right after
                            // `.cropped`, in the same call — including once
                            // this screen has already popped itself in
                            // response to that same result, which made this a
                            // `setState` after dispose.
                            onStatusChanged: (status) {
                              if (!mounted) return;
                              setState(
                                () => _ready = status == CropStatus.ready,
                              );
                            },
                            baseColor: Colors.black,
                            maskColor: Colors.black.withValues(alpha: 0.6),
                            cornerDotBuilder: (size, edge) =>
                                _CropCorner(size: size),
                            interactive: true,
                            radius: 4,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The handle at each corner of the crop: a white dot ringed in the accent,
/// big enough to find with a thumb.
class _CropCorner extends StatelessWidget {
  const _CropCorner({required this.size});

  /// The touch area the cropper gives each corner.
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Center(
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
      ),
    ),
  );
}

class _RatioOption extends StatelessWidget {
  const _RatioOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: NexSpacing.xs),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? scheme.primary
              : Colors.white.withValues(alpha: 0.1),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NexSpacing.md,
                vertical: NexSpacing.sm,
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.onPrimary : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
