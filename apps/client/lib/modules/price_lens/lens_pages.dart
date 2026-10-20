import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'money.dart';
import 'options.dart';
import 'price_lens_common.dart';
import 'strings.dart';
import 'comparison.dart';
import 'lens_undo.dart';
import 'history_status.dart';
part 'lens_saved_page.dart';

/// The opt-in pages: the price memory the person chose to keep, and
/// the saved comparisons. Nothing here is scraped, nothing is a
/// market rate — every line says "you entered this".

/// The price memory: earlier prices for the same product and package
/// specification, dated. Deleting a memory offers Undo.
class LensMemoryPage extends StatefulWidget {
  const LensMemoryPage({super.key, required this.controller});

  final PriceLensController controller;

  @override
  State<LensMemoryPage> createState() => _LensMemoryPageState();
}

class _LensMemoryPageState extends State<LensMemoryPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _delete(PriceMemory memory) async {
    final s = priceLensStrings;
    final answer = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) => NexAlertDialog(
        title: Text(s(dialogContext, 'deleteMemoryTitle')),
        content: NexDialogBody(
          child: Text(s(dialogContext, 'memoryDeleteBody')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s(dialogContext, 'cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            child: Text(s(dialogContext, 'delete')),
          ),
        ],
      ),
    );
    if (answer != 'delete' || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final message = s(context, 'memoryDeleted');
    final undoLabel = s(context, 'undo');
    try {
      await widget.controller.deleteMemory(memory.id);
      if (mounted) {
        LensUndo.offer(
          messenger,
          message: message,
          undoLabel: undoLabel,
          failureMessage: s(context, 'undoFailed'),
          restore: () => widget.controller.restoreMemory(memory),
        );
      }
    } catch (_) {
      if (mounted) lensWriteFailure(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = priceLensStrings;
    final persian = NexModuleStrings.persian(context);
    final memories = widget.controller.memories;
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'memoryTitle'))),
      body: SafeArea(
        child: widget.controller.readFailed
            ? LensReadError(controller: widget.controller)
            : memories.isEmpty && widget.controller.invalidMemories.isEmpty
            ? NexEmptyState(
                icon: Icons.bookmark_outline,
                message: s(context, 'memoryNone'),
                action: FilledButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.calculate_outlined),
                  label: Text(s(context, 'backToCalculator')),
                  // Material caps buttons at 40dp tall — a label a 2× text
                  // scale cannot fit into; let it grow with the words.
                  style: const ButtonStyle(
                    maximumSize: WidgetStatePropertyAll<Size?>(
                      Size(double.infinity, double.infinity),
                    ),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.xl,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      bottom: NexSpacing.md,
                    ),
                    child: Text(
                      s(context, 'memoryHint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final row in widget.controller.invalidMemories)
                    LensInvalidRow(
                      controller: widget.controller,
                      record: row,
                      kind: 'memory',
                    ),
                  for (final memory in memories)
                    _MemoryRow(
                      memory: memory,
                      persian: persian,
                      onDelete: () => _delete(memory),
                    ),
                ],
              ),
      ),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({
    required this.memory,
    required this.persian,
    required this.onDelete,
  });

  final PriceMemory memory;
  final bool persian;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    final exponent = priceExponentOf(memory.currency);
    final price =
        '${formatMinorFraction(memory.exactPaid, exponent, persian: persian)} '
        '${memory.currency}';
    final line = s(context, 'memoryOf', {
      'label': memory.label,
      'price': price,
      'date': lensFullDate(context, memory.date),
    });
    return Semantics(
      label: s(context, 'memorySemantics', {
        'label': memory.label,
        'price': price,
        'date': lensFullDate(context, memory.date),
      }),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.xs),
        child: Row(
          children: [
            Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
            IconButton(
              tooltip: s(context, 'memoryDelete'),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}
