import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// Renders a CHANGELOG-style bullet list as an actual list, not the flat
/// paragraph a bare `Text` would make of it — the source is already curated
/// to be user-facing, so the one thing left to do here is presentation.
///
/// Shared between the update sheet's "what's new" panel and the full
/// changelog history: both show the same shape of content, one release's
/// notes at a time.
class ReleaseNotesList extends StatelessWidget {
  const ReleaseNotesList({super.key, required this.raw});

  final String raw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = raw
        .trim()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines) _ReleaseNoteLine(line: line, theme: theme),
      ],
    );
  }
}

class _ReleaseNoteLine extends StatelessWidget {
  const _ReleaseNoteLine({required this.line, required this.theme});

  final String line;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Every line in the source is a `- ` bullet (see CHANGELOG.md's own
    // convention); the strip-and-guard keeps this from breaking if that ever
    // stops being true rather than swallowing a line silently.
    final isBullet = line.startsWith('- ');
    final text = isBullet ? line.substring(2) : line;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBullet)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          if (isBullet) const SizedBox(width: NexSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
