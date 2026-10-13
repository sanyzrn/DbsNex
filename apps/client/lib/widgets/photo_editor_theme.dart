import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// The photo editors are dark whatever the app is: a picture is judged
/// against black, the way every camera and gallery shows it.
///
/// They used to take the app's own theme over a black page, so in the light
/// theme the controls drawn in its colours — the Draw/Text switch, the undo
/// and clear buttons — came out dark grey on near-black and all but vanished.
/// This is the dark theme in the person's own accent and typeface, so the
/// editor is still theirs.
class NexPhotoEditorTheme extends StatelessWidget {
  const NexPhotoEditorTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final current = Theme.of(context);
    return Theme(
      data: nexDarkTheme(
        fontFamily: current.textTheme.bodyMedium?.fontFamily,
        accentSeed: current.colorScheme.primary,
      ),
      child: child,
    );
  }
}

/// A round tool under a photo: an icon in a translucent disc, its name
/// beneath. Dimmed while it cannot be used.
class NexPhotoTool extends StatelessWidget {
  const NexPhotoTool({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onPressed,
        radius: 36,
        child: AnimatedOpacity(
          duration: NexMotion.fast,
          opacity: enabled ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: NexMotion.fast,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? scheme.primary
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: selected ? scheme.onPrimary : Colors.white,
                  ),
                ),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
