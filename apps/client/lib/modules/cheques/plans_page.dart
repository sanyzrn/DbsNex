import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'plan_model.dart';
import 'plan_editor.dart';
import 'plan_repository.dart';
import 'reminders.dart';
import 'privacy.dart';
import 'repository.dart';
import 'strings.dart';
import 'widgets.dart';

class PlansPage extends StatefulWidget {
  const PlansPage({super.key, required this.store});
  final NexModuleStore store;
  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  late final repo = PlanRepository(widget.store);
  List<InstalmentPlan> rows = [];
  bool loading = true, failed = false, busy = false;
  int generation = 0;
  StreamSubscription<void>? changes;
  @override
  void initState() {
    super.initState();
    changes = widget.store.changes.listen((_) => unawaited(load()));
    unawaited(load());
  }

  @override
  void dispose() {
    unawaited(changes?.cancel());
    super.dispose();
  }

  Future<void> load() async {
    final g = ++generation;
    try {
      final data = await widget.store.list('plan');
      if (mounted && g == generation) {
        setState(() {
          rows = data.map((r) => InstalmentPlan(r.id, r.body)).toList();
          loading = false;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && g == generation) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  Future<void> edit([InstalmentPlan? p]) => Navigator.of(context).push<void>(
    NexPageRoute(
      builder: (_) =>
          chequePrivateRoute(context, PlanEditor(repo: repo, plan: p)),
    ),
  );
  Future<void> write(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) {
        var ok = false;
        try {
          ok = await renewPlans(widget.store, AppLocalizations.of(context));
        } catch (_) {
          ok = false;
        }
        if (!ok && mounted) {
          nexShowBanner(
            context,
            message: chequeStrings(context, 'remindError'),
            kind: NexBannerKind.failed,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        nexShowBanner(
          context,
          message: chequeStrings(
            context,
            e is ChequeFailure ? e.code : 'saveError',
          ),
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(InstalmentPlan p) async {
    final s = chequeStrings,
        host = NexBannerHost.of(context),
        l10n = AppLocalizations.of(context);
    final yes = await nexShowDialog<bool>(
      context: context,
      builder: (x) => NexAlertDialog(
        title: Text(s(x, 'deletePlan')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x),
            child: Text(AppLocalizations.of(x).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(x, true),
            child: Text(s(x, 'delete')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await write(() async {
      final raw = await repo.delete(p);
      host?.show(
        message: s.text(l10n, 'deleted'),
        actionLabel: s.text(l10n, 'undo'),
        onAction: () async {
          try {
            await repo.restore(p.id, raw);
            await renewPlans(repo.store, l10n);
          } catch (_) {
            host.show(
              message: s.text(l10n, 'saveError'),
              kind: NexBannerKind.failed,
            );
          }
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = chequeStrings;
    return Scaffold(
      appBar: NexAppBar(
        title: Text(s(context, 'plans')),
        actions: const [ChequePrivacyButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => edit(),
        icon: const Icon(Icons.add),
        label: Text(s(context, 'addPlan')),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : failed
          ? NexEmptyState(
              icon: Icons.refresh,
              message: s(context, 'readError'),
              action: TextButton(
                onPressed: load,
                child: Text(s(context, 'retry')),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.xl + kMinInteractiveDimension * 2,
              ),
              children: [
                if (rows.isEmpty) Text(s(context, 'noPlans')),
                for (final p in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NexSpacing.md),
                    child: NexPanel(
                      title: p.title,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!p.valid)
                            Text(s(context, 'invalid'))
                          else ...[
                            Text(
                              '${s(context, 'plan_total')}: ${chequeMoney(context, p.total!, unit: 'rial')} ${s(context, 'rial')}',
                            ),
                            TextButton(
                              onPressed: () => edit(p),
                              child: Text(s(context, 'editPlan')),
                            ),
                            for (var i = 0; i < p.count; i++)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: p.paid(i),
                                onChanged: busy
                                    ? null
                                    : (_) => write(() async {
                                        await repo.toggle(p, i);
                                      }),
                                title: Text(
                                  '${s(context, 'instalment')} ${nexDigits('${i + 1}', persian: NexModuleStrings.persian(context))} · ${chequeMoney(context, p.amount(i))} ${s(context, 'toman')}',
                                ),
                                subtitle: Text(
                                  nexModuleDateLabel(context, p.date(i)),
                                ),
                              ),
                          ],
                          TextButton(
                            onPressed: busy ? null : () => remove(p),
                            child: Text(s(context, 'deletePlanAction')),
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
