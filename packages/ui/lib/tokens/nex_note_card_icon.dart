import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import 'nex_site_glyph.dart';
import 'nex_tokens.dart';

/// A card's central glyph, sized and colored by the existing note-type disc.
class NexNoteCardGlyph extends StatelessWidget {
  const NexNoteCardGlyph(this.note, {super.key, this.size, this.color});

  final Note note;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final side = size ?? IconTheme.of(context).size ?? 24;
    if (note.snippetPreview case final snippet?) {
      return NexCodeLanguageGlyph(snippet.language, size: side, color: color);
    }
    if (note.type == NoteType.link) {
      final face = NexLinkFace.of(note.linkUrl ?? '');
      if (face.brandColor != null) return NexSiteGlyph(face: face, size: side);
    }
    if (note.type == NoteType.file) {
      final name = note.originalFilename ?? '';
      final path = note.mediaUri ?? '';
      final type = note.mimeType?.split(';').first.trim().toLowerCase();
      Widget? mark(String filename, String? mime) {
        final format = _formatOf(filename, mime);
        if (format != null) {
          return _FormatGlyph(format, size: side, color: color);
        }
        final glyph = _nameIcon(filename) ?? _mimeIcon(mime);
        return glyph == null
            ? null
            : Icon(glyph.icon, size: side, color: color);
      }

      final glyph = mark(name, null) ?? mark('', type) ?? mark(path, null);
      if (glyph != null) return glyph;
    }
    return Icon(nexNoteTypeIcon(note.type.wireName), size: side, color: color);
  }
}

/// Language marks retain the same size in a note, editor or language picker.
class NexCodeLanguageGlyph extends StatelessWidget {
  const NexCodeLanguageGlyph(
    this.language, {
    super.key,
    this.size = 24,
    this.color,
  });

  final NexCodeLanguage language;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      _FormatGlyph(language.glyph, size: size, color: color, source: true);
}

class _FormatGlyph extends StatelessWidget {
  const _FormatGlyph(
    this.label, {
    required this.size,
    this.color,
    this.source = false,
  });

