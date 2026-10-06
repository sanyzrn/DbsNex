import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/cycle_reminders.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../../widgets/nex_dialog.dart';
import '../cycle_screen.dart';
import 'cycle_format.dart';
import 'cycle_space.dart';

/// Turns «Cycle» on or off. Off asks once what to do with its data; on is
/// the switch alone. Resolves to the new state — unchanged when the person
/// backed out of the question.
Future<bool> nexSetCycleEnabled(
  BuildContext context, {
  required NexServices services,
  required NexPreferences preferences,
  required bool value,
}) async {
  if (value) {
    await preferences.setCycleEnabled(true);
    if (context.mounted) {
      await CycleReminders.apply(
        context: context,
        services: services,
        preferences: preferences,
      );
    }
    return true;
  }
  final l10n = AppLocalizations.of(context);
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.cycleTurnOffTitle),
      content: NexDialogBody(child: Text(l10n.cycleTurnOffBody)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('cycle-off-delete'),
          onPressed: () => Navigator.pop(dialogContext, 'delete'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: Text(l10n.cycleTurnOffDelete),
        ),
        TextButton(
          key: const ValueKey('cycle-off-keep'),
          onPressed: () => Navigator.pop(dialogContext, 'keep'),
          child: Text(l10n.cycleTurnOffKeep),
        ),
      ],
    ),
  );
  if (choice == null) return true;
  if (choice == 'delete') await services.cycleDeleteAll();
  await services.reminders.cancelCycle();
  await preferences.setCycleEnabled(false);
  return false;
}

/// «Cycle» in the profile: what it is in a few lines, the switch, and a
/// way in once it is on.
///
/// Here rather than among the settings because it is about the person —
/// their body, their rhythm — not about how the app behaves, and the profile
/// is where someone goes for what is theirs. Drawn in Cycle's own blush, so
/// it reads as a door to that space rather than one more row.
class CycleProfileCard extends StatefulWidget {
  const CycleProfileCard({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<CycleProfileCard> createState() => _CycleProfileCardState();
}

class _CycleProfileCardState extends State<CycleProfileCard> {
  Future<void> _set(bool value) async {
    await nexSetCycleEnabled(
      context,
      services: widget.services,
      preferences: widget.preferences,
      value: value,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final on = widget.preferences.cycleEnabled;
    return CycleTheme(
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final brightness = theme.brightness;
          final rose = cyclePeriodColor(brightness);
          return Container(
            key: const ValueKey('profile-cycle'),
            margin: const EdgeInsets.only(top: NexSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NexRadius.xl),
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: brightness == Brightness.dark
                    ? const [Color(0xFF2E1A26), Color(0xFF221C33)]
                    : const [Color(0xFFFCE8EF), Color(0xFFF1EAFB)],
              ),
              border: Border.all(color: cycleHairline(brightness)),
            ),
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.md,
              NexSpacing.sm,
              NexSpacing.sm,
              NexSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  key: const ValueKey('profile-cycle-switch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.water_drop_outlined, color: rose),
                  title: Text(
                    l10n.cycleTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  value: on,
                  onChanged: _set,
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
                  child: Text(
                    l10n.cycleProfileAbout,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ),
                if (on)
                  Padding(
                    padding: const EdgeInsets.only(top: NexSpacing.sm),
                    child: TextButton.icon(
                      key: const ValueKey('profile-cycle-open'),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(l10n.cycleProfileOpen),
                      onPressed: () => Navigator.push(
                        context,
                        NexPageRoute<void>(
                          builder: (_) => CycleScreen(
                            services: widget.services,
                            preferences: widget.preferences,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
