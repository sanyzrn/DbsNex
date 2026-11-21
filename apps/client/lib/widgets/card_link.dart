import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/link_art.dart';

/// What a link's card calls it: the page's own title, or the one its address
/// spells out — never the address again, which the site's name already says.
String nexLinkHeadline(Note note, String title, NexLinkFace face) {
  final url = (note.linkUrl ?? '').trim();
  final bare = title.trim().toLowerCase().replaceFirst(_addressPrefix, '');
  final host = face.host.toLowerCase();
  final onlyAddress =
      title.trim().isEmpty ||
      title.trim() == url ||
      bare == host ||
      bare.startsWith('$host/') && !title.contains(' ');
  return onlyAddress ? (face.title ?? '') : title;
}

final RegExp _addressPrefix = RegExp(r'^(https?://)?(www\.)?');

/// The colour a site is drawn in: its own when it is one people know, one
/// worked out from its address otherwise — the same site, the same colour.
Color nexSiteColor(NexLinkFace face, ColorScheme scheme) {
  if (face.brandColor case final brand?) return Color(brand);
  final hue =
      face.host.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0xffff) % 360;
  return HSLColor.fromAHSL(
    1,
    hue.toDouble(),
    0.55,
    scheme.brightness == Brightness.dark ? 0.62 : 0.46,
  ).toColor();
}

/// The site's mark: its own icon when it gave one, otherwise its initial on
/// its colour (2.8.3).
class NexSiteMark extends StatelessWidget {
  const NexSiteMark({
    super.key,
    required this.face,
    required this.icon,
    required this.size,
    required this.tint,
  });

  final NexLinkFace face;
  final File? icon;
  final double size;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = nexSiteColor(face, scheme);
    if (face.brandColor != null) {
      return NexSiteGlyph(face: face, size: size);
    }
    final radius = BorderRadius.circular(size * 0.3);
    if (icon case final file?) {
      return Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (context, error, stack) =>
              NexSiteGlyph(face: face, size: size * 0.72),
        ),
      );
    }
    final letter = face.name.isEmpty
        ? '#'
        : face.name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, tint, 0.4)!],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: nexReadableOn(Colors.white, color),
          fontWeight: FontWeight.w800,
          fontSize: size * 0.48,
          height: 1,
        ),
      ),
    );
  }
}

/// A link's list card: what the page is called — or what its address
/// says it is — and, with a second row, the site by its own icon, its name
/// and what the link points at (2.8.3). It replaces the bare address and a
/// globe the list card had.
class NexCardLinkPreview extends StatelessWidget {
  const NexCardLinkPreview({super.key, required this.note});

  final Note note;

  static bool fits(Note note) =>
      note.type == NoteType.link && (note.linkUrl ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: NexLinkArt.instance,
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final face = NexLinkFace.of(note.linkUrl ?? '');
      final row = nexCardPreviewLineHeightFor(context);
      final lines = NexCardDensity.of(context).lines;
      final words = nexLinkHeadline(note, note.title ?? '', face);
      final headline = NexMarkdownText.preview(
        words.isNotEmpty ? words : (note.displayText ?? note.linkUrl ?? ''),
      );
      final kind = face.kind == NexLinkKind.page
          ? null
          : AppLocalizations.of(context).tileLinkKind(face.kind.name);
      final small = theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      );
      return Column(
        key: const ValueKey('card-link'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: row,
            child: NexTextSurface.line(
              headline,
              style: NexCardDensity.of(context).previewStyle(theme),
            ),
          ),
          if (lines > 1)
            SizedBox(
              height: row,
              child: Row(
                children: [
                  NexSiteMark(
                    face: face,
                    icon: NexLinkArt.instance.of(note.id)?.icon,
                    size: 16,
                    tint: nexSiteColor(face, scheme),
                  ),
                  const SizedBox(width: NexSpacing.xs + 2),
                  Flexible(
                    flex: 2,
                    child: Text(
                      face.host.isEmpty ? (note.linkUrl ?? '') : face.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: face.brandColor == null
                          ? TextDirection.ltr
                          : null,
                      style: small?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (kind != null)
                    Flexible(
                      child: Text(
                        ' · $kind',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