  final String label;
  final double size;
  final Color? color;
  final bool source;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final ink = color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: Center(
        child: SizedBox.square(
          dimension: size,
          child: source
              ? Center(
                  child: Container(
                    width: size,
                    height: size * 0.73,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: ink.withValues(alpha: ink.a * 0.70),
                      ),
                      borderRadius: BorderRadius.circular(size * 0.18),
                    ),
                    child: _label(
                      context,
                      ink,
                      size * (label.length > 3 ? 0.29 : 0.36),
                    ),
                  ),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      size: size,
                      color: color,
                    ),
                    Align(
                      alignment: const Alignment(0, 0.42),
                      child: _label(
                        context,
                        ink,
                        size *
                            switch (label.length) {
                              4 => 0.19,
                              3 => 0.23,
                              _ => 0.30,
                            },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, Color ink, double fontSize) {
    final style = TextStyle(
      inherit: false,
      color: ink.withValues(
        alpha: ink.a * (IconTheme.of(context).opacity ?? 1),
      ),
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1,
    );
    // These aren't text labels for the surrounding button or chip.
    return source
        ? RichText(
            text: TextSpan(text: label, style: style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          )
        : Text(
            label,
            style: style,
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          );
  }
}

String? _formatOf(String name, String? mime) {
  // The actual filename wins over a generic share intent. A known MIME can
  // still give a missing or unfamiliar extension a useful mark.
  final extension = NexFileKinds.extensionOf(name);
  return switch (extension) {
    'md' || 'markdown' || 'mdown' => 'MD',
    'doc' || 'docx' || 'docm' || 'dot' || 'dotx' => 'DOC',
    'xls' || 'xlsx' || 'xlsm' => 'XLS',
    'ppt' || 'pptx' || 'pps' || 'ppsx' => 'PPT',
    'odt' ||
    'ods' ||
    'odp' ||
    'rtf' ||
    'csv' ||
    'tsv' ||
    'zip' ||
    'rar' ||
    'apk' ||
    'svg' ||
    'png' ||
    'gif' ||
    'jpg' ||
    'mp3' ||
    'wav' ||
    'mp4' ||
    'mkv' ||
    'txt' ||
    'eps' => extension.toUpperCase(),
    'jpeg' => 'JPG',
    'webp' => 'WEBP',
    'epub' => 'EPUB',
    '7z' => '7Z',
    'tar' || 'gz' || 'tgz' || 'bz2' || 'xz' => 'TAR',
    'json' || 'jsonc' => '{ }',
    'html' || 'htm' => 'HTM',
    'css' ||
    'js' ||
    'ts' ||
    'py' ||
    'php' ||
    'sql' ||
    'xml' => extension.toUpperCase(),
    'dart' => 'Dart',
    'yaml' || 'yml' => 'YML',
    'pdf' => null,
    _ => switch (mime) {
      'text/plain' => 'TXT',
      'text/markdown' || 'text/x-markdown' => 'MD',
      'text/csv' => 'CSV',
      'text/tab-separated-values' => 'TSV',
      'application/msword' ||
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
        'DOC',
      'application/vnd.ms-excel' ||
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
        'XLS',
      'application/vnd.ms-powerpoint' ||
      'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
        'PPT',
      'application/zip' || 'application/x-zip-compressed' => 'ZIP',
      'application/vnd.android.package-archive' => 'APK',
      'application/epub+zip' => 'EPUB',
      'application/json' => '{ }',
      'image/svg+xml' => 'SVG',
      'image/png' => 'PNG',
      'image/jpeg' => 'JPG',
      'text/html' => 'HTM',
      'text/css' => 'CSS',
      'text/javascript' || 'application/javascript' => 'JS',
      _ => null,
    },
  };
}

enum _FileGlyph {
  pdf(Icons.picture_as_pdf_outlined),
  archive(Icons.folder_zip_outlined),
  spreadsheet(Icons.table_chart_outlined),
  slides(Icons.slideshow_outlined),
  document(Icons.description_outlined),
  text(Icons.article_outlined),
  image(Icons.image_outlined),
  book(Icons.menu_book_outlined),
  code(Icons.code_outlined),
  audio(Icons.audio_file_outlined),
  video(Icons.smart_display_outlined);

  const _FileGlyph(this.icon);
  final IconData icon;
}

_FileGlyph? _nameIcon(String? name) {
  if (name == null || name.isEmpty) return null;
  return switch (NexFileKinds.extensionOf(name)) {
    'pdf' => _FileGlyph.pdf,
    'zip' ||
    'rar' ||
    '7z' ||
    'tar' ||
    'tgz' ||
    'gz' ||
    'bz2' ||
    'xz' => _FileGlyph.archive,
    'xls' || 'xlsx' || 'xlsm' || 'ods' => _FileGlyph.spreadsheet,
    'ppt' || 'pptx' || 'pps' || 'ppsx' || 'odp' => _FileGlyph.slides,
    'docm' || 'dot' || 'dotx' => _FileGlyph.document,
    'svg' || 'tif' || 'tiff' || 'avif' || 'ico' => _FileGlyph.image,
    'epub' => _FileGlyph.book,
    _ => _kindIcon(NexFileKinds.of(path: name)),
  };
}

_FileGlyph? _mimeIcon(String? mimeType) {
  final type = mimeType?.split(';').first.trim().toLowerCase();
  return switch (type) {
    'application/pdf' => _FileGlyph.pdf,
    'application/zip' ||
    'application/x-zip-compressed' ||
    'application/vnd.rar' ||
    'application/x-rar-compressed' ||
    'application/x-7z-compressed' ||
    'application/x-tar' ||
    'application/gzip' ||
    'application/x-gzip' ||
    'application/x-bzip2' ||
    'application/x-xz' => _FileGlyph.archive,
    'application/vnd.ms-excel' ||
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
    'application/vnd.ms-excel.sheet.macroenabled.12' ||
    'application/vnd.oasis.opendocument.spreadsheet' => _FileGlyph.spreadsheet,
    'application/vnd.ms-powerpoint' ||
    'application/vnd.openxmlformats-officedocument.presentationml.presentation' ||
    'application/vnd.openxmlformats-officedocument.presentationml.slideshow' ||
    'application/vnd.oasis.opendocument.presentation' => _FileGlyph.slides,
    'image/svg+xml' => _FileGlyph.image,
    'application/epub+zip' => _FileGlyph.book,
    'application/json' ||
    'application/javascript' ||
    'application/xml' => _FileGlyph.code,
    _ => _kindIcon(NexFileKinds.of(mimeType: type)),
  };
}

_FileGlyph? _kindIcon(NexFileKind kind) => switch (kind) {
  NexFileKind.markdown => _FileGlyph.text,
  NexFileKind.plainText => _FileGlyph.text,
  NexFileKind.code => _FileGlyph.code,
  NexFileKind.table => _FileGlyph.spreadsheet,
  NexFileKind.image => _FileGlyph.image,
  NexFileKind.audio => _FileGlyph.audio,
  NexFileKind.video => _FileGlyph.video,
  NexFileKind.document => _FileGlyph.document,
  NexFileKind.other => null,
};
