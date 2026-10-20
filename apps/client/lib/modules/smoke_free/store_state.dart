import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';

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
        SnackBar(content: Text(smokeFreeStrings(context, 'saveError'))),
      );
    }
  }

  Widget recordsBody(Widget child, VoidCallback retry) {
    if (loading) return const Center(child: NexInlineSpinner());
    if (loadFailed) {
      return NexEmptyState(
        icon: Icons.cloud_off_outlined,
        message: smokeFreeStrings(context, 'loadError'),
        action: TextButton(
          onPressed: retry,
          // Material's default caps a text button at 40 px tall, which a
          // 2× text scale cannot fit into; let it grow with the words.
          style: const ButtonStyle(
            maximumSize: WidgetStatePropertyAll<Size?>(
              Size(double.infinity, double.infinity),
            ),
          ),
          child: Text(smokeFreeStrings(context, 'retry')),
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
  final message = smokeFreeStrings(context, 'saveError');
  try {
    await write();
    return true;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return false;
  }
}
