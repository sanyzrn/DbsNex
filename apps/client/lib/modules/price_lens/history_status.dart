import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'controller.dart';
import 'strings.dart';
import 'lens_undo.dart';

void lensWriteFailure(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(priceLensStrings(context, 'saveFailed'))),
    );

class LensReadError extends StatelessWidget {
  const LensReadError({super.key, required this.controller});
  final PriceLensController controller;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(NexSpacing.md),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(priceLensStrings(context, 'loadFailed')),
        TextButton(
          onPressed: () => unawaited(controller.load()),
          child: Text(priceLensStrings(context, 'retry')),
        ),
      ],
    ),
  );
}

/// Invalid history is still manageable, and is never a price comparison.
class LensInvalidRow extends StatelessWidget {
  const LensInvalidRow({
    super.key,
    required this.controller,
    required this.record,
    required this.kind,
  });
  final PriceLensController controller;
  final ModuleRecord record;
  final String kind;
  Future<void> _delete(BuildContext context) async {
    final s = priceLensStrings;
    final approved = await nexShowDialog<bool>(
      context: context,
      builder: (dialog) => NexAlertDialog(
        title: Text(s(dialog, 'incompleteDelete')),
        content: NexDialogBody(child: Text(s(dialog, 'incompleteDeleteBody'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(s(dialog, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s(dialog, 'delete')),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context),
        message = s(context, 'memoryDeleted'),
        undo = s(context, 'undo'),
        failure = s(context, 'undoFailed');
    try {
      if (kind == 'memory') {
        await controller.deleteMemory(record.id);
      } else {
        await controller.deleteComparison(record.id);
      }
      if (context.mounted) {
        LensUndo.offer(
          messenger,
          message: message,
          undoLabel: undo,
          failureMessage: failure,
          restore: () => controller.restore(kind, record.id),
        );
      }
    } catch (_) {
      if (context.mounted) lensWriteFailure(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(priceLensStrings(context, 'incompleteHistory')),
    subtitle: Text(
      record.body['label'] is String
          ? record.body['label'] as String
          : record.id,
    ),
    trailing: IconButton(
      tooltip: priceLensStrings(context, 'delete'),
      onPressed: () => unawaited(_delete(context)),
      icon: const Icon(Icons.delete_outline),
    ),
  );
}
