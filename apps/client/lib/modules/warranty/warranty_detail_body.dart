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
                NexPopupMenuButton<String>(
                  key: const ValueKey('warranty-detail-menu'),
                  tooltip: strings(context, 'detailsTitle'),
                  onSelected: (value) => unawaited(_runAction(value)),
                  itemBuilder: (menuContext) => [
                    nexMenuItem(
                      value: 'edit',
                      icon: Icons.edit_outlined,
                      label: AppLocalizations.of(menuContext).edit,
                    ),
                    if (WarrantyModels.readArchived(body))
                      nexMenuItem(
                        value: 'unarchive',
                        icon: Icons.unarchive_outlined,
                        label: warrantyStrings(menuContext, 'unarchive'),
                      )
                    else
                      nexMenuItem(
                        value: 'archive',
                        icon: Icons.archive_outlined,
                        label: warrantyStrings(menuContext, 'archived'),
                      ),
                    nexMenuItem(
                      value: 'copyFile',
                      icon: Icons.copy_outlined,
                      label: warrantyStrings(menuContext, 'copyFile'),
                    ),
                    nexMenuItem(
                      value: 'shareFile',
                      icon: Icons.share_outlined,
                      label: warrantyStrings(menuContext, 'shareFile'),
                    ),
                    nexMenuItem(
                      value: 'delete',
                      icon: Icons.delete_outline,
                      label: AppLocalizations.of(menuContext).delete,
                      destructive: true,
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
                WarrantyFields.dayLabel(context, purchased),
              ),
            if (end != null)
              _row(
                context,
                Icons.event_available,
                strings(context, 'endsLabel'),
                WarrantyFields.dayLabel(context, end),
              ),
            if (months != null)
              _row(
                context,
                Icons.timelapse,
                strings(context, 'durationLabel'),
                months == 1
                    ? strings(context, 'oneMonth')
                    : strings(context, 'monthCount', {'count': months}),
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
            if (WarrantyModels.readString(body, 'receiptRef').trim().isEmpty &&
                WarrantyModels.readString(body, 'serial').trim().isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: NexSpacing.xs),
                child: Text(
                  strings(context, 'noProof'),
                  key: const ValueKey('warranty-no-proof'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (!WarrantyModels.readArchived(body)) ...[
              const SizedBox(height: NexSpacing.md),
              Text(
                strings(context, 'reminderNote'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // Opt-in: an OS alert for the end of the coverage or a claim
              // deadline. Wired to this record, so the platform cancels it
              // when the purchase is deleted or archived. Archived purchases
              // offer nothing here.
              NexModuleReminderControl(
                key: const ValueKey('warranty-reminders'),
                store: widget.store,
                sourceKind: WarrantyModels.warranty,
                sourceId: widget.record.id,
              ),
            ],
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
