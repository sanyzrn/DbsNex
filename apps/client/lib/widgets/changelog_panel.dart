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
///
/// [limit] keeps the newest that many sections. Null keeps all of them, which
/// is what the parser's own tests want; the screen passes a number, because a
/// list of every release there has ever been is an archive, and nobody opens
/// About looking for an archive.
@visibleForTesting
List<ChangelogSection> parseChangelogSections(String raw, {int? limit}) {
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

  final shown = sections
      .where((s) => s.heading != 'How this file is used')
      .toList();
  if (limit == null || shown.length <= limit) return shown;
  return shown.sublist(0, limit);
}

/// The changelog, inline, at the bottom of About — not a separate route, and
/// not a network fetch. The bundled copy is always present in a running app:
/// it is the one piece of user-facing content this screen does not depend on
/// a server for.
///
/// It used to sit under the update screen's offer, which put every release
/// there has ever been beneath a question about one of them. About is where a
/// history belongs, and About is a page that already scrolls — so this no
/// longer scrolls inside itself, which is the thing nested scrollers do worst.
class ChangelogPanel extends StatefulWidget {
  const ChangelogPanel({super.key, this.limit = 10});

  /// How many releases back to show.
  ///
  /// Ten, which at this project's pace is a few months — enough to answer
  /// "when did this arrive?" without turning the page into a changelog file
  /// with a scrollbar. The bundled file still holds everything; only what is
  /// drawn is capped, so raising this is one number and loses nothing.
  final int limit;

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
    // assets/CHANGELOG.md, not the root file directly: see the comment on
    // this asset in pubspec.yaml for why a `..`-escaping path silently fails
    // on a real build despite working under `flutter test`.
    final raw = await rootBundle.loadString('assets/CHANGELOG.md');
    // Parsed unbounded and cached that way: the cache is shared, and a second
    // caller wanting a different number should not be served whatever the
    // first one asked for.
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
        final shown = sections.length <= widget.limit
            ? sections
            : sections.sublist(0, widget.limit);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in shown) ...[
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
        );
      },
    );
  }
}
