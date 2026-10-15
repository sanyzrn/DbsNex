import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nex_client/modules/module_api.dart';
import 'models.dart';
import 'money.dart';
import 'local_writes.dart';

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
          if (ExpenseCategory.fromBody(row.id, row.body) case final item?) item,
      ];
      budgets = [
        for (final row in results[2] as List<ModuleRecord>)
          if (ExpenseBudget.fromBody(row.id, row.body) case final item?) item,
      ];
      templates = [
        for (final row in results[3] as List<ModuleRecord>)
          if (ExpenseTemplate.fromBody(row.id, row.body) case final item?) item,
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

  Future<void> _mutate(Future<void> Function() write) {
    final done = _tail.then((_) async {
      _mutating++;
      try {
        await write();
        lastWriteError = null;
        await load();
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

  Future<void> saveTx(ExpenseTx tx, {ExpenseTx? existing, String? draftId}) =>
      _mutate(
        () => LocalWrites.serial(store, () async {
          final proposed = tx.toBody();
          if (!ExpenseTx.fromBody(tx.id, proposed).valid ||
              !expenseAmountInRange(tx.amount)) {
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
            if (old != null && LocalWrites.same(old[key], proposed[key])) {
              continue;
            }
            if (proposed.containsKey(key)) {
              body[key] = proposed[key];
            } else {
              body.remove(key);
            }
          }
          body.addAll(expenseCurrencyMetadata(body['currency'] as String));
          body['schema'] = 2;
          if (!ExpenseTx.fromBody(tx.id, body).valid) {
            throw StateError('The current transaction needs repair');
          }
          await LocalWrites.apply(store, [
            (kind: 'tx', id: tx.id, body: body),
            if (draftId != null) (kind: 'draft', id: draftId, body: null),
          ]);
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
  Future<void> clearBudget(String month, String? categoryId, String currency) =>
      _delete('budget', budgetId(month, categoryId, currency));
  ExpenseBudget? budgetFor(String month, String? categoryId, String currency) {
    for (final b in budgets) {
      if (b.month == month &&
          b.categoryId == categoryId &&
          b.currency == currency) {
        return b;
      }
    }
    return null;
  }

  Future<void> saveTemplate(
    ExpenseTemplate template, {
    String? id,
    String? draftId,
  }) {
    if (ExpenseTemplate.fromBody(id ?? template.id, template.toBody()) ==
        null) {
      return Future.error(StateError('Invalid template'));
    }
    return _put(
      'tpl',
      id ?? (template.id.isNotEmpty ? template.id : 'tpl-${store.newId()}'),
      template.toBody(),
      draftId: draftId,
    );
  }

  Future<void> deleteTemplate(String id) => _delete('tpl', id);
  Future<void> restoreTemplate(String id) => restore('tpl', id);
  String newTxId() => 'tx-${store.newId()}';
  String get preferredCurrencyCode =>
      expenseCurrencyOf(
        settings['currency'] is String ? settings['currency'] as String : null,
      )?.code ??
      'IRR';
  String get preferredIrrUnit =>
      settings['irrUnit'] == 'toman' ? 'toman' : 'rial';
  Future<void> rememberEditorDefaults({
    required String currencyCode,
    required String irrUnit,
  }) => _put('settings', 'main', {
    'currency': currencyCode,
    'irrUnit': irrUnit,
    'schema': 1,
  });
}
