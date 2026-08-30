import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';

/// Four switches for the four things the home screen puts above the notes.
///
/// Every one of them is the app's idea rather than the reader's — a greeting,
/// a generated summary, a search field and a row of tags, on a screen whose
/// subject is the list underneath them. This is not a settings page; it is the
/// answer to "I just want my notes", and it lives one tap from the screen it
/// changes rather than three taps into Settings, because it is the kind of
/// thing people turn on and off while looking at the result.
class HomeLayoutSheet extends StatefulWidget {
  const HomeLayoutSheet({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<HomeLayoutSheet> createState() => _HomeLayoutSheetState();
}

class _HomeLayoutSheetState extends State<HomeLayoutSheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prefs = widget.preferences;

    Widget row({
      required IconData icon,
      required String label,
      required bool value,
      required Future<void> Function(bool) onChanged,
    }) => NexSwitchTile(
      value: value,
      secondary: Icon(icon),
      title: Text(label),
      onChanged: (next) async {
        await onChanged(next);
        if (mounted) setState(() {});
      },
    );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.layoutTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  l10n.layoutSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          row(
            icon: Icons.waving_hand_outlined,
            label: l10n.layoutGreeting,
            value: prefs.showGreeting,
            onChanged: prefs.setShowGreeting,
          ),
          row(
            icon: Icons.auto_awesome_outlined,
            label: l10n.layoutDaySummary,
            value: prefs.showDaySummary,
            onChanged: prefs.setShowDaySummary,
          ),
          row(
            icon: Icons.search,
            label: l10n.layoutSearchField,
            value: prefs.showSearchField,
            onChanged: prefs.setShowSearchField,
          ),
          row(
            icon: Icons.sell_outlined,
            label: l10n.layoutTagRow,
            value: prefs.showTagRow,
            onChanged: prefs.setShowTagRow,
          ),
          const SizedBox(height: NexSpacing.sm),
        ],
      ),
    );
  }
}
