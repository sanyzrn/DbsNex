import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';

class EmptyTimeline extends StatelessWidget {
  const EmptyTimeline({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The clearance is reserved *outside* the Center, which is the whole
    // point. It used to be bottom padding on the scroll view, inside the
    // centred block — so it moved the content up by half of itself and left
    // the rest of it under the capture button, which is anchored to the
    // viewport rather than to this column. On a desktop window, where the
    // empty state is shorter than the space it sits in, the last line came out
    // directly beneath the button.
    return Padding(
      padding: EdgeInsets.only(
        bottom: nexFabClearance + nexBottomInset(context),
      ),
      child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Text(l10n.emptyPromise, textAlign: TextAlign.center, style: theme.textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(l10n.emptySupport, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              _Ghost(Icons.short_text, l10n.emptyType),
              const SizedBox(height: 8),
              _Ghost(Icons.graphic_eq, l10n.emptySpeak),
              const SizedBox(height: 8),
              _Ghost(Icons.photo_camera_outlined, l10n.emptyPhotograph),
              const SizedBox(height: 16),
              Text(l10n.emptyNoSave, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                l10n.emptyAi,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _Ghost extends StatelessWidget {
  const _Ghost(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(children: [
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon),
      ),
      const SizedBox(width: 14),
      Expanded(child: Divider(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3))),
      const SizedBox(width: 14),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );
}