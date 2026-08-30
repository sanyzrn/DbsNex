import 'package:flutter/material.dart';

/// A switch drawn smaller than Material draws one.
///
/// Material 3 lays its switch out at 52x32 and offers no way to ask for less
/// — there is no size on `Switch`, and none on `SwitchThemeData` either. Next
/// to a 56px settings row carrying an icon, a title and a subtitle, that is
/// the loudest thing on the line, and it is the second time it has been
/// reported as out of proportion with everything around it. Shrinking the
/// thumb's tick and its tap padding, which is all the theme can reach, was
/// not enough.
///
/// So the real control is scaled into a smaller box. Scaling rather than
/// re-drawing on purpose: a hand-painted switch would have to reimplement the
/// thumb animation, the drag-to-toggle, the pressed overlay and the semantics
/// that say "switch, on" to a screen reader, and every one of those is a way
/// to be subtly worse than the platform for the sake of eight pixels.
///
/// The tap target does not shrink with it. This is meant to sit in the
/// trailing slot of a row that is itself tappable and at least 48 high — see
/// [NexSwitchTile] — so the thing a finger aims at is the whole line, which
/// is both larger than the switch ever was and easier to hit.
class NexSwitch extends StatelessWidget {
  const NexSwitch({super.key, required this.value, required this.onChanged});

  final bool value;

  /// Null disables it, as on any Material control.
  final ValueChanged<bool>? onChanged;

  /// What Material lays a switch out at once its tap padding is off.
  ///
  /// Kept as two numbers rather than a `Size`, because reading `.width` off a
  /// const `Size` is a property access and not a constant expression, so the
  /// scaled size below could not then be const.
  static const _materialWidth = 52.0;
  static const _materialHeight = 32.0;

  /// Enough to stop it dominating the row, not so much that it reads as a
  /// toy: a little under an iOS switch, which is 51x31.
  static const _scale = 0.8;

  static const Size size = Size(
    _materialWidth * _scale,
    _materialHeight * _scale,
  );

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: FittedBox(
      fit: BoxFit.contain,
      child: Switch(
        value: value,
        onChanged: onChanged,
        // Pinned here rather than left to the theme, because the scale factor
        // is only correct against a known size: with the tap padding on, the
        // control measures 52x48 and `BoxFit.contain` would fit that taller
        // box into the same width and shrink it further than intended.
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );
}

/// A settings row with a [NexSwitch] on the end.
///
/// Stands in for `SwitchListTile`, which builds its own `Switch` and gives no
/// way to hand it a different one. The parameters are the ones the app
/// actually used, so the call sites read the same.
///
/// [MergeSemantics] keeps what `SwitchListTile` gave for free: the row and the
/// control announce as one switch rather than as a label and a separate
/// toggle that happen to sit together.
class NexSwitchTile extends StatelessWidget {
  const NexSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.secondary,
    this.contentPadding,
  });

  final Widget title;
  final Widget? subtitle;

  /// The leading icon, named as `SwitchListTile` names it.
  final Widget? secondary;

  final EdgeInsetsGeometry? contentPadding;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: ListTile(
        // `SwitchListTile` greys its label when `onChanged` is null; a bare
        // `ListTile` with no `onTap` still paints as if it were live. Without
        // this, the intelligence rows that read "not supported by provider"
        // would look as available as the ones that are.
        enabled: onChanged != null,
        contentPadding: contentPadding,
        leading: secondary,
        title: title,
        subtitle: subtitle,
        trailing: NexSwitch(value: value, onChanged: onChanged),
        // The whole row, the way `SwitchListTile` behaves — and the reason
        // the switch itself is allowed to be small.
        onTap: onChanged == null ? null : () => onChanged(!value),
      ),
    );
  }
}
