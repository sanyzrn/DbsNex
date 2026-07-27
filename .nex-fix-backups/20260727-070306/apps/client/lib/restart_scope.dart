import 'package:flutter/widgets.dart';

class NexRestartScope extends InheritedWidget {
  const NexRestartScope({
    super.key,
    required this.restart,
    required super.child,
  });

  final VoidCallback restart;

  static NexRestartScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NexRestartScope>();
    assert(scope != null, 'NexRestartScope is missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant NexRestartScope oldWidget) => false;
}