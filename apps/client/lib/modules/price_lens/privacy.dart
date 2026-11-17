import 'package:flutter/material.dart';

import 'strings.dart';

class LensPrivacy extends StatefulWidget {
  const LensPrivacy({super.key, required this.child});
  final Widget child;
  @override
  State<LensPrivacy> createState() => _LensPrivacyState();
}

class _LensPrivacyState extends State<LensPrivacy> {
  final hideAmounts = ValueNotifier(false);
  @override
  void dispose() {
    hideAmounts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LensVisibility(notifier: hideAmounts, child: widget.child);
}

class LensVisibility extends InheritedNotifier<ValueNotifier<bool>> {
  const LensVisibility({
    super.key,
    required super.notifier,
    required super.child,
  });
  static ValueNotifier<bool>? of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<LensVisibility>()?.notifier;
}

bool lensAmountsHidden(BuildContext c) => LensVisibility.of(c)?.value ?? false;

/// Capture the notifier while the source context is active: route builders
/// may run again after a source row has been removed or a theme has changed.
WidgetBuilder lensRouteBuilder(BuildContext context, Widget child) {
  final visibility = LensVisibility.of(context);
  return (_) => LensVisibility(notifier: visibility, child: child);
}

class LensPrivacyButton extends StatelessWidget {
  const LensPrivacyButton({super.key});
  @override
  Widget build(BuildContext context) {
    final hidden = lensAmountsHidden(context),
        notifier = LensVisibility.of(context);
    return IconButton(
      tooltip: priceLensStrings(
        context,
        hidden ? 'showAmounts' : 'hideAmounts',
      ),
      onPressed: notifier == null
          ? null
          : () => notifier.value = !notifier.value,
      icon: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
    );
  }
}
