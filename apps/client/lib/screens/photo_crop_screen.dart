import 'dart:async';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../l10n/app_localizations.dart';
import '../widgets/nex_banner.dart';
import '../widgets/photo_action_bar.dart';
import 'photo_annotate_screen.dart';

/// Runs off the UI thread: a full-resolution camera photo is large enough
/// that decode+rotate+encode on the main isolate would drop frames.
Uint8List _rotateClockwise(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final rotated = img.copyRotate(decoded, angle: 90);
  // PNG, not the source format: re-encoding a JPEG here would compound
  // generation loss on every tap, for a step that is meant to be repeatable.
  return Uint8List.fromList(img.encodePng(rotated));
}

/// Crop step shown right after a photo is taken or picked, before it is ever
/// written to disk.
///
/// Returns the cropped bytes, or `null` if the user backs out — which
/// discards the whole capture, not just the crop, matching the camera-app
/// convention this follows: the X abandons the photo, the checkmark commits
/// the crop and moves on.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({super.key, required this.image});

  final Uint8List image;

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final _controller = CropController();
  Uint8List _current = Uint8List(0);
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

  @override
  void initState() {
    super.initState();
    _current = widget.image;
  }

  Future<void> _rotate() async {
    if (_rotating || _cropping || !_ready) return;
    setState(() => _rotating = true);
    final rotated = await compute(_rotateClockwise, _current);
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
      _current = rotated;
      _ready = false;
      _rotating = false;
    });
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
        if (!_pendingAnnotate) {
          Navigator.of(context).pop(croppedImage);
          return;
        }
        final annotated = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(
            builder: (_) => PhotoAnnotateScreen(image: croppedImage),
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop(annotated ?? croppedImage);
      case CropFailure(:final cause):
        setState(() => _cropping = false);
        nexShowBanner(context, message: '$cause');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = _cropping || _rotating || !_ready;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.cropPhotoTitle),
        leading: IconButton(
          tooltip: l10n.cropCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // The controls are at the bottom now — see [NexPhotoActionBar]. They
      // were three small icons in the app bar, which is the far corner of a
      // phone from the hand holding it, and one of them committed the photo.
      bottomNavigationBar: NexPhotoActionBar(
        tools: [
          NexPhotoTool(
            icon: Icons.rotate_90_degrees_cw_outlined,
            label: l10n.cropRotate,
            busy: _rotating,
            onPressed: busy ? null : _rotate,
          ),
          NexPhotoTool(
            icon: Icons.edit_outlined,
            label: l10n.cropAnnotate,
            onPressed: busy ? null : () => _startCrop(annotate: true),
          ),
        ],
        buttons: [
          NexPhotoPrimaryButton(
            label: l10n.cropConfirm,
            icon: Icons.check,
            busy: _cropping,
            onPressed: busy ? null : () => _startCrop(annotate: false),
          ),
        ],
      ),
      body: Crop(
        key: ValueKey(_current),
        image: _current,
        controller: _controller,
        onCropped: (result) => unawaited(_onCropped(result)),
        // `_crop()` reports `.ready` again right after `.cropped`, in the
        // same call — including once this screen has already popped itself
        // in response to that same result, which made this a `setState`
        // after dispose.
        onStatusChanged: (status) {
          if (!mounted) return;
          setState(() => _ready = status == CropStatus.ready);
        },
        baseColor: Colors.black,
        maskColor: Colors.black.withValues(alpha: 0.6),
      ),
    );
  }
}
