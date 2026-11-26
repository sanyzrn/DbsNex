part of 'warranty_detail.dart';

extension _WarrantyDetailBody on _WarrantyDetailPageState {
  Widget _view(BuildContext context) {
    final strings = warrantyStrings;
    final product = WarrantyModels.readString(
      _body ?? widget.record.body,
      'product',
    );
    final title = product.isEmpty ? strings(context, 'detailsTitle') : product;
    final actions = <Widget>[
      if (_body != null) _editAction(context),
      if (_body != null) _menu(context),
    ];
    if (widget.inSheet) {
      // The notification destination opens this inside a sheet: no scaffold
      // and no app bar, only the title row and the record.
      return Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(child: _bodyArea(context)),
        ],
      );
    }
    return Scaffold(
      appBar: NexAppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: actions,
      ),
      body: _bodyArea(context),
    );
  }

  Widget _bodyArea(BuildContext context) => _loading
      ? const Center(child: NexInlineSpinner())
      : _loadFailed || _body == null
      ? _readError()
      : _content(context, _body!);

  Widget _editAction(BuildContext context) => IconButton(
    key: const ValueKey('warranty-detail-edit'),
    tooltip: AppLocalizations.of(context).edit,
    icon: const Icon(Icons.edit_outlined),
    onPressed: _busy ? null : () => unawaited(_edit()),
  );

  Widget _menu(BuildContext context) => NexPopupMenuButton<String>(
    key: const ValueKey('warranty-detail-menu'),
    tooltip: warrantyStrings(context, 'detailsTitle'),
    onSelected: (value) => unawaited(_runAction(value)),
    itemBuilder: (menuContext) => [
      if (WarrantyModels.readArchived(_body!))
        nexMenuItem(
          value: 'unarchive',
          icon: Icons.unarchive_outlined,
          label: warrantyStrings(menuContext, 'unarchive'),
        )
      else
        nexMenuItem(
          value: 'archive',
          icon: Icons.archive_outlined,
          label: warrantyStrings(menuContext, 'archive'),
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
  );

  Widget _readError() => NexEmptyState(
    icon: Icons.cloud_off_outlined,
    message: warrantyStrings(context, 'loadFailed'),
    action: TextButton(
      onPressed: () => unawaited(_load()),
      child: Text(warrantyStrings(context, 'retry')),
    ),
  );

  Widget _content(BuildContext context, Map<String, Object?> body) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    final end = WarrantyModels.readDate(body, 'coverageEnd');
    final purchased = WarrantyModels.readDate(body, 'purchasedAt');
    final months = WarrantyModels.readCount(body, 'durationMonths');
    final amount = WarrantyModels.readCount(body, 'amountRials');
    final kind = WarrantyModels.readCoverKind(body);
    final phone = WarrantyModels.readString(body, 'supportPhone');
    final registry = WarrantyModels.readRegistry(body);
    String value(String key) => WarrantyModels.readString(body, key);
    final archived = WarrantyModels.readArchived(body);

    return ListView(
      key: const ValueKey('warranty-detail-scroll'),
      padding: EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.xl + nexBottomInset(context),
      ),
      children: [
        _WarrantyStatusCard(end: end),
        if (archived) ...[
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'archived'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: NexSpacing.lg),
        NexShelfHeading(
          icon: Icons.shopping_bag_outlined,
          title: strings(context, 'identityTitle'),
        ),
        const SizedBox(height: NexSpacing.sm),
        // What the product is, first: a desk asks for the brand and the
        // model before anything else, and they were typed in the editor.
        if (value('brand').isNotEmpty)
          _row(
            context,
            Icons.local_offer_outlined,
            strings(context, 'brand'),
            Text(value('brand'), style: theme.textTheme.bodyLarge),
          ),
        if (value('model').isNotEmpty)
          _row(
            context,
            Icons.devices_outlined,
            strings(context, 'model'),
            WarrantyFields.ltr(
              value('model'),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        if (value('category').isNotEmpty)
          _row(
            context,
            Icons.category_outlined,
            strings(context, 'category'),
            Text(value('category'), style: theme.textTheme.bodyLarge),
          ),
        if (purchased != null)
          _row(
            context,
            Icons.calendar_today_outlined,
            strings(context, 'purchasedLabel'),
            Text(
              WarrantyFields.dayLabel(context, purchased),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        if (value('merchant').isNotEmpty)
          _row(
            context,
            Icons.storefront_outlined,
            strings(context, 'merchantLabel'),
            Text(value('merchant'), style: theme.textTheme.bodyLarge),
          ),
        if (value('receiptRef').isNotEmpty)
          _row(
            context,
            Icons.receipt_long_outlined,
            strings(context, 'receiptLabel'),
            WarrantyFields.ltr(
              value('receiptRef'),
              style: theme.textTheme.bodyLarge,
            ),
            trailing: _copyValue(
              context,
              'warranty-copy-receipt',
              value('receiptRef'),
            ),
          ),
        if (amount != null)
          _row(
            context,
            Icons.payments_outlined,
            strings(context, 'amountLabel'),
            Text(
              WarrantyFields.money(context, amount),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        if (value('note').isNotEmpty)
          _row(
            context,
            Icons.notes_outlined,
            strings(context, 'noteLabel'),
            Text(value('note'), style: theme.textTheme.bodyLarge),
          ),
        const SizedBox(height: NexSpacing.lg),
        NexShelfHeading(
          icon: Icons.verified_user_outlined,
          title: strings(context, 'supportTitle'),
        ),
        const SizedBox(height: NexSpacing.sm),
        if (end != null)
          _row(
            context,
            Icons.event_available_outlined,
            strings(context, 'endsLabel'),
            Text(
              WarrantyFields.dayLabel(context, end),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        // A zero can only come from a record this version never wrote;
        // a coverage of "0 months" is not a fact worth showing.
        if (months != null && months > 0)
          _row(
            context,
            Icons.timelapse_outlined,
            strings(context, 'durationLabel'),
            Text(
              months == 1
                  ? strings(context, 'oneMonth')
                  : strings(context, 'monthCount', {'count': months}),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        if (kind.isNotEmpty)
          _row(
            context,
            Icons.workspace_premium_outlined,
            strings(context, 'kindLabel'),
            Text(
              WarrantyFields.coverKind(context, kind),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        if (value('company').isNotEmpty)
          _row(
            context,
            Icons.business_outlined,
            strings(context, 'companyLabel'),
            Text(value('company'), style: theme.textTheme.bodyLarge),
          ),
        if (phone.isNotEmpty)
          _row(
            context,
            Icons.support_agent_outlined,
            strings(context, 'phoneLabel'),
            WarrantyFields.ltr(phone, style: theme.textTheme.bodyLarge),
            trailing: IconButton(
              key: const ValueKey('warranty-copy-phone'),
              tooltip: strings(context, 'copyPhone'),
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => unawaited(_copyPhone(phone)),
            ),
          ),
        if (value('cardNumber').isNotEmpty)
          _row(
            context,
            Icons.credit_card_outlined,
            strings(context, 'cardLabel'),
            WarrantyFields.ltr(
              value('cardNumber'),
              style: theme.textTheme.bodyLarge,
            ),
            trailing: _copyValue(
              context,
              'warranty-copy-card',
              value('cardNumber'),
            ),
          ),
        if (value('serial').isNotEmpty)
          _row(
            context,
            Icons.qr_code_2_outlined,
            strings(context, 'serialLabel'),
            WarrantyFields.ltr(
              value('serial'),
              style: theme.textTheme.bodyLarge,
            ),
            trailing: _copyValue(
              context,
              'warranty-copy-serial',
              value('serial'),
            ),
          ),
        if (registry.isNotEmpty)
          _row(
            context,
            Icons.badge_outlined,
            strings(context, 'registryValue'),
            Text(
              WarrantyFields.registry(context, registry),
              style: theme.textTheme.bodyLarge,
            ),
          ),
        if (value('coverageType').isNotEmpty)
          _row(
            context,
            Icons.label_outline,
            strings(context, 'typeLabel'),
            Text(value('coverageType'), style: theme.textTheme.bodyLarge),
          ),
        if (value('receiptRef').trim().isEmpty &&
            value('serial').trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: NexSpacing.sm),
            child: Text(
              strings(context, 'noProof'),
              key: const ValueKey('warranty-no-proof'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (!archived) ...[
          const SizedBox(height: NexSpacing.lg),
          Text(
            strings(context, 'reminderNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Opt-in: an OS alert for the end of the cover or a claim
          // deadline. Wired to this record, so the platform cancels it when
          // the purchase is deleted or archived. The alert names the
          // purchase and its day — "you have a reminder" says nothing a
          // person can act on — and the picker opens on the end date,
          // because that is the day worth choosing around.
          NexModuleReminderControl(
            key: const ValueKey('warranty-reminders'),
            store: widget.store,
            sourceKind: WarrantyModels.warranty,
            sourceId: widget.record.id,
            initial: end,
            body: end == null
                ? null
                : warrantyStrings(context, 'reminderBody', {
                    'name': value('product').trim().isEmpty
                        ? strings(context, 'detailsTitle')
                        : value('product').trim(),
                    'date': WarrantyFields.dayLabel(context, end),
                  }),
          ),
        ],
        const SizedBox(height: NexSpacing.lg),
        WarrantyClaimsSection(
          claims: _claims,
          onAdd: _addClaim,
          onDeleteClaim: _deleteClaim,
        ),
      ],
    );
  }
}
