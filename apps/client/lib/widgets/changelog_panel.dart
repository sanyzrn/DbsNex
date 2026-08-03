import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'release_notes.dart';

/// One `## `-headed section of CHANGELOG.md, in source order (newest first —
/// the file itself is written that way).
@immutable
class ChangelogSection {
  const ChangelogSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

/// Splits CHANGELOG.md into its `## ` sections, keeping only the ones with
/// real bullets to show — the file's own "How this file is used" preamble is
/// written for contributors, not for someone reading this in the app.
@visibleForTesting
List<ChangelogSection> parseChangelogSections(String raw) {
  final sections = <ChangelogSection>[];
  String? heading;
  final body = StringBuffer();
  void flush() {
    final trimmed = body.toString().trim();
    if (heading != null && trimmed.isNotEmpty) {
      sections.add(ChangelogSection(heading: heading, body: trimmed));
    }
    body.clear();
  }

  for (final line in raw.split('\n')) {
    if (line.startsWith('## ')) {
      flush();
      heading = line.substring(3).trim();
    } else if (heading != null) {
      body.writeln(line);
    }
  }
  flush();

  return sections.where((s) => s.heading != 'How this file is used').toList();
}

/// The changelog, inline and scrollable, right where the update sheet always
/// shows it — not a separate route, and not a network fetch. `flutter test`
/// runs without a real asset bundle unless the caller wraps it, but the
/// bundled CHANGELOG.md is always present in a running app: it is the one
/// piece of user-facing content this screen does not depend on a server for.
class ChangelogPanel extends StatefulWidget {
  const ChangelogPanel({super.key});

  @override
  State<ChangelogPanel> createState() => _ChangelogPanelState();
}

/// Cached at module level: the bundled file cannot change during a session,
/// so re-reading and re-parsing it every time the panel mounts — the update
/// sheet is reachable repeatedly from Settings — would just be waste.
Future<List<ChangelogSection>>? _cachedChangelog;

class _ChangelogPanelState extends State<ChangelogPanel> {
  late final Future<List<ChangelogSection>> _sections = _cachedChangelog ??=
      _load();

  Future<List<ChangelogSection>> _load() async {
    // The asset key is the literal pubspec path, `..` and all — Flutter does
    // not normalise it to the bare filename, confirmed against this app's
    // own generated AssetManifest.json.
    final raw = await rootBundle.loadString('../../CHANGELOG.md');
    return parseChangelogSections(raw);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<List<ChangelogSection>>(
      future: _sections,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // No spinner: this is a local bundled file, not a network fetch —
          // the wait is one frame, not something worth animating for. An
          // indeterminate `CircularProgressIndicator` also runs a repeating
          // ticker, which is actively hostile to `pumpAndSettle()` in tests
          // if this state is ever visible for more than an instant.
          return const SizedBox(height: 60);
        }
        final sections = snapshot.data;
        if (sections == null || sections.isEmpty) {
          return Text(l10n.changelogEmpty, style: theme.textTheme.bodyMedium);
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final section in sections) ...[
                    Text(
                      section.heading == 'Unreleased'
                          ? l10n.changelogLatestHeading
                          : l10n.changelogVersionHeading(section.heading),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    ReleaseNotesList(raw: section.body),
                    const SizedBox(height: NexSpacing.lg),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
