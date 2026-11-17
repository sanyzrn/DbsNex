import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'card_number.dart';
import 'card_sheet.dart';
import 'iban.dart';
import 'module.dart';
import 'payment_cards.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

/// The book of cards and IBANs: one row per person, the number grouped the
/// way it is read aloud, and copy in one tap. Nothing is fetched, nothing is
/// sent; a card number is public information people give out to be paid.
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen>
    with StoreState<CardsScreen> {
  List<PaymentCard> _cards = const [];
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() => readRecords(() async {
    final cards = await allCards(widget.store);
    if (!mounted) return;
    setState(() => _cards = cards);
  });

  Future<void> _add({PaymentCard? existing}) async {
    final saved = await showCardSheet(
      context,
      widget.store,
      existing: existing,
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _copy(String text) async {
    final messenger = NexBannerHost.of(context);
    final copied = upgradeWord(context, 'cardCopied');
    await nexModuleCopyText(text);
    messenger?.show(message: copied);
  }

  Future<void> _delete(PaymentCard card) async {
    final messenger = NexBannerHost.of(context);
    final l10n = AppLocalizations.of(context);
    final deleted = upgradeWord(context, 'cardDeleted');
    final failure = lentStrings(context, 'saveError');
    final raw = await widget.store.get('card', card.id);
    if (raw == null) return;
    await widget.store.delete('card', card.id);
    if (!mounted) return;
    messenger?.show(
      message: deleted,
      actionLabel: l10n.undo,
      onAction: () => unawaited(
        widget.store.put('card', card.id, raw).catchError((Object _) {
          messenger.show(kind: NexBannerKind.failed, message: failure);
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'cardsTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        key: const ValueKey('cards-new'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: Text(strings(context, 'cardNew')),
      ),
      body: recordsBody(
        _cards.isEmpty
            ? NexEmptyState(
                icon: Icons.credit_card,
                message: strings(context, 'cardsEmpty'),
              )
            : ListView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.lg + nexBottomInset(context),
                ),
                children: [
                  for (final (index, card) in _cards.indexed)
                    NexGroupedRow(
                      index: index,
                      count: _cards.length,
                      child: _CardTile(
                        card: card,
                        onCopy: _copy,
                        onEdit: () => unawaited(_add(existing: card)),
                        onDelete: () => unawaited(_delete(card)),
                      ),
                    ),
                ],
              ),
        () => unawaited(_load()),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final PaymentCard card;
  final Future<void> Function(String text) onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final bank = bankOf(card.card);
    return ListTile(
      key: ValueKey('card-${card.id}'),
      onTap: onEdit,
      contentPadding: const EdgeInsetsDirectional.only(
        start: NexSpacing.md,
        end: NexSpacing.sm,
      ),
      title: Text(
        card.person.isEmpty
            ? strings(context, 'splitUnknownPerson')
            : card.person,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.card.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              groupCard(card.card),
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodyMedium?.copyWith(letterSpacing: 0.6),
            ),
            Text(
              bank == null
                  ? strings(context, 'cardBankUnknown')
                  : (persian ? bank.fa : bank.en),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (card.iban.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              groupIban(card.iban),
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (card.holder.isNotEmpty)
            Text(
              card.holder,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (card.card.isNotEmpty)
            IconButton(
              key: ValueKey('card-copy-${card.id}-card'),
              tooltip: strings(context, 'cardCopy'),
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => unawaited(onCopy(card.card)),
            ),
          if (card.iban.isNotEmpty)
            IconButton(
              key: ValueKey('card-copy-${card.id}-iban'),
              tooltip: strings(context, 'cardCopy'),
              icon: const Icon(Icons.account_balance_outlined),
              onPressed: () => unawaited(onCopy(card.iban)),
            ),
          IconButton(
            key: ValueKey('card-delete-${card.id}'),
            tooltip: strings(context, 'cardDelete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
