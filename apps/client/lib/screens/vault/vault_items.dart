part of '../vault_screen.dart';

/// The vault's list and what each item shows: logins, bank cards, their
/// fields and menus.
extension _VaultItems on _VaultScreenState {
  Widget _list(AppLocalizations l, ThemeData theme) {
    final query = search.text.trim().toLowerCase();
    final items =
        entries
            .where(
              (e) =>
                  e.kind == widget.kind &&
                  (widget.focusId == null || e.id == widget.focusId) &&
                  (!favorites || e.favorite) &&
                  [
                    e.title,
                    e.value('login'),
                    e.value('website'),
                    e.value('bank'),
                    e.value('holder'),
                  ].join(' ').toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) {
            final favorite = (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0);
            return favorite != 0
                ? favorite
                : b.updatedAt.compareTo(a.updatedAt);
          });
    final password = widget.kind == VaultKind.password;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: NexAutoDirection(
                controller: search,
                builder: (context, direction) => TextField(
                  controller: search,
                  textDirection: direction,
                  textAlign: TextAlign.start,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  onChanged: (_) {
                    _touch();
                    _rebuild(() {});
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l.vaultSearch,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: l.vaultFavorites,
              isSelected: favorites,
              onPressed: () => _rebuild(() => favorites = !favorites),
              icon: const Icon(Icons.star_outline_rounded),
              selectedIcon: const Icon(Icons.star_rounded),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: password ? l.vaultAddPassword : l.vaultAddCard,
              onPressed: busy || draft != null
                  ? null
                  : () => _edit(VaultStore.empty(widget.kind)),
              icon: Icon(
                password ? Icons.add_moderator_outlined : Icons.add_card,
              ),
            ),
          ],
        ),
        if (draft != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(l.vaultResume),
                subtitle: Text(
                  draft!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(draft!),
              ),
            ),
          ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(
                  password ? Icons.key_outlined : Icons.credit_card,
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  query.isNotEmpty || favorites
                      ? l.vaultNoResults
                      : l.vaultEmpty,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(l.vaultEmptyHint, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy || draft != null
                      ? null
                      : () => _edit(VaultStore.empty(widget.kind)),
                  icon: Icon(
                    password ? Icons.add_moderator_outlined : Icons.add_card,
                  ),
                  label: Text(password ? l.vaultAddPassword : l.vaultAddCard),
                ),
              ],
            ),
          ),
        for (final entry in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: widget.picking
                ? Card(
                    key: ValueKey('vault-pick-${entry.id}'),
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, entry.id),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _bankCard(theme, entry, menu: null, onTap: null),
                      ),
                    ),
                  )
                : entry.kind == VaultKind.card
                ? _cardItem(l, theme, entry)
                : _passwordItem(l, theme, entry),
          ),
        const SizedBox(height: 12),
        Text(l.vaultBackupHint, style: theme.textTheme.bodySmall),
      ],
    );
  }

  /// Everything about one password on the list itself.
  ///
  /// There used to be a details page between the list and the value, which
  /// made the most common thing anyone does here — copy a password — cost an
  /// extra tap and a page transition every time.
  Widget _passwordItem(AppLocalizations l, ThemeData theme, VaultEntry entry) {
    final scheme = theme.colorScheme;
    return Card(
      key: ValueKey('vault-item-${entry.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.key_rounded,
                    size: 20,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (entry.favorite)
                  Icon(Icons.star_rounded, size: 20, color: scheme.primary),
                _itemMenu(l, entry),
              ],
            ),
            for (final (key, label) in [
              ('login', l.vaultLogin),
              ('password', l.vaultPassword),
              ('website', l.vaultWebsite),
              ('notes', l.vaultNotes),
            ])
              if (entry.value(key).isNotEmpty)
                _fieldRow(theme, entry, key, label),
          ],
        ),
      ),
    );
  }

  /// The card itself, then every detail under it, copyable in one tap.
  Widget _cardItem(AppLocalizations l, ThemeData theme, VaultEntry entry) {
    return Card(
      key: ValueKey('vault-item-${entry.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bankCard(
              theme,
              entry,
              menu: _itemMenu(l, entry),
              onTap: () => _copy(
                '${entry.id}:number',
                vaultCardDigits(entry.value('number')),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (key, label) in [
                    ('number', l.vaultNumber),
                    ('expiry', l.vaultExpiry),
                    ('iban', l.vaultIban),
                    ('account', l.vaultAccount),
                    ('holder', l.vaultHolder),
                    ('bank', l.vaultBank),
                    ('notes', l.vaultNotes),
                  ])
                    if (entry.value(key).isNotEmpty)
                      _fieldRow(theme, entry, key, label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemMenu(AppLocalizations l, VaultEntry entry) =>
      PopupMenuButton<String>(
        tooltip: nexLabel(context, 'More', 'بیشتر'),
        enabled: !busy,
        icon: const Icon(Icons.more_vert),
        onSelected: (choice) {
          _touch();
          switch (choice) {
            case 'edit':
              if (draft == null) _edit(entry);
            case 'favorite':
              unawaited(_toggleFavorite(entry));
            case 'delete':
              unawaited(_confirmDelete(entry));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            enabled: draft == null,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: Text(l.vaultEdit),
            ),
          ),
          PopupMenuItem(
            value: 'favorite',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                entry.favorite ? Icons.star_rounded : Icons.star_outline,
              ),
              title: Text(l.vaultFavorite),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline),
              title: Text(l.vaultDelete),
            ),
          ),
        ],
      );

  static const _ltrFields = {
    'password',
    'number',
    'iban',
    'expiry',
    'account',
    'website',
    'login',
  };

  /// One labelled value. The whole row copies; the icon says it did.
  Widget _fieldRow(
    ThemeData theme,
    VaultEntry entry,
    String key,
    String label,
  ) {
    final l = AppLocalizations.of(context);
    final id = '${entry.id}:$key';
    final copied = copiedField == id;
    final raw = entry.value(key);
    final shown = key == 'number' ? _groupDigits(vaultCardDigits(raw)) : raw;
    final value = key == 'number' ? vaultCardDigits(raw) : raw;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _copy(id, value),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 2, top: 2, bottom: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    shown,
                    textDirection: _ltrFields.contains(key)
                        ? TextDirection.ltr
                        : null,
                    maxLines: key == 'notes' ? 6 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: _ltrFields.contains(key)
                          ? const [FontFeature.tabularFigures()]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: copied ? l.vaultCopied : '${l.copy} · $label',
              onPressed: () => _copy(id, value),
              icon: Icon(
                copied ? Icons.check_rounded : Icons.copy_outlined,
                size: 20,
                color: copied ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _groupDigits(String digits) => [
    for (var i = 0; i < digits.length; i += 4)
      digits.substring(i, i + 4 > digits.length ? digits.length : i + 4),
  ].join(' ');

  Widget _bankCard(
    ThemeData theme,
    VaultEntry entry, {
    VoidCallback? onTap,
    Widget? menu,
  }) {
    final number = vaultCardDigits(entry.value('number'));
    final chosen = nexParseTagColor(entry.value('color'));
    final base = chosen ?? theme.colorScheme.primaryContainer;
    final second = chosen == null
        ? theme.colorScheme.secondaryContainer
        : Color.lerp(chosen, Colors.black, 0.35)!;
    final ink =
        ThemeData.estimateBrightnessForColor(Color.lerp(base, second, .5)!) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF14161A);
    final foreground = chosen == null
        ? theme.colorScheme.onPrimaryContainer
        : ink;
    return AspectRatio(
      aspectRatio: 1.9,
      child: Material(
        color: base,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [base, second],
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 4, 16),
            child: IconTheme.merge(
              data: IconThemeData(color: foreground),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: foreground),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.credit_card),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: foreground,
                            ),
                          ),
                        ),
                        if (entry.favorite)
                          const Icon(Icons.star_rounded, size: 20),
                        ?menu,
                        if (menu == null) const SizedBox(height: 48),
                      ],
                    ),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _groupDigits(number),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 22,
                          letterSpacing: 1.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.value('holder'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (entry.value('expiry').isNotEmpty)
                            Text(
                              entry.value('expiry'),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
