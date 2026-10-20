import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';

/// An empty state that never overflows: centered exactly as before when it
/// fits, and scrolling when large text or a small screen makes it taller
/// than the body it lives in.
class ScrollSafeEmpty extends StatelessWidget {
  const ScrollSafeEmpty({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: child,
      ),
    ),
  );
}

/// Small module-local load/error boundary. Data stays visible during refresh.
mixin StoreState<T extends StatefulWidget> on State<T> {
  bool loading = true;
  int _generation = 0;
  bool loadFailed = false;

  Future<void> readRecords(Future<void> Function() read) async {
    final generation = ++_generation;
    try {
      await read();
      if (generation != _generation) return;
      if (mounted) {
        setState(() {
          loading = false;
          loadFailed = false;
        });
      }
    } catch (_) {
      if (generation != _generation) return;
      if (mounted) {
        setState(() {
          loading = false;
          loadFailed = true;
        });
      }
    }
  }

  void writeError() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(habitsStrings(context, 'saveError'))),
      );
    }
  }

  Widget recordsBody(Widget child, VoidCallback retry) {
    if (loading) return const Center(child: NexInlineSpinner());
    if (loadFailed) {
      return ScrollSafeEmpty(
        child: NexEmptyState(
          icon: Icons.cloud_off_outlined,
          message: habitsStrings(context, 'loadError'),
          action: TextButton(
            onPressed: retry,
            child: Text(habitsStrings(context, 'retry')),
          ),
        ),
      );
    }
    return child;
  }
}

/// Keeps asynchronous writes away from navigation and surfaces recoverable
/// failures without discarding the form contents. Each retry uses the same ID.
Future<bool> storeWrite(
  BuildContext context,
  Future<void> Function() write,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = habitsStrings(context, 'saveError');
  try {
    await write();
    return true;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return false;
  }
}
