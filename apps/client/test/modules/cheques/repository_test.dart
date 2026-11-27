import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/cheques/repository.dart';
import 'package:nex_client/modules/cheques/model.dart';

import '../../support/nex_harness.dart';
import 'fixtures.dart';

class ChequeFaultStore extends NexModuleStore {
  ChequeFaultStore(NexTestHarness h) : super(h.services, 'cheques');
  bool failWrite = false,
      failDelete = false,
      failDraftRead = false,
      failCleanup = false;
  @override
  Future<Map<String, Object?>?> get(String kind, String id) {
    if (kind == 'draft' && failDraftRead) throw StateError('unavailable');
    return super.get(kind, id);
  }

  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) {
    if (kind == 'cheque' && failWrite ||
        kind == 'draft' && failCleanup && body['discarded'] == true) {
      throw StateError('unavailable');
    }
    return super.put(kind, id, body);
  }

  @override
  Future<void> delete(String kind, String id) {
    if (kind == 'draft' && failCleanup) throw StateError('unavailable');
    return super.delete(kind, id);
  }

  @override
  Future<void> deleteRecords(List<({String kind, String id})> records) {
    if (failDelete) throw StateError('unavailable');
    return super.deleteRecords(records);
  }
}

void main() {
  late NexTestHarness h;
  late ChequeFaultStore store;
  late ChequeRepository repo;
  setUp(() async {
    h = await NexTestHarness.create(name: 'cheque_repo_');
    store = ChequeFaultStore(h);
    repo = ChequeRepository(store, clock: () => DateTime(2026, 11, 17));
  });
  tearDown(() => h.dispose());
  test(
    'fresh saves preserve unknown fields and duplicate identifiers are refused',
    () async {
      final old = chequeRaw(sayad: '0012345678901234')
        ..['future'] = {'keep': true};
      await store.put('cheque', 'a', old);
      final c = await repo.save('a', old, {...old, 'party': 'New'});
      expect(c.raw['future'], {'keep': true});
      await expectLater(
        repo.save('b', null, chequeRaw(sayad: '0012345678901234')),
        throwsA(isA<ChequeFailure>()),
      );
      expect(await store.get('cheque', 'b'), isNull);
    },
  );
  test('partial and full settlements are one atomic financial write, then safely reversible', () async {
    var c = await repo.save('a', null, chequeRaw());
    c = await repo.addEvent(
      c,
      id: 'one',
      kind: 'payment',
      day: DateTime(2026, 11, 17),
      amount: '300',
    );
    expect(c.remaining, BigInt.from(700));
    expect(c.status, 'active');
    c = await repo.addEvent(
      c,
      id: 'two',
      kind: 'payment',
      day: DateTime(2026, 11, 17),
      amount: '700',
    );
    expect(c.status, 'settled');
    expect(c.remaining, BigInt.zero);
    await expectLater(
      repo.addEvent(
        c,
        id: 'invalid-return',
        kind: 'status',
        day: DateTime(2026, 11, 17),
        next: 'returned',
      ),
      throwsA(isA<ChequeFailure>()),
    );
    c = await repo.reverseLast(c);
    expect(c.status, 'active');
    expect(c.remaining, BigInt.from(700));
    expect(c.events.last['voided'], isTrue);
    expect(Cheque('a', (await store.get('cheque', 'a'))!).valid, isTrue);
  });
  test(
    'failed event writes cannot reduce a saved balance; queue recovers',
    () async {
      final c = await repo.save('a', null, chequeRaw());
      store.failWrite = true;
      await expectLater(
        repo.addEvent(
          c,
          id: 'one',
          kind: 'payment',
          day: DateTime(2026, 11, 17),
          amount: '300',
        ),
        throwsStateError,
      );
      expect((await store.get('cheque', 'a'))!['events'], isEmpty);
      store.failWrite = false;
      final next = await repo.addEvent(
        c,
        id: 'one',
        kind: 'payment',
        day: DateTime(2026, 11, 17),
        amount: '300',
      );
      expect(next.remaining, BigInt.from(700));
    },
  );
  test('stale concurrent actions, overpayment and future-dated events cannot mutate money', () async {
    final c = await repo.save('a', null, chequeRaw());
    final next = await repo.addEvent(
      c,
      id: 'one',
      kind: 'payment',
      day: DateTime(2026, 11, 17),
      amount: '600',
    );
    await expectLater(
      repo.addEvent(
        c,
        id: 'two',
        kind: 'payment',
        day: DateTime(2026, 11, 17),
        amount: '600',
      ),
      throwsA(isA<ChequeFailure>()),
    );
    await expectLater(
      repo.addEvent(
        next,
        id: 'two',
        kind: 'payment',
        day: DateTime(2026, 11, 17),
        amount: '401',
      ),
      throwsA(isA<ChequeFailure>()),
    );
    await expectLater(
      repo.addEvent(
        next,
        id: 'two',
        kind: 'payment',
        day: DateTime(2026, 11, 18),
        amount: '1',
      ),
      throwsA(isA<ChequeFailure>()),
    );
    expect(
      Cheque('a', (await store.get('cheque', 'a'))!).remaining,
      BigInt.from(400),
    );
  });
  test('history locks identity/amount and transfer is not a receipt', () async {
    var c = await repo.save('a', null, chequeRaw(direction: 'incoming'));
    c = await repo.addEvent(
      c,
      id: 'transfer',
      kind: 'status',
      day: DateTime(2026, 11, 17),
      next: 'transferred',
      target: 'Supplier',
    );
    expect(c.paid, BigInt.zero);
    expect(c.remaining, BigInt.from(1000));
    expect(c.closed, isTrue);
    await expectLater(
      repo.save('a', c.raw, {...c.raw, 'amountRial': '2000'}),
      throwsA(isA<ChequeFailure>()),
    );
    c = await repo.reverseLast(c);
    c = await repo.save('a', c.raw, {...c.raw, 'amountRial': '2000'});
    expect(c.face, BigInt.from(2000));
  });
  test('delete is atomic with drafts; Undo restores raw saved data and refuses collision', () async {
    final c = await repo.save('a', null, chequeRaw()..['future'] = 'retained');
    await store.put('draft', 'cheque:a', {'private': 'draft'});
    await store.put('draft', 'action:a', {'private': 'draft'});
    store.failDelete = true;
    await expectLater(repo.delete(c), throwsStateError);
    expect(await store.get('draft', 'cheque:a'), isNotNull);
    store.failDelete = false;
    final raw = await repo.delete(c);
    expect(await store.get('cheque', 'a'), isNull);
    expect(await store.list('draft'), isEmpty);
    await repo.restore('a', raw);
    expect(await store.get('cheque', 'a'), c.raw);
    await expectLater(repo.restore('a', raw), throwsA(isA<ChequeFailure>()));
  });
  test('unknown schema is never edited or projected as finance; explicit delete still works', () async {
    final raw = chequeRaw()..['v'] = 99;
    await store.put('cheque', 'a', raw);
    await expectLater(
      repo.save('a', raw, chequeRaw()),
      throwsA(isA<ChequeFailure>()),
    );
    expect(await store.get('cheque', 'a'), raw);
    await repo.delete(Cheque('a', raw));
    expect(await store.get('cheque', 'a'), isNull);
  });
}
