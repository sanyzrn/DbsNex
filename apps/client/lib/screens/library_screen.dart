import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../widgets/nex_shelf.dart';
import '../widgets/storage_panel.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import 'recently_deleted_screen.dart';
import 'threads_screen.dart';
import 'tag_manager_screen.dart';

/// Where the notes live that are not on the timeline.
///
/// Tags and Trash used to be reachable only through the gear icon. Neither is a
/// preference: Trash is a *content location* holding the user's own notes, and
/// Tags is content organisation. Recovering a note deleted by an accidental
/// swipe — which the swipe gesture makes likely enough to plan for — should not
/// begin with reasoning your way to Settings, the least discoverable path in
/// the app.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  // Started once, here. A future created inside `build` is a new future on
  // every rebuild, so its FutureBuilder resets to "waiting" each time and the
  // placeholder never goes away.
  late final Future<StorageSnapshot> _storage = widget.services.storage();

  /// How much each shelf holds, said on its tile; null until counted.
  ({int tags, int threads, int deleted})? _counts;

  NexServices get services => widget.services;
  NexPreferences get preferences => widget.preferences;

  @override
  void initState() {
    super.initState();
    unawaited(_count());
  }

  Future<void> _count() async {
    try {
      final results = await Future.wait([
        services.listTags(),
        services.threads(),
        services.deletedNotes(),
      ]);
      if (!mounted) return;
      setState(
        () => _counts = (
          tags: results[0].length,
          threads: results[1].length,
          deleted: results[2].length,
        ),
      );
    } catch (_) {
      // The tiles still open their pages; only the counts are missing.
    }
  }

  /// Opens [page], and counts again on the way back: a tag renamed into
  /// another, a thread made, the trash emptied.
  Future<void> _open(Widget page) async {
    await Navigator.push(context, NexPageRoute<void>(builder: (_) => page));
    if (mounted) await _count();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final counts = _counts;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NexSpacing.md,
          NexSpacing.sm,
          NexSpacing.md,
          NexSpacing.md + nexBottomInset(context),
        ),
        children: [
          // Three shelves, each in its own colour and saying how much it
          // holds — the shape Tools uses, for the same reason: a place you
          // go into reads faster as a tile than as a row.
          nexShelfPairs([
            NexShelfTile(
              key: const ValueKey('library-tags'),
              title: l10n.tags,
              subtitle: counts == null
                  ? l10n.libraryTagsHint
                  : l10n.libraryTagCount(counts.tags),
              icon: Icons.label_outline,
              hue: NexHue.violet,
              onTap: () => unawaited(
                _open(
                  TagManagerScreen(
                    services: services,
                    preferences: preferences,
                  ),
                ),
              ),
            ),
            NexShelfTile(
              key: const ValueKey('library-threads'),
              title: l10n.threads,
              subtitle: counts == null
                  ? l10n.threadsSubtitle
                  : l10n.libraryThreadCount(counts.threads),
              icon: Icons.timeline_outlined,
              hue: NexHue.teal,
              onTap: () => unawaited(
                _open(
                  ThreadsScreen(services: services, preferences: preferences),
                ),
              ),
            ),
            NexShelfTile(
              key: const ValueKey('library-trash'),
              title: l10n.trash,
              subtitle: counts == null
                  ? l10n.libraryTrashHint
                  : l10n.libraryTrashCount(counts.deleted),
              icon: Icons.restore_from_trash_outlined,
              hue: NexHue.rose,
              onTap: () => unawaited(
                _open(
                  RecentlyDeletedScreen(
                    services: services,
                    preferences: preferences,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: NexSpacing.md),
          NexPanel(
            padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
            child: FutureBuilder<StorageSnapshot>(
              future: _storage,
              builder: (context, snapshot) => snapshot.hasData
                  ? StoragePanel(snapshot: snapshot.requireData)
                  : const Padding(
                      padding: EdgeInsets.symmetric(horizontal: NexSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NexSkeleton(width: 120, height: 16),
                          SizedBox(height: NexSpacing.sm),
                          NexSkeleton(height: 10),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
