import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../platform/app_update.dart';
import '../widgets/release_notes.dart';

/// Every published release's notes, newest first — reachable on its own,
/// not only while an update happens to be pending.
///
/// [UpdateSheet]'s "what's new" panel answers "should I update"; this
/// answers "what have I missed", which stays a fair question long after an
/// update has already been installed.
class ChangelogScreen extends StatefulWidget {
  const ChangelogScreen({super.key, this.checker});

  /// Reuses the caller's [UpdateChecker] when there is one — same client,
  /// same `repository` — rather than standing up a second one that a test
  /// might have pointed somewhere else entirely. Built fresh otherwise.
  final UpdateChecker? checker;

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  late final UpdateChecker _checker =
      widget.checker ?? UpdateChecker(currentVersion: nexAppVersion);
  late final bool _ownsChecker = widget.checker == null;

  // Null until the fetch resolves — distinct from an empty list, which means
  // "asked, got nothing" rather than "hasn't asked yet".
  List<ReleaseNote>? _releases;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final releases = await _checker.listReleases();
    if (!mounted) return;
    setState(() => _releases = releases);
  }

  @override
  void dispose() {
    if (_ownsChecker) _checker.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.changelogTitle)),
      body: _body(l10n),
    );
  }

  Widget _body(AppLocalizations l10n) {
    final releases = _releases;
    if (releases == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (releases.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Text(l10n.changelogEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.all(NexSpacing.lg),
      itemCount: releases.length,
      separatorBuilder: (_, __) => const SizedBox(height: NexSpacing.xl),
      itemBuilder: (context, index) {
        final release = releases[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.changelogVersionHeading(release.version),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: NexSpacing.sm),
            ReleaseNotesList(raw: release.notes),
          ],
        );
      },
    );
  }
}
