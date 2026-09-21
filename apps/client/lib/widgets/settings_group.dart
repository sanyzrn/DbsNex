/// The two shapes every tuning screen in this app is built out of.
///
/// They were private to the assistant's settings, which was fine while it was
/// the only screen of its kind. It is not: the daily brief is tuned the same
/// way, from the same section of Settings, and a page that merely *resembles*
/// the one beside it is a page people notice is different without being able
/// to say why. Sharing the widgets is what makes two screens the same rather
/// than similar.
library;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// One labelled card, the same shape Settings uses for its groups.
class NexSettingsGroup extends StatelessWidget {
  const NexSettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: NexSpacing.sm,
              bottom: NexSpacing.sm,
            ),
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(NexRadius.lg),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: NexSpacing.md,
                      endIndent: NexSpacing.md,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled control inside a card: icon and name on one line, the control
/// itself under them at full width.
///
/// The choice cards need the whole width to stay readable, so this is not a
/// `ListTile` with a trailing widget — the label row is the ListTile's look
/// without its layout.
class NexSettingsField extends StatelessWidget {
  const NexSettingsField({
    required this.icon,
    required this.label,
    required this.child,
    this.note,
  });

  final IconData icon;
  final String label;
  final Widget child;

  /// A line under the control that only appears when it has something to say.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: NexSpacing.sm),
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          child,
          if (note case final text?) ...[
            const SizedBox(height: NexSpacing.sm),
            Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
