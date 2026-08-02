import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/nex_toast.dart';

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
  bool _cropping = false;

  void _onCropped(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure(:final cause):
        setState(() => _cropping = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(nexToast(content: Text('$cause')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            onPressed: _cropping
                ? null
                : () {
                    setState(() => _cropping = true);
                    _controller.crop();
                  },
          ),
        ],
      ),
      body: Crop(
        image: widget.image,
        controller: _controller,
        onCropped: _onCropped,
        baseColor: Colors.black,
        maskColor: Colors.black.withValues(alpha: 0.6),
      ),
    );
  }
}
