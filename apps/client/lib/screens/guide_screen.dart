import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// Everything the app does, in one page.
///
/// A bundled Markdown file per language rather than a screenful of localised
/// strings, and that is worth saying out loud because it goes against how the
/// rest of this app is translated. Those strings are *labels* — a word on a
/// button, in a place a translator can see. This is prose: a dozen sections of
/// it, which as ARB keys would double the size of the catalogue and turn every
/// wording fix into an edit across five files.
///
/// It also renders through [NexMarkdown], so the guide comes out in the same
/// typography as a note — which is the point of having written that renderer.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, this.privacy = false});

  /// The privacy policy rather than the guide (REL-02): the same reader, its
  /// own files under `assets/privacy/`.
  final bool privacy;

  static Future<void> show(BuildContext context, {bool privacy = false}) =>
      Navigator.of(
        context,
      ).push(NexPageRoute<void>(builder: (_) => GuideScreen(privacy: privacy)));

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  Future<String>? _guide;
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Language can change while the app is open, and the guide is one of the
    // few screens where that means loading a different file rather than
    // rebuilding with different strings.
    final code = Localizations.localeOf(context).languageCode;
    if (code == _loadedFor) return;
    _loadedFor = code;
    final folder = widget.privacy ? 'privacy' : 'guide';
    _guide = rootBundle.loadString(
      code == 'fa' ? 'assets/$folder/fa.md' : 'assets/$folder/en.md',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.privacy ? l10n.privacyPolicy : l10n.guideTitle),
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _guide,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(NexSpacing.lg),
                child: NexSkeleton(height: 16),
              );
            }
            final text = snapshot.data?.trim() ?? '';
            if (text.isEmpty) {
              // Only reachable if the asset failed to bundle. Said out loud
              // rather than shown as an empty page, which is indistinguishable
              // from a guide nobody wrote.
              return Padding(
                padding: const EdgeInsets.all(NexSpacing.lg),
                child: Text(l10n.guideUnavailable),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.lg,
                NexSpacing.md,
                NexSpacing.lg,
                NexSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final part in _parts(text))
                    switch (part) {
                      (image: final file?, alt: final alt, text: _) =>
                        _GuideImage(file: file, alt: alt),
                      (image: null, alt: _, text: final prose) => NexMarkdown(
                        prose,
                      ),
                    },
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// An image on a line of its own: `![what it shows](file.webp)`.
final _imageLine = RegExp(r'^!\[([^\]]*)\]\(([^)\s]+)\)\s*$');

/// The guide as runs of prose between its pictures.
///
/// Pictures are laid out here rather than handed to the Markdown renderer,
/// which knows nothing about bundled assets and would try to open the name
/// as a URL.
List<({String? image, String alt, String text})> _parts(String source) {
  final parts = <({String? image, String alt, String text})>[];
  final prose = <String>[];
  void flush() {
    final text = prose.join('\n').trim();
    if (text.isNotEmpty) parts.add((image: null, alt: '', text: text));
    prose.clear();
  }

  for (final line in source.split('\n')) {
    final match = _imageLine.firstMatch(line.trim());
    if (match == null) {
      prose.add(line);
      continue;
    }
    flush();
    parts.add((image: match[2]!, alt: match[1]!, text: ''));
  }
  flush();
  return parts;
}

/// The stand-in pictures shipped until real screenshots exist, by content.
///
/// The Persian guide has its own files (`name_fa.webp`) so the two languages
/// can show their own screens. Both start as the same stand-ins, and a
/// stand-in is not shown at all: an illustration of nothing reads as a broken
/// guide. Replacing a file with a real screenshot changes its bytes, and it
/// appears — nothing else to edit.
const _placeholders = {
  '6d3724cf0b9f240aa4d9a795355f3e3a3a499413ca8b5e52426a8f73521a556c',
  '7cd1289bef6325ec67c74170793c732854fdfbffeaa14698e4e4e339d1aba2c5',
  '55432d3ccd6ebb35c4b15574c14c564e013e51f325f128ba633a18d07812f21f',
  '5bb758d139e513d41e48fde9a515cbcba082385ba7d35b14b065e2801f3093a5',
  'ad32e5bb9e6f1eedec1ec81809c6a973fe4f0e4e09069927b46617e66ca517b9',
  '8f1487a22c1975bf341d25f39c152af1ad4ca2046b600f6281ced2ce5d11ada5',
  '654771e324b2bb7dd52e921b44bf9a173ed6f2766f96580f4fa39d95f6753176',
  'b5f0dbf2fef5362130812a07589ccedba6f658ce3feac4950b568c787d4d5c0f',
  '4f31fe1fcbd5204c7fa4b3dd089de2aadfe7b20b282c834659dac7ac4fde8fef',
  'e952f0b57190abc3f558bca1b2eebd9d387c724fff1a3d5b92df9873679ef801',
  'd34e85c24118899dc988191b61769e2c28634ce19d2201e951f897ad3b99d388',
  '977c0a94b9396e2a926806dbcd35d4a6ee05203674bb1ce5728ab3c36b42ff5d',
  '2ff111b955de6b030c8efa9172aae387cd500bad1838a937ff9b3834f8a77654',
};

/// Loads a guide picture and says whether it is a real one: null for a
/// stand-in or a file that is not there.
@visibleForTesting
Future<Uint8List?> nexGuidePicture(String file) async {
  try {
    final data = await rootBundle.load('assets/guide/images/$file');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (_placeholders.contains(sha256.convert(bytes).toString())) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

/// One screenshot from `assets/guide/images/`, at phone-screen proportions.
///
/// The frame is fixed at 4:5 whatever the file's own size, so a picture
/// replaced later cannot push the text around. A stand-in or a missing file
/// takes no space at all.
class _GuideImage extends StatefulWidget {
  const _GuideImage({required this.file, required this.alt});

  final String file;
  final String alt;

  @override
  State<_GuideImage> createState() => _GuideImageState();
}

class _GuideImageState extends State<_GuideImage> {
  late final Future<Uint8List?> _bytes = nexGuidePicture(widget.file);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Semantics(
              image: true,
              label: widget.alt,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(NexRadius.lg),
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
