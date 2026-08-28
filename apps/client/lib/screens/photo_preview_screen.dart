import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../widgets/photo_action_bar.dart';
import 'photo_crop_screen.dart';

/// What you see straight after taking or picking a photo.
///
/// This screen exists because the one before it was wrong about what people
/// want. Capture used to open the cropper directly — every photo, no
/// exception — which puts an edit in the path of a note that mostly did not
/// need one. A photo of a whiteboard goes straight in; the crop is the
/// exception, and an exception should be a button rather than a toll.
///
/// So: the picture, and two decisions. Save it as it is, or go and change it
/// first. Backing out discards the capture entirely, which is the camera
/// convention the crop screen already followed.
///
/// Returns the bytes to store, or null if the user backed out.
class PhotoPreviewScreen extends StatelessWidget {
  const PhotoPreviewScreen({super.key, required this.image});

  final Uint8List image;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      // The photo runs the whole height, under the bar and under the status
      // bar, because it is the subject of the screen and a letterboxed
      // thumbnail with chrome around it is a form, not a photo.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: l10n.cropCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Contained, not covered: a crop that happens without being asked
          // for is the thing this screen was added to stop.
          Center(child: Image.memory(image, fit: BoxFit.contain)),
          Align(
            alignment: Alignment.bottomCenter,
            child: NexPhotoActionBar(
              buttons: [
                NexPhotoSecondaryButton(
                  label: l10n.edit,
                  icon: Icons.tune,
                  onPressed: () => _edit(context),
                ),
                NexPhotoPrimaryButton(
                  label: l10n.cropConfirm,
                  icon: Icons.check,
                  onPressed: () => Navigator.of(context).pop(image),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final edited = await Navigator.of(context).push<Uint8List>(
      NexPageRoute(builder: (_) => PhotoCropScreen(image: image)),
    );
    if (!context.mounted) return;
    // Null means they backed out of the editor, not out of the capture — so
    // this screen stays, with the original still on it.
    if (edited != null) Navigator.of(context).pop(edited);
  }
}
