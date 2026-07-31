import 'package:flutter/material.dart';

import '../tokens/nex_tokens.dart';

/// What a surface shows when it holds nothing yet.
///
/// Every screen that could be empty had written its own version of this: the
/// same glyph-over-message column, but with the icon at 40 in one place and the
/// gap under it at 12 in one and 4 in another, and the colour reached for
/// through `outline` in one file and `Theme.of(context)` spelled out twice in
/// the next. They looked alike without being alike, so the two the user is most
/// likely to see back to back — Trash and Tags — did not quite line up.
///
/// [action] is for the empty state that can be acted on directly: Tags offers
/// "Create tag" here because an empty tag list is a thing the user can fix from
/// where they are standing. Trash offers nothing, because an empty trash is not
/// a problem.
class NexEmptyState extends StatelessWidget {
  const NexEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  /// Big enough to read as an illustration rather than as a control that
  /// stopped working — this is the one place in the app an icon is not
  /// something you tap.
  static const iconSize = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: theme.colorScheme.outline),
            const SizedBox(height: NexSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (action != null) ...[
              const SizedBox(height: NexSpacing.sm),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The spinner that stands in for an icon while its own action is running.
///
/// Sized to the icon it replaces, so the button it sits in does not change
/// width the moment it is pressed. Three call sites spelled this out by hand as
/// a `SizedBox` wrapping a `CircularProgressIndicator`, which is exactly the
/// kind of detail that drifts one number at a time.
class NexInlineSpinner extends StatelessWidget {
  const NexInlineSpinner({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(strokeWidth: 2),
  );
}
