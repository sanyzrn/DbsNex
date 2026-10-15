part of 'lens_pages.dart';

/// The saved comparisons: each restores into the calculator on a tap,
/// deleting offers Undo.
class LensSavedPage extends StatefulWidget {
  const LensSavedPage({
    super.key,
    required this.controller,
    required this.onOpen,
    this.onOpenUnit,
  });

  final PriceLensController controller;
  final ValueChanged<List<PriceOption>> onOpen;
  final ValueChanged<String?>? onOpenUnit;

  @override
  State<LensSavedPage> createState() => _LensSavedPageState();
}

class _LensSavedPageState extends State<LensSavedPage> {
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

  Future<void> _delete(SavedComparison comparison) async {
    final s = priceLensStrings;
    final answer = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) => NexAlertDialog(
        title: Text(s(dialogContext, 'deleteSavedTitle')),
        content: NexDialogBody(
          child: Text(s(dialogContext, 'savedDeleteBody')),
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
    final message = s(context, 'savedDeleted');
    final undoLabel = s(context, 'undo');
    try {
      await widget.controller.deleteComparison(comparison.id);
      if (mounted) {
        LensUndo.offer(
          messenger,
          message: message,
          undoLabel: undoLabel,
          failureMessage: s(context, 'undoFailed'),
          restore: () => widget.controller.restoreComparison(comparison),
        );
      }
    } catch (_) {
      if (mounted) lensWriteFailure(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    final saved = widget.controller.saved;
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'savedComparisons'))),
      body: SafeArea(
        child: widget.controller.readFailed
            ? LensReadError(controller: widget.controller)
            : saved.isEmpty && widget.controller.invalidSaved.isEmpty
            ? NexEmptyState(
                icon: Icons.calculate_outlined,
                message: s(context, 'noSaved'),
              )
            : ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.xl,
                ),
                children: [
                  for (final row in widget.controller.invalidSaved)
                    LensInvalidRow(
                      controller: widget.controller,
                      record: row,
                      kind: 'comparison',
                    ),
                  for (final comparison in saved)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        bottom: NexSpacing.xs,
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              s(context, 'comparisonOf', {
                                'n': comparison.options.length,
                                'date': lensFullDate(context, comparison.date),
                              }),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onOpenUnit?.call(comparison.commonUnitKey);
                              widget.onOpen(comparison.options);
                            },
                            child: Text(s(context, 'restoreToCalculator')),
                          ),
                          IconButton(
                            tooltip: s(context, 'delete'),
                            onPressed: () => _delete(comparison),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
