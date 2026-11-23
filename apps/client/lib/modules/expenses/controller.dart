import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nex_client/modules/module_api.dart';

import 'expenses_summary.dart';
import 'local_writes.dart';
import 'models.dart';
import 'money.dart';

/// Fresh reads, serial recoverable writes and exact guarded Undo.
class ExpensesController extends ChangeNotifier {
  ExpensesController(this.store) {
    _changes = store.changes.listen((_) {
      if (_mutating == 0) unawaited(load());
    });
  }
  final NexModuleStore store;
  late final StreamSubscription<void> _changes;
  Future<void> _tail = Future.value();
  int _loadToken = 0, _mutating = 0;
  bool _disposed = false;
  bool loading = true;
  String? lastWriteError;
  bool readFailed = false;
  List<ExpenseTx> txs = const [];
  List<ExpenseCategory> customCategories = const [];
  List<ExpenseBudget> budgets = const [];
  List<ExpenseTemplate> templates = const [];
  Map<String, Object?> settings = const {};
  final _undos = <String, Future<void> Function()>{};

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.cancel());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final token = ++_loadToken;
    try {
      await LocalWrites.recover(store);
      final results = await Future.wait<Object?>([
        store.list('tx'),
        store.list('cat'),
        store.list('budget'),
        store.list('tpl'),
        store.get('settings', 'main'),
      ]);
      if (_disposed || token != _loadToken) return;
      txs = [
        for (final row in results[0] as List<ModuleRecord>)
          ExpenseTx.fromBody(row.id, row.body),
      ];
      customCategories = [
        for (final row in results[1] as List<ModuleRecord>)
          ?ExpenseCategory.fromBody(row.id, row.body),
      ];
      budgets = [
        for (final row in results[2] as List<ModuleRecord>)
          ?ExpenseBudget.fromBody(row.id, row.body),
      ];
      templates = [
        for (final row in results[3] as List<ModuleRecord>)
          ?ExpenseTemplate.fromBody(row.id, row.body),
      ];
      settings = results[4] as Map<String, Object?>? ?? {};
      readFailed = false;
      loading = false;
      _notify();
    } catch (_) {
      if (_disposed || token != _loadToken) return;
      readFailed = true;
      loading = false;
      _notify();
    }
  }

  Future<T> _mutate<T>(Future<T> Function() write) {
    final done = _tail.then((_) async {
      _mutating++;
      try {
        final result = await write();
        lastWriteError = null;
        await load();
        return result;
      } catch (_) {
        lastWriteError = 'write';
        _notify();
        rethrow;
      } finally {
        _mutating--;
      }
    });
    _tail = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  Future<void> _put(
    String kind,
    String id,
    Map<String, Object?> body, {
    String? draftId,
  }) => _mutate(
    () => LocalWrites.serial(store, () async {
      final raw = await store.get(kind, id);
      await LocalWrites.apply(store, [
        (kind: kind, id: id, body: {...?raw, ...body}),
        if (draftId != null) (kind: 'draft', id: draftId, body: null),
      ]);
    }),
  );

  Future<void> _delete(String kind, String id) => _mutate(() async {
    final undo = await LocalWrites.delete(store, kind, id);
    _undos['$kind:$id'] = undo;
  });

  Future<void> restore(String kind, String id) => _mutate(() async {
    final undo = _undos['$kind:$id'];
    if (undo == null) throw StateError('Undo unavailable');
    await undo();
    _undos.remove('$kind:$id');
  });

  Future<Future<void> Function()> saveTx(
    ExpenseTx tx, {
    ExpenseTx? existing,
    String? draftId,
  }) => _mutate(
    () => LocalWrites.serial(store, () async {
      final proposed = tx.toBody();
      if (!ExpenseTx.fromBody(tx.id, proposed).valid ||
          !expenseAmountInRange(tx.amountRial)) {
        throw StateError('Invalid transaction');
      }
      final raw = await store.get('tx', tx.id);
      if (existing != null && raw == null) {
        throw StateError('Transaction no longer exists');
      }
      final body = {...?raw};
      final old = existing?.valid == true ? existing!.toBody() : null;
      for (final key in {
        ...proposed.keys,
        'category',
        'note',
        'merchant',
        'account',
      }) {
        // Only skip a field the stored body already holds: a 2.1.x
        // record has no `amountRial` yet, and the migration has to
        // write it even though the value is unchanged.
        if (old != null &&
            (raw?.containsKey(key) ?? false) &&
            LocalWrites.same(old[key], proposed[key])) {
          continue;
        }
        if (proposed.containsKey(key)) {
          body[key] = proposed[key];
        } else {
          body.remove(key);
        }
      }
      // A record written by 2.1.x kept a currency's minor units; the
      // amount now lives in `amountRial`, so the old keys go with it —
      // the value itself is kept, converted once, and never rescaled.
      for (final legacy in const [
        'amount',
        'currency',
        'currency_code',
        'currency_exponent',
        'exponent',
      ]) {
        body.remove(legacy);
      }
      body['schema'] = 3;
      if (!ExpenseTx.fromBody(tx.id, body).valid) {
        throw StateError('The current transaction needs repair');
      }
      final undo = await LocalWrites.apply(store, [
        (kind: 'tx', id: tx.id, body: body),
        if (draftId != null) (kind: 'draft', id: draftId, body: null),
      ]);
      return () => _mutate(undo);
    }),
  );

  Future<void> deleteTx(String id) => _delete('tx', id);
  Future<void> restoreTx(ExpenseTx tx) => restore('tx', tx.id);

  ExpenseTx? txById(String id) {
    for (final tx in txs) {
      if (tx.id == id) return tx;
    }
    return null;
  }

  Future<void> addCategory(String label, {String? id}) => label.trim().isEmpty
      ? Future.value()
      : _put('cat', id ?? 'cat-${store.newId()}', {
          'label': label.trim(),
          'schema': 1,
        });

  /// Renames one of the person's own categories, keeping its id — and every
  /// record written with it. The built-in ones are words from the module's
  /// strings and are not records to rename.
  Future<void> renameCategory(ExpenseCategory category, String label) =>
      label.trim().isEmpty
      ? Future.value()
      : _mutate(
          () => LocalWrites.patch(store, 'cat', category.id, {
            'label': label.trim(),
          }),
        );

  Future<void> deleteCategory(ExpenseCategory category) =>
      _delete('cat', category.id);
  Future<void> restoreCategory(ExpenseCategory category) =>
      restore('cat', category.id);

  Future<void> saveBudget(
    ExpenseBudget budget, {
    ExpenseBudget? existing,
    String? draftId,
  }) => _mutate(
    () => LocalWrites.serial(store, () async {
      final body = budget.toBody();
      if (ExpenseBudget.fromBody(budget.id, body) == null) {
        throw StateError('Invalid budget');
      }
      if (existing != null && await store.get('budget', existing.id) == null) {
        throw StateError('Budget no longer exists');
      }
      final raw = await store.get('budget', budget.id);
      if (existing != null && existing.id != budget.id && raw != null) {
        throw StateError('Budget destination already exists');
      }
      await LocalWrites.apply(store, [
        (kind: 'budget', id: budget.id, body: {...?raw, ...body}),
        if (existing != null && existing.id != budget.id)
          (kind: 'budget', id: existing.id, body: null),
        if (draftId != null) (kind: 'draft', id: draftId, body: null),
      ]);
    }),
  );

  Future<void> clearBudget(String start, String? categoryId) =>
      _delete('budget', budgetId(start, categoryId));

  ExpenseBudget? budgetFor(String start, String? categoryId) {
    for (final b in budgets) {
      if (b.start == start && b.categoryId == categoryId) return b;
    }
    return null;
  }

  /// The budgets set for a month's first civil day.
  List<ExpenseBudget> budgetsForStart(String start) => [
    for (final b in budgets)
      if (b.start == start) b,
  ];

  /// Copies the previous month's limits into missing categories. Undo
  /// refuses to overwrite any later edit to one of the copied budgets.
  Future<({int count, Future<void> Function() undo})?> copyBudgetsFrom({
    required String from,
    required String to,
  }) {
    if (from == to) return Future.value();
    return _mutate(
      () => LocalWrites.serial(store, () async {
        final rows = <LocalChange>[];
        for (final record in await store.list('budget')) {
          final budget = ExpenseBudget.fromBody(record.id, record.body);
          if (budget == null || budget.start != from) continue;
          final id = budgetId(to, budget.categoryId);
          if (await store.get('budget', id) != null) continue;
          final copy = ExpenseBudget(
            start: to,
            categoryId: budget.categoryId,
            amountRial: budget.amountRial,
          );
          rows.add((kind: 'budget', id: id, body: copy.toBody()));
        }
        if (rows.isEmpty) return null;
        final undo = await LocalWrites.apply(store, rows);
        return (count: rows.length, undo: () => _mutate(undo));
      }),
    );
  }

  Future<void> saveTemplate(ExpenseTemplate template, {String? draftId}) {
    if (ExpenseTemplate.fromBody(template.id, template.toBody()) == null) {
      return Future.error(StateError('Invalid template'));
    }
    return _put(
      'tpl',
      template.id.isEmpty ? 'tpl-${store.newId()}' : template.id,
      template.toBody(),
      draftId: draftId,
    );
  }

  Future<void> deleteTemplate(String id) => _delete('tpl', id);
  Future<void> restoreTemplate(String id) => restore('tpl', id);
  String newTxId() => 'tx-${store.newId()}';

  /// Writes [tx] again as a new payment, dated [at] (now by default) and
  /// with no `templateId`/`period`: it is a copy for today, not this month's
  /// occurrence of a recurring payment.
  Future<({String id, Future<void> Function() undo})> duplicateTx(
    ExpenseTx tx, {
    DateTime? at,
    String? draftId,
  }) async {
    final when = at ?? DateTime.now();
    final copy = ExpenseTx(
      id: newTxId(),
      type: tx.type,
      amountRial: tx.amountRial,
      date: DateTime(when.year, when.month, when.day, when.hour, when.minute),
      categoryId: tx.categoryId,
      note: tx.note,
      merchant: tx.merchant,
      account: tx.account,
    );
    // The editing sheet's own draft goes with the save (2.8.19): its edits
    // went into the copy, and left behind they came back on the original as
    // unfinished work.
    final undo = await saveTx(copy, draftId: draftId ?? 'tx:${copy.id}');
    return (id: copy.id, undo: undo);
  }

  /// Writes this month's occurrence of [template] down, once — the one-tap
  /// "log this month's" the brief asks for. It returns the new payment's id,
  /// or null when that month is already written down. Nothing is ever logged
  /// without this call.
  Future<String?> logTemplate(
    ExpenseTemplate template, {
    required DateTime dueDay,
  }) async {
    final month = NexModuleMonth.of(dueDay, solar: template.solar);
    final period = monthStartIso(month);
    final done = txs.any(
      (tx) => tx.templateId == template.id && tx.period == period,
    );
    if (done) return null;
    final tx = ExpenseTx(
      id: newTxId(),
      type: template.type,
      amountRial: template.amountRial,
      date: DateTime(dueDay.year, dueDay.month, dueDay.day, 12),
      categoryId: template.categoryId,
      note: template.note,
      merchant: template.merchant,
      templateId: template.id,
      period: period,
    );
    await saveTx(tx);
    return tx.id;
  }

  /// The settings a person chose: the unit amounts are said in, and whether
  /// the amounts are hidden on screen.
  ExpenseUnit get unit => ExpenseUnit.fromKey(settings['unit']);
  bool get hideAmounts => settings['hideAmounts'] == true;

  Future<void> rememberUnit(ExpenseUnit unit) =>
      _put('settings', 'main', {'unit': unit.key, 'schema': 1});

  Future<void> setHideAmounts(bool hidden) =>
      _put('settings', 'main', {'hideAmounts': hidden, 'schema': 1});

  /// Everything this module has falling due between [from] and [to] — the
  /// one function the shared calendar and the home offers both use.
  List<ModuleDue> duesBetween(DateTime from, DateTime to) =>
      ExpenseSchedule(templates: templates, txs: txs).duesBetween(from, to);
}
