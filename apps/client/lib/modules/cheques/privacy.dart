import 'package:flutter/material.dart';

import 'strings.dart';

class ChequePrivacy extends StatefulWidget {
  const ChequePrivacy({super.key, required this.child});
  final Widget child;
  @override
  State<ChequePrivacy> createState() => _ChequePrivacyState();
}

class _ChequePrivacyState extends State<ChequePrivacy> {
  final value = ValueNotifier<bool>(false);
  @override
  void dispose() {
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ChequeVisibility(notifier: value, child: widget.child);
}

class ChequeVisibility extends InheritedNotifier<ValueNotifier<bool>> {
  const ChequeVisibility({
    super.key,
    required super.notifier,
    required super.child,
  });
  static ValueNotifier<bool>? of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<ChequeVisibility>()?.notifier;
}

bool chequeHidden(BuildContext c) => ChequeVisibility.of(c)?.value ?? false;
Widget chequePrivateRoute(BuildContext c, Widget child) =>
    ChequeVisibility(notifier: ChequeVisibility.of(c), child: child);

class ChequePrivacyButton extends StatelessWidget {
  const ChequePrivacyButton({super.key});
  @override
  Widget build(BuildContext context) {
    final v = ChequeVisibility.of(context);
    return IconButton(
      tooltip: chequeStrings(
        context,
        chequeHidden(context) ? 'showAmounts' : 'hideAmounts',
      ),
      icon: Icon(
        chequeHidden(context)
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
      ),
      onPressed: v == null ? null : () => v.value = !v.value,
    );
  }
}

class ChequePrivateInput extends StatelessWidget {
  const ChequePrivateInput({
    super.key,
    required this.hidden,
    required this.child,
  });
  final bool hidden;
  final Widget child;
  @override
  Widget build(BuildContext context) => hidden
      ? const SizedBox(
          height: kMinInteractiveDimension,
          child: Center(child: Text('••••')),
        )
      : child;
}
