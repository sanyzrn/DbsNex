import '../platform/crash_reporter.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/editor_drafts.dart';
import '../widgets/draft_guard.dart';
import '../widgets/nex_banner.dart';
import '../widgets/photo_editor_theme.dart';
import 'photo_annotate_screen.dart';
import 'photo_crop_image.dart';

// The crop package fixes its corner slots at 32dp. Scale only its bounded
// viewport so each slot reaches 48dp; image fit and image-based crop areas
// stay the same. Compensate the dot/stroke below to keep their visible size.
const _cropControlScale = 1.5;

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
  // Every term is a real difference from the photo as it was handed in — a
  // turn, a flip, a ratio, an area the person moved — or work in flight.
  // `_ready` is none of those: it only says the parser finished, and counting
  // it asked "discard changes?" of somebody who had changed nothing and only
  // waited. The first `onMoved` after a (re)mount is the layout's own rect
  // (the package reports the initial computation the same way it reports a
  // drag), so [_initialArea] absorbs it and only a rect that differs from it
  // afterwards counts.
  bool get hasUnsavedChanges =>
      _turns != 0 ||
      _flipped ||
      _aspectRatio != null ||
      _restoredArea != null ||
      _areaMoved ||
      _rotating ||
      _cropping;
  final _controller = CropController();

  late Uint8List _source = widget.image;
  PhotoCropPreview? _preview;
  Uint8List? _previewBytes;
  ImageParser<Size>? _previewParser;
  late bool _legacyAnnotation;
  bool get _legacyCrop => _legacyAnnotation && identical(_source, widget.image);

  int _turns = 0;
  bool _flipped = false;
  bool _cropping = false;
  bool _rotating = false;
  // False from the very first frame until `Crop`'s own async parse of
  // the preview finishes (again after every rotation) — calling
  // `CropController.crop()` before that hits a package-internal assertion,
  // since there is nothing parsed yet to crop.
  bool _ready = false;
  // Which action asked for the crop: the checkmark returns straight to the
  // caller, the pencil detours through the (optional) annotate screen first.
  bool _pendingAnnotate = false;
  final _ratioScroll = ScrollController();
  Rect? _restoredArea;
  Rect? _area;

  /// See [hasUnsavedChanges]: the rect as the layout left it, and whether a
  /// later rect has differed from it.
  Rect? _initialArea;
  bool _areaMoved = false;
  String get _key => '${widget.draftKey}-crop';
  void _snapshot() => widget.drafts?.writeSoon(_key, {
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
    _preview?.dispose();
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

  Future<void> _reset() => _transform(turns: 0, flip: false, reset: true);

  @override
  void initState() {
    super.initState();
    final draft = widget.drafts?.read(_key);
    final annotation = widget.drafts?.read('${widget.draftKey}-annotation');
    _legacyAnnotation =
        annotation?['image'] != null &&
        (annotation?['version'] != 2 || annotation?['legacyCrop'] == true);
    _aspectRatio = (draft?['ratio'] as num?)?.toDouble();
    _turns = ((draft?['turns'] as num?)?.toInt() ?? 0) % 4;
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
    unawaited(_loadPreview(_source));
  }

  Future<void> _loadPreview(Uint8List source) async {
    PhotoCropPreview? preview;
    try {
      preview = await PhotoCropPreview.decode(source);
      if (!mounted) return;
      final bytes = await preview.render(_turns, _flipped);
      if (!mounted) return;
      final old = _preview;
      setState(() {
        _source = source;
        _preview = preview;
        _previewBytes = bytes;
        _previewParser = _preview!.parser(_turns);
        _ready = false;
      });
      preview = null;
      old?.dispose();
    } catch (error) {
      _showEditFailure('photo.preview', error);
    } finally {
      preview?.dispose();
    }
  }

  Future<void> _rotate() => _transform(turns: (_turns + 1) % 4, flip: _flipped);

  Future<void> _flip() => _transform(turns: _turns, flip: !_flipped);

  Future<void> _transform({
    required int turns,
    required bool flip,
    bool reset = false,
  }) async {
    final preview = _preview;
    if (_rotating || _cropping || !_ready || preview == null) return;
    setState(() => _rotating = true);
    try {
      final transformed = await preview.render(turns, flip);
      if (!mounted) return;
      // Remount Crop within its bounded viewport. Updating its controller's
      // image in place uses the full screen as the viewport.
      setState(() {
        _turns = turns;
        _flipped = flip;
        _restoredArea = null;
        _area = null;
        _initialArea = null;
        _previewBytes = transformed;
        _previewParser = preview.parser(turns);
        _ready = false;
        if (reset) {
          discardDraft();
          _legacyAnnotation = false;
          _areaMoved = false;
          _aspectRatio = null;
        }
      });
      if (!reset) _snapshot();
    } catch (error) {
      _showEditFailure('photo.rotate', error);
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  void _showEditFailure(String stage, Object error) {
    unawaited(NexCrashLog.handled(stage, error));
    if (!mounted) return;
    nexShowBanner(
      context,
      kind: NexBannerKind.failed,
      message: AppLocalizations.of(context).photoEditFailed,
    );
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
        if (!mounted) return;
        if (!_pendingAnnotate) {
          Navigator.of(context).pop(croppedImage);
          return;
        }
        final annotated = await Navigator.of(context).push<Uint8List>(
          NexPageRoute(
            swipeBackEnabled: false,
            builder: (_) => PhotoAnnotateScreen(
              image: croppedImage,
              drafts: widget.drafts,
              draftKey: widget.draftKey,
              legacyCrop: _legacyCrop,
            ),
          ),
        );
        if (!mounted) return;
        if (annotated == null) {
          setState(() {
            // Back from drawing: the crop stays made, and it is what turns
            // and flips start from now.
            _turns = 0;
            _flipped = false;
            _restoredArea = null;
            _area = null;
            _initialArea = null;
            _areaMoved = true;
            _previewBytes = null;
            _cropping = false;
            _ready = false;
          });
          unawaited(_loadPreview(croppedImage));
        } else {
          Navigator.of(context).pop(annotated);
        }
      case CropFailure(:final cause):
        if (!mounted) return;
        setState(() => _cropping = false);
        _showEditFailure('photo.crop', cause);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = _cropping || _rotating || !_ready;
    final preview = _previewBytes;
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
                        onPressed: busy ? null : () => unawaited(_reset()),
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
              child: preview == null
                  ? const SizedBox.expand()
                  : LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(size: constraints.biggest),
                        child: ClipRect(
                          child: SizedBox.fromSize(
                            size: constraints.biggest,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: SizedBox(
                                width: constraints.maxWidth / _cropControlScale,
                                height:
                                    constraints.maxHeight / _cropControlScale,
                                child: Crop(
                                  key: ValueKey(preview),
                                  image: preview,
                                  imageParser: _previewParser,
                                  imageCropper: OriginalPhotoCropper(
                                    _source,
                                    _turns,
                                    _flipped,
                                    _legacyCrop,
                                  ),
                                  aspectRatio: _aspectRatio,
                                  controller: _controller,
                                  initialRectBuilder: _restoredArea == null
                                      ? null
                                      : InitialRectBuilder.withArea(
                                          _restoredArea!,
                                        ),
                                  onMoved: (_, area) {
                                    if (_area == area) return;
                                    _area = area;
                                    // The first report after a (re)mount is
                                    // the initial rect itself — layout, not a
                                    // hand. Only a rect that differs from it
                                    // is an edit.
                                    final initial = _initialArea;
                                    if (initial == null) {
                                      _initialArea = area;
                                    } else if (area != initial) {
                                      _areaMoved = true;
                                      _snapshot();
                                    }
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
                                  maskColor: Colors.black.withValues(
                                    alpha: 0.6,
                                  ),
                                  cornerDotBuilder: (size, edge) =>
                                      _CropCorner(size: size, edge: edge),
                                  interactive: true,
                                  radius: 4 / _cropControlScale,
                                ),
                              ),
                            ),
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
  const _CropCorner({required this.size, required this.edge});

  final double size;
  final EdgeAlignment edge;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ColoredBox(
      // A transparent, hit-testable surface, not just empty layout space.
      color: Colors.transparent,
      key: ValueKey('crop-target-${edge.name}'),
      child: Center(
        child: Container(
          key: ValueKey('crop-dot-${edge.name}'),
          width: 14 / _cropControlScale,
          height: 14 / _cropControlScale,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2 / _cropControlScale,
            ),
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
    // The pill is drawn at its own height, centred in the row, and the touch
    // reaches the row's whole height (2.8.1). A horizontal list stretches its
    // children to the row, so the pill used to grow into a tall bubble with
    // its label pinned to the top edge.
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: NexSpacing.xs),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Center(
              child: AnimatedContainer(
                duration: NexMotion.of(context, NexMotion.standard),
                curve: NexMotion.curve,
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.textScalerOf(context).scale(20) +
                      NexSpacing.md +
                      NexSpacing.xs,
                  minWidth: 56,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: selected
                      ? scheme.primary
                      : Colors.white.withValues(alpha: 0.1),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.onPrimary : Colors.white,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
