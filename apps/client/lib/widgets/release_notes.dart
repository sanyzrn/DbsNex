import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// Use the same Markdown renderer as note details. It preserves wrapped
/// paragraphs, emphasis and code without exposing source markers.
class ReleaseNotesList extends StatelessWidget {
  const ReleaseNotesList({super.key, required this.raw});
  final String raw;
  @override
  Widget build(BuildContext context) =>
      NexMarkdown(raw.trim(), style: Theme.of(context).textTheme.bodyMedium);
}
