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

  /// Consumes the RestartRequired token returned by a restore and performs the
  /// rebuild. Pairing the token with this call makes it impossible to restore a
  /// backup and then forget to rebuild the service graph.
  static void restartAfter(BuildContext context, Object token) {
    of(context).restart();
  }

  @override
  bool updateShouldNotify(covariant NexRestartScope oldWidget) => false;
}
