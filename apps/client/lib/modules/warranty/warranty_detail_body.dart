part of 'warranty_detail.dart';

extension _WarrantyDetailBody on _WarrantyDetailSheetState {
  Widget _view(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed || _body == null) {
      return _readError();
    }

    // A messenger of the sheet's own: a snackbar shown from inside this
    // sheet lands in the sheet rather than under it.
    return ScaffoldMessenger(
      child: Builder(
        builder: (inner) {
          _sheetMessenger = ScaffoldMessenger.of(inner);
          return PopScope(
            canPop: !_busy,
            child: AbsorbPointer(absorbing: _busy, child: _sheet(inner)),
          );
        },
      ),
    );
  }

  Widget _sheet(BuildContext context) {
    final body = _body!;
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    final product = WarrantyModels.readString(body, 'product');
    final purchased = WarrantyModels.readDate(body, 'purchasedAt');
    final end = WarrantyModels.readDate(body, 'coverageEnd');
    final months = WarrantyModels.readCount(body, 'durationMonths');
    final amount = WarrantyModels.readCount(body, 'amountRials');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(product, style: theme.textTheme.headlineSmall),
                ),
                PopupMenuButton<String>(
                  key: const ValueKey('warranty-detail-menu'),
                  tooltip: strings(context, 'detailsTitle'),
                  onSelected: (value) => unawaited(_runAction(value)),
                  itemBuilder: (menuContext) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(AppLocalizations.of(menuContext).edit),
                    ),
                    if (WarrantyModels.readArchived(body))
                      PopupMenuItem(
                        value: 'unarchive',
                        child: Text(warrantyStrings(menuContext, 'unarchive')),
                      )
                    else
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(warrantyStrings(menuContext, 'archived')),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(AppLocalizations.of(menuContext).delete),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.md),
            if (purchased != null)
              _row(
                context,
                Icons.calendar_today_outlined,
                strings(context, 'purchasedLabel'),
                WarrantyFields.ymd(context, purchased),
              ),
            if (end != null)
              _row(
                context,
                Icons.event_available,
                strings(context, 'endsLabel'),
                WarrantyFields.ymd(context, end),
              ),
            if (months != null)
              _row(
                context,
                Icons.timelapse,
                strings(context, 'durationLabel'),
                strings(context, 'monthCount', {'count': months}),
              ),
            if (amount != null)
              _row(
                context,
                Icons.payments_outlined,
                strings(context, 'amountLabel'),
                WarrantyFields.money(context, amount),
              ),
            for (final MapEntry(:key, :value) in {
              'merchant': 'merchantLabel',
              'serial': 'serialLabel',
              'receiptRef': 'receiptLabel',
              'coverageType': 'typeLabel',
              'note': 'noteLabel',
            }.entries)
              if (WarrantyModels.readString(body, key).isNotEmpty)
                _row(
                  context,
                  Icons.receipt_long_outlined,
                  strings(context, value),
                  WarrantyModels.readString(body, key),
                ),
            const SizedBox(height: NexSpacing.lg),
            WarrantyClaimsSection(
              claims: _claims,
              onAdd: _addClaim,
              onDeleteClaim: _deleteClaim,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: NexSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    ),
  );
}
