import 'dart:convert';

import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'values.dart';
import 'money_format.dart' show maxMoney;

class ChequeFailure implements Exception {
  const ChequeFailure(this.code);
  final String code;
}

class ChequeRepository {
  ChequeRepository(this.store, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final NexModuleStore store;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Map<String, Object?>?> _fresh(
    String id,
    Map<String, Object?>? expected,
  ) async {
    final raw = await store.get('cheque', id);
    if (jsonEncode(raw) != jsonEncode(expected)) {
      throw const ChequeFailure('conflict');
    }
    return raw;
  }

  Future<Cheque> save(
    String id,
    Map<String, Object?>? expected,
    Map<String, Object?> fields,
  ) => _serial(() async {
    final raw = await _fresh(id, expected);
    final prior = raw == null ? null : Cheque(id, raw);
    final amount = chequeAmount(fields['amountRial'] ?? raw?['amountRial']);
    final days = fields['reminderDays'];
    if (amount != null &&
            amount > BigInt.from(maxMoney) &&
            amount != prior?.face ||
        days is List &&
            days.any((d) => !{0, 1, 3, 7, 14, 30}.contains(d)) &&
            jsonEncode(days) != jsonEncode(raw?['reminderDays'])) {
      throw const ChequeFailure('validation');
    }
    if (prior != null && !prior.valid) throw const ChequeFailure('invalid');
    if (prior?.locked == true &&
        ['direction', 'purpose', 'amountRial'].any(
          (k) => k == 'amountRial'
              ? chequeAmount(fields[k]) != chequeAmount(raw![k])
              : fields[k] != raw![k],
        )) {
      throw const ChequeFailure('locked');
    }
    final body = <String, Object?>{
      ...?raw,
      ...fields,
      'v': 1,
      'status': raw?['status'] ?? 'active',
      'archived': chequeClosed.contains(raw?['status']),
      'events': raw?['events'] ?? <Object?>[],
    };
    body['amountRial'] = storedRials(body['amountRial']);
    final oldPerson = raw?['person'];
    final suppliedPerson = fields['person'];
    body['person'] = {
      if (oldPerson is Map) ...Map<String, Object?>.from(oldPerson),
      if (suppliedPerson is Map) ...Map<String, Object?>.from(suppliedPerson),
      'name':
          fields['party'] ??
          (suppliedPerson is Map ? suppliedPerson['name'] : null) ??
          prior?.party ??
          '',
    };
    final c = Cheque(id, body);
    if (!c.valid) throw const ChequeFailure('validation');
    if (c.sayad.isNotEmpty) {
      final all = await store.list('cheque');
      if (all.any((r) => r.id != id && r.body['sayad'] == c.sayad)) {
        throw const ChequeFailure('duplicate');
      }
    }
    await store.put('cheque', id, body);
    return c;
  });
  Future<Cheque> addEvent(
    Cheque old, {
    required String id,
    required String kind,
    required DateTime day,
    String amount = '',
    String next = '',
    String note = '',
    String target = '',
  }) => _serial(() async {
    final raw = await _fresh(old.id, old.raw);
    if (!old.valid ||
        old.events.length >= 500 ||
        chequeDay(chequeDayKey(day)) == null ||
        chequeDaysBetween(day, clock()) < 0 ||
        note.length > 500 ||
        target.length > 100) {
      throw const ChequeFailure('validation');
    }
    if (old.events.any((e) => e['id'] == id)) {
      throw const ChequeFailure('conflict');
    }
    var status = next;
    if (kind == 'payment') {
      final n = chequeAmount(amount);
      if (old.closed ||
          old.purpose != 'payment' ||
          n == null ||
          n > old.remaining) {
        throw const ChequeFailure('paymentError');
      }
      status = n == old.remaining ? 'settled' : old.status;
    } else if (kind == 'status') {
      if (next == old.status ||
          !chequeStatuses.contains(next) ||
          next == 'settled' ||
          (next == 'transferred' && target.trim().isEmpty) ||
          (next == 'deposited' && target.trim().isEmpty)) {
        throw const ChequeFailure('validation');
      }
    } else {
      throw const ChequeFailure('validation');
    }
    final event = <String, Object?>{
      'id': id,
      'kind': kind,
      'day': chequeDayKey(day),
      'amountRial': storedRials(amount),
      'previous': old.status,
      'next': status,
      'note': note.trim(),
      'target': target.trim(),
      'voided': false,
    };
    final body = <String, Object?>{
      ...raw!,
      'status': status,
      'archived': chequeClosed.contains(status),
      'events': [...old.events, event],
    };
    final updated = Cheque(old.id, body);
    if (!updated.valid) throw const ChequeFailure('validation');
    await store.put('cheque', old.id, body);
    return updated;
  });
  Future<Cheque> reverseLast(Cheque old) => _serial(() async {
    final raw = await _fresh(old.id, old.raw);
    if (!old.valid) throw const ChequeFailure('invalid');
    final events = old.events;
    final index = events.lastIndexWhere((e) => e['voided'] != true);
    if (index < 0) throw const ChequeFailure('validation');
    final status = events[index]['previous'];
    events[index] = {...events[index], 'voided': true};
    final body = <String, Object?>{
      ...raw!,
      'events': events,
      'status': status,
      'archived': chequeClosed.contains(status),
    };
    final c = Cheque(old.id, body);
    if (!c.valid) throw const ChequeFailure('validation');
    await store.put('cheque', old.id, body);
    return c;
  });
  Future<Map<String, Object?>> delete(Cheque old) => _serial(() async {
    final raw = await _fresh(old.id, old.raw);
    if (raw == null) throw const ChequeFailure('conflict');
    final draft = await store.get('draft', 'cheque:${old.id}');
    final action = await store.get('draft', 'action:${old.id}');
    await store.deleteRecords([
      (kind: 'cheque', id: old.id),
      if (draft != null) (kind: 'draft', id: 'cheque:${old.id}'),
      if (action != null) (kind: 'draft', id: 'action:${old.id}'),
    ]);
    return raw;
  });
  Future<void> restore(String id, Map<String, Object?> raw) =>
      _serial(() async {
        if (await store.get('cheque', id) != null) {
          throw const ChequeFailure('conflict');
        }
        final sayad = raw['sayad'];
        if (sayad is String &&
            sayad.isNotEmpty &&
            (await store.list('cheque')).any((r) => r.body['sayad'] == sayad)) {
          throw const ChequeFailure('duplicate');
        }
        await store.put('cheque', id, raw);
      });
}
