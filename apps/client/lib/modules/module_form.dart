import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// The "everything else" of a form, behind one button.
///
/// A form asks for the minimum first — what it is, and when — and keeps what
/// is optional here: a calm card that says what the extra questions are for,
/// which opens (with a short slide) into the fields themselves. Nothing a
/// person might find private is needed to begin, and a long form stops
/// looking like a wall.
///
/// The open state belongs to the form ([open], [onChanged]) so it can be kept
/// with a draft, and so a form that is correcting something saved opens it
/// from the start.
class NexMoreDetails extends StatelessWidget {
  const NexMoreDetails({
    super.key,
    required this.open,
    required this.onChanged,
    required this.title,
    required this.child,
    this.hint,
    this.icon = Icons.tune_outlined,
    this.toggleKey,
  });

  final bool open;
  final ValueChanged<bool> onChanged;

  /// The button's words: "Add details (optional)".
  final String title;

  /// One line on what they are for.
  final String? hint;
  final IconData icon;

  /// A key on the button, which exists only while the fields are closed.
  final Key? toggleKey;

  /// The optional fields, shown once open.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedSize(
      duration: NexMotion.of(context, NexMotion.standard),
      curve: NexMotion.curve,
      alignment: AlignmentDirectional.topStart,
      child: open
          ? child
          : Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(NexRadius.lg),
              child: InkWell(
                key: toggleKey,
                borderRadius: BorderRadius.circular(NexRadius.lg),
                onTap: () => onChanged(true),
                child: Padding(
                  padding: const EdgeInsets.all(NexSpacing.md),
                  child: Row(
                    children: [
                      Icon(icon, color: scheme.primary),
                      const SizedBox(width: NexSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.titleSmall),
                            if (hint case final hint?) ...[
                              const SizedBox(height: 2),
                              Text(
                                hint,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
