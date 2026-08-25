import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// The controls under a photo, shared by the preview and the crop step.
///
/// They used to be small icons in the app bar, which is where a photo editor
/// put its controls in 2014 and nowhere anyone reaches with a thumb. Camera
/// roll, Photos, every messaging app: the decision about a picture is made at
/// the bottom of the screen, at a size you can hit while holding the phone in
/// one hand.
///
/// Two tiers, both optional. [tools] are the small round things that change
/// the picture — rotate, draw — set on translucent white so they read against
/// any photo. [buttons] are the decisions, laid out across the full width at a
/// height that does not need aiming.
class NexPhotoActionBar extends StatelessWidget {
  const NexPhotoActionBar({
    super.key,
    this.tools = const [],
    required this.buttons,
  });

  final List<Widget> tools;

  /// One or two. Each takes an equal share of the width, so a single button
  /// spans the screen and a pair splits it.
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // A gradient rather than a bar: the photo runs behind it and stops at
      // the screen edge, so a hard line across it would cut the picture where
      // nothing about the picture changes.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xCC000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.lg,
            NexSpacing.md,
            NexSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tools.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final tool in tools)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.sm,
                        ),
                        child: tool,
                      ),
                  ],
                ),
                const SizedBox(height: NexSpacing.md),
              ],
              Row(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(width: NexSpacing.sm),
                    Expanded(child: buttons[i]),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One round control over a photo — rotate, draw.
///
/// Its own widget because the translucent disc is what makes an icon legible
/// on top of an arbitrary picture, and a bare `IconButton` over a white sky is
/// invisible.
class NexPhotoTool extends StatelessWidget {
  const NexPhotoTool({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;

  /// The tooltip, and the semantics label. Not drawn: the bar is over a photo
  /// and a row of captions there is clutter.
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: nexMinTapTarget,
          height: nexMinTapTarget,
          child: busy
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    ),
  );
}

/// The height a decision button gets down here.
///
/// Taller than Material's default 40. This is the last control between a photo
/// and a note, it is reached with a thumb at the bottom of a phone, and the
/// two apps everyone compares this to use something close to it.
const nexPhotoButtonHeight = 54.0;

/// The button that commits.
class NexPhotoPrimaryButton extends StatelessWidget {
  const NexPhotoPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(nexPhotoButtonHeight),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        textStyle: theme.textTheme.titleMedium,
      ),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: NexSpacing.sm),
                ],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );
  }
}

/// The button beside it that goes somewhere else first.
class NexPhotoSecondaryButton extends StatelessWidget {
  const NexPhotoSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(nexPhotoButtonHeight),
      foregroundColor: Colors.white,
      // White at a third, not the theme's outline: this button sits on a
      // photograph, and an outline picked to work against a page is not
      // guaranteed to be visible against anything.
      side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
      textStyle: Theme.of(context).textTheme.titleMedium,
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: NexSpacing.sm),
        ],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
