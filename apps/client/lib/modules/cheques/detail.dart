import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'editor.dart';
import 'event_editor.dart';
import 'model.dart';
import 'reminders.dart';
import 'repository.dart';
import 'strings.dart';
import 'privacy.dart';
import 'values.dart';
import 'widgets.dart';
import 'share.dart';

class ChequeDetail extends StatefulWidget {
  const ChequeDetail({super.key, required this.repo, required this.id});
  final ChequeRepository repo;
  final String id;
  @override
  State<ChequeDetail> createState() => _ChequeDetailState();
}

class _ChequeDetailState extends State<ChequeDetail> {
  Cheque? _cheque;
  bool _loading = true, _failed = false, _busy = false;
  int _generation = 0;
  StreamSubscription<void>? _changes;
  @override
  void initState() {
    super.initState();
    _changes = widget.repo.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final raw = await widget.repo.store.get('cheque', widget.id);
      if (mounted && generation == _generation) {
        setState(() {
          _cheque = raw == null ? null : Cheque(widget.id, raw);
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _delete(Cheque c) async {
    if (_busy) return;
    final s = chequeStrings;
    final yes = await nexShowDialog<bool>(
      context: context,
      builder: (x) => NexAlertDialog(
        title: Text(s(x, 'deleteAsk')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x),
            child: Text(AppLocalizations.of(x).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(x, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(x).colorScheme.error,
            ),
            child: Text(s(x, 'delete')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final repo = widget.repo,
        host = NexBannerHost.of(context),
        l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final raw = await repo.delete(c);
      var restoring = false;
      host?.show(
        message: s.text(l10n, 'deleted'),
        actionLabel: s.text(l10n, 'undo'),
        onAction: () async {
          if (restoring) return;
          restoring = true;
          try {
            await repo.restore(c.id, raw);
            final ok = await armCheque(repo.store, Cheque(c.id, raw), l10n);
            if (!ok) {
              host.show(
                message: s.text(l10n, 'remindError'),
                kind: NexBannerKind.failed,
              );
            }
          } catch (e) {
            host.show(
              message: s.text(l10n, e is ChequeFailure ? e.code : 'saveError'),
              kind: NexBannerKind.failed,
            );
          } finally {
            restoring = false;
          }
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        nexShowBanner(
          context,
          message: s(context, e is ChequeFailure ? e.code : 'saveError'),
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverse(Cheque c) async {
    final s = chequeStrings;
    final yes = await nexShowDialog<bool>(
      context: context,
      builder: (x) => NexAlertDialog(
        title: Text(s(x, 'reverseAsk')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x),
            child: Text(AppLocalizations.of(x).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(x, true),
            child: Text(s(x, 'reverse')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.repo.reverseLast(c);
      if (!mounted) return;
      var ok = true;
      try {
        ok = await armCheque(
          widget.repo.store,
          updated,
          AppLocalizations.of(context),
        );
      } catch (_) {
        ok = false;
      }
      if (!ok && mounted) {
        nexShowBanner(
          context,
          message: s(context, 'remindError'),
          kind: NexBannerKind.failed,
        );
      }
    } catch (e) {
      if (mounted) {
        nexShowBanner(
          context,
          message: s(context, e is ChequeFailure ? e.code : 'saveError'),
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _money(Cheque c, String title, BigInt value) => Padding(
    padding: const EdgeInsets.only(bottom: NexSpacing.sm),
    child: Text(
      '${chequeStrings(context, title)}: ${chequeMoney(context, value, unit: c.unit)} ${chequeStrings(context, c.unit)}',
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = _cheque, s = chequeStrings;
    return Scaffold(
      appBar: NexAppBar(
        title: Text(
          c?.party.isNotEmpty == true ? c!.party : s(context, 'title'),
        ),
        actions: [
          const ChequePrivacyButton(),
          if (c != null && c.valid && !_failed)
            IconButton(
              tooltip: s(context, 'share'),
              onPressed: () => shareCheque(context, c),
              icon: const Icon(Icons.share_outlined),
            ),
          if (c != null && !_failed) ...[
            if (c.valid)
              IconButton(
                tooltip: s(context, 'edit'),
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        NexPageRoute(
                          builder: (_) => chequePrivateRoute(
                            context,
                            ChequeEditor(repo: widget.repo, cheque: c),
                          ),
                        ),
                      ),
                icon: const Icon(Icons.edit_outlined),
              ),
            IconButton(
              tooltip: s(context, 'delete'),
              onPressed: _busy ? null : () => _delete(c),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? NexEmptyState(
              icon: Icons.refresh,
              message: s(context, 'readError'),
              action: TextButton(
                onPressed: _load,
                child: Text(s(context, 'retry')),
              ),
            )
          : c == null
          ? NexEmptyState(
              icon: Icons.receipt_long_outlined,
              message: s(context, 'noResults'),
            )
          : !c.valid
          ? Padding(
              padding: const EdgeInsets.all(NexSpacing.md),
              child: Text(s(context, 'invalid')),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.xl + nexBottomInset(context),
              ),
              children: [
                NexPanel(
                  title: s(context, 'status_${c.status}'),
                  icon: Icons.receipt_long_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${s(context, c.direction)} · ${s(context, c.purpose)}',
                      ),
                      const SizedBox(height: NexSpacing.md),
                      _money(c, 'amount', c.face!),
                      _money(c, 'paid', c.paid),
                      _money(c, 'remaining', c.remaining),
                      if (c.actionDay != null)
                        Text(
                          '${s(context, c.purpose == 'guarantee' ? 'followUp' : 'due')}: ${nexModuleDateLabel(context, c.actionDay!)}',
                        ),
                      for (final key in [
                        'bank',
                        'account',
                        'number',
                        'sayad',
                        'note',
                      ])
                        if (c.text(key).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: NexSpacing.sm),
                            child: NexTextDirection(
                              text: c.text(key),
                              child: Text('${s(context, key)}: ${c.text(key)}'),
                            ),
                          ),
                      const SizedBox(height: NexSpacing.md),
                      Text(
                        '${s(context, 'sayadState')}: ${s(context, 'sayad_${c.text('sayadState')}')}',
                      ),
                      if (chequeDay(c.raw['sayadCheckedDay'])
                          case final DateTime checked)
                        Text(nexModuleDateLabel(context, checked)),
                      Text(
                        s(context, 'sayadNotice'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                if (c.events.length < 500) ...[
                  if (!c.closed &&
                      c.purpose == 'payment' &&
                      c.remaining > BigInt.zero)
                    FilledButton.icon(
                      key: const ValueKey('cheque-settle'),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push<void>(
                              NexPageRoute(
                                builder: (_) => chequePrivateRoute(
                                  context,
                                  ChequeEventEditor(
                                    repo: widget.repo,
                                    cheque: c,
                                    payment: true,
                                  ),
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(s(context, 'settle')),
                    ),
                  if (c.remaining > BigInt.zero)
                    TextButton.icon(
                      key: const ValueKey('cheque-status'),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push<void>(
                              NexPageRoute(
                                builder: (_) => chequePrivateRoute(
                                  context,
                                  ChequeEventEditor(
                                    repo: widget.repo,
                                    cheque: c,
                                    payment: false,
                                  ),
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(s(context, 'statusChange')),
                    ),
                ] else
                  Text(s(context, 'eventLimit')),
                const SizedBox(height: NexSpacing.md),
                NexShelfHeading(
                  icon: Icons.history,
                  title: s(context, 'history'),
                ),
                if (c.events.isEmpty) Text(s(context, 'noHistory')),
                if (c.locked)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _reverse(c),
                    icon: const Icon(Icons.undo),
                    label: Text(s(context, 'reverse')),
                  ),
                for (final e in c.events.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NexSpacing.sm),
                    child: NexPanel(
                      title:
                          '${e['kind'] == 'payment' ? s(context, 'paymentEvent') : s(context, 'status_${e['next']}')}${e['voided'] == true ? ' · ${s(context, 'voided')}' : ''}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            nexModuleDateLabel(context, chequeDay(e['day'])!),
                          ),
                          if (e['kind'] == 'payment')
                            Text(
                              '${chequeMoney(context, chequeAmount(e['amountRial'])!, unit: c.unit)} ${s(context, c.unit)}',
                            ),
                          if (e['target'] is String &&
                              (e['target'] as String).isNotEmpty)
                            Text(e['target'] as String),
                          if ((e['note'] as String).isNotEmpty)
                            NexTextDirection(
                              text: e['note'] as String,
                              child: Text(e['note'] as String),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
