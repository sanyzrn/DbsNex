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
  const GuideScreen({super.key});

  static Future<void> show(BuildContext context) => Navigator.of(
    context,
  ).push(NexPageRoute<void>(builder: (_) => const GuideScreen()));

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
    _guide = rootBundle.loadString(
      code == 'fa' ? 'assets/guide/fa.md' : 'assets/guide/en.md',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.guideTitle)),
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

/// One screenshot from `assets/guide/images/`, at phone-screen proportions.
///
/// The frame is fixed at 4:5 whatever the file's own size, so a picture
/// replaced later cannot push the text around, and a missing one leaves a
/// labelled space rather than an error.
class _GuideImage extends StatelessWidget {
  const _GuideImage({required this.file, required this.alt});

  final String file;
  final String alt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Semantics(
            image: true,
            label: alt,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NexRadius.lg),
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: Image.asset(
                  'assets/guide/images/$file',
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (context, _, _) => ColoredBox(
                    color: scheme.surfaceContainerHigh,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(NexSpacing.md),
                        child: Text(alt, textAlign: TextAlign.center),
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
