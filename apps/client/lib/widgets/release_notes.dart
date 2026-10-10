import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// Where a release's Persian notes start in its body (LOC-05). The release
/// workflow appends them, from CHANGELOG.fa.md, under this marker; GitHub
/// shows nothing for it.
const releaseNotesPersianMarker = '<!-- nex:fa -->';

/// The part of [raw] written for [languageCode]: the Persian notes for a
/// Persian reader when the release carries them, the English otherwise —
/// including every release published before there were Persian notes.
String releaseNotesFor(String raw, String languageCode) {
  final at = raw.indexOf(releaseNotesPersianMarker);
  if (at < 0) return raw.trim();
  final english = raw.substring(0, at).trim();
  final persian = raw.substring(at + releaseNotesPersianMarker.length).trim();
  if (languageCode == 'fa' && persian.isNotEmpty) return persian;
  return english;
}

/// Use the same Markdown renderer as note details. It preserves wrapped
/// paragraphs, emphasis and code without exposing source markers.
class ReleaseNotesList extends StatelessWidget {
  const ReleaseNotesList({super.key, required this.raw});
  final String raw;
  @override
  Widget build(BuildContext context) => NexMarkdown(
    releaseNotesFor(raw, Localizations.localeOf(context).languageCode),
    style: Theme.of(context).textTheme.bodyMedium,
  );
}
