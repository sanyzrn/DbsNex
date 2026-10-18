part of '../note_detail_sheet.dart';

/// An image that arrived as a file rather than through the camera.
///
/// The same picture in the same app looked entirely different depending on
/// which door it came in by: one captured or picked was shown full width and
/// opened into the viewer, and one dropped on the share sheet was a filename
/// and a byte count. Same picture, same gesture, same viewer, either way now.
// Decode to the display width only. Giving both cache dimensions forces an
// exact resize and changes a portrait photo's aspect ratio before BoxFit runs.
// Some widget hosts report zero width while measuring; let Image.file choose
// its own decode size in that case.
int? _imageCacheWidth(BuildContext context) {
  final pixels =
      MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context);
  return pixels >= 1 ? pixels.round() : null;
}

class _ImageFileBody extends StatelessWidget {
  const _ImageFileBody({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (!File(path).existsSync()) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              NexPageRoute<void>(
                builder: (_) => NexPhotoViewer.file(path),
                swipeBackEnabled: false,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NexRadius.md),
              child: Image.file(
                File(path),
                semanticLabel: l10n.photo,
                fit: BoxFit.contain,
                height: 220,
                width: double.infinity,
                cacheWidth: _imageCacheWidth(context),
                // A file named `.png` that is not one lands here as a decode
                // failure rather than as a crash. Nothing is drawn, and the
                // row above still says everything the file itself knows.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(l10n.tapToExpand, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
