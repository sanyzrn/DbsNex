import 'package:flutter/material.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../widgets/storage_panel.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import 'recently_deleted_screen.dart';
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

  NexServices get services => widget.services;
  NexPreferences get preferences => widget.preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryTitle)),
      body: ListView(
        padding: EdgeInsets.only(
          top: NexSpacing.sm,
          bottom: NexSpacing.sm + nexBottomInset(context),
        ),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.lg,
            ),
            leading: const Icon(Icons.label_outline),
            title: Text(l10n.tags),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              NexPageRoute<void>(
                builder: (_) => TagManagerScreen(services: services),
              ),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.lg,
            ),
            leading: const Icon(Icons.restore_from_trash_outlined),
            title: Text(l10n.trash),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              NexPageRoute<void>(
                builder: (_) => RecentlyDeletedScreen(
                  services: services,
                  preferences: preferences,
                ),
              ),
            ),
          ),
          const Divider(height: NexSpacing.xl),
          FutureBuilder<StorageSnapshot>(
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
        ],
      ),
    );
  }
}
