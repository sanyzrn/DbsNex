import 'dart:convert';

import 'package:nex_client/modules/module_api.dart';

/// The conversions a person has already made, kept in the module's own store
/// so they are still there next time — and starred ones kept for good.
///
/// Two record kinds: `recent` (capped at twenty, newest first) and
/// `favorite`. Both hold the same body, so one can be promoted to the other
/// without being rebuilt. Every field is read defensively: a record written
/// by an older version, or one that lost a field, is skipped or read with
/// defaults, never thrown over.
enum ConverterTab { dates, units, sizes }

class ConverterEntry {
  const ConverterEntry({
    required this.id,
    required this.tab,
    required this.label,
    required this.payload,
    required this.at,
    this.starred = false,
  });

  final String id;
  final ConverterTab tab;

  /// One line a person can read and copy: «۷۰ کیلوگرم = ۱۵۴٫۳ پوند».
  final String label;

  /// What the screen needs to put the conversion back in its fields.
  final Map<String, Object?> payload;
  final DateTime at;
  final bool starred;

  /// Two records that would restore the same screen are the same conversion,
  /// even if their words were written in another language.
  String get signature => jsonEncode(payload);

  Map<String, Object?> toBody() => {
    'v': 1,
    'tab': tab.name,
    'label': label,
    'payload': payload,
    'at': at.toIso8601String(),
  };

  ConverterEntry copyWith({String? id, bool? starred}) => ConverterEntry(
    id: id ?? this.id,
    tab: tab,
    label: label,
    payload: payload,
    at: at,
    starred: starred ?? this.starred,
  );
}

/// Everything kept for this module, newest first in both lists.
({List<ConverterEntry> recents, List<ConverterEntry> favorites})
converterReadHistory(List<ModuleRecord> recents, List<ModuleRecord> favorites) {
  List<ConverterEntry> read(
    List<ModuleRecord> records, {
    required bool starred,
  }) {
    final entries = <ConverterEntry>[];
    for (final record in records) {
      final entry = _entryFrom(record, starred: starred);
      if (entry != null) entries.add(entry);
    }
    entries.sort((a, b) => b.at.compareTo(a.at));
    return entries;
  }

  return (
    recents: read(recents, starred: false),
    favorites: read(favorites, starred: true),
  );
}

ConverterEntry? _entryFrom(ModuleRecord record, {required bool starred}) {
  final body = record.body;
  final label = body['label'];
  if (label is! String || label.trim().isEmpty) return null;
  final tabName = body['tab'];
  final tab = ConverterTab.values.firstWhere(
    (value) => value.name == tabName,
    orElse: () => ConverterTab.units,
  );
  final payload = <String, Object?>{};
  final raw = body['payload'];
  if (raw is Map<Object?, Object?>) {
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is String) payload[key] = entry.value;
    }
  }
  final at = switch (body['at']) {
    final String text => DateTime.tryParse(text),
    _ => null,
  };
  return ConverterEntry(
    id: record.id,
    tab: tab,
    label: label,
    payload: payload,
    at: at ?? record.updatedAt,
    starred: starred,
  );
}

/// Whether [entry] is one of [favorites].
bool converterIsFavorite(ConverterEntry entry, List<ConverterEntry> favorites) {
  final signature = entry.signature;
  for (final favorite in favorites) {
    if (favorite.signature == signature) return true;
  }
  return false;
}

/// Keeps [entry] at the top of the recent list, removing an older copy of the
/// same conversion and anything past [cap].
Future<void> converterRemember(
  NexModuleStore store,
  ConverterEntry entry,
) async {
  final records = await store.list('recent');
  // Already the newest: nothing to move, and no new id to write.
  if (records.isNotEmpty) {
    final newest = _entryFrom(records.first, starred: false);
    if (newest != null && newest.signature == entry.signature) return;
  }
  for (final record in records) {
    final kept = _entryFrom(record, starred: false);
    if (kept != null && kept.signature == entry.signature) {
      await store.delete('recent', record.id);
    }
  }
  await store.put('recent', store.newId(), entry.toBody());
  final after = await store.list('recent');
  for (final stale in after.skip(_recentCap)) {
    await store.delete('recent', stale.id);
  }
}

/// Stars [entry], or takes the star off. Returns the favourite it wrote, so
/// the caller can undo it.
Future<ConverterEntry?> converterStar(
  NexModuleStore store,
  ConverterEntry entry, {
  required bool star,
}) async {
  final records = await store.list('favorite');
  for (final record in records) {
    final kept = _entryFrom(record, starred: true);
    if (kept != null && kept.signature == entry.signature) {
      if (!star) await store.delete('favorite', record.id);
      return null;
    }
  }
  if (!star) return null;
  final id = store.newId();
  await store.put('favorite', id, entry.toBody());
  return entry.copyWith(id: id, starred: true);
}

/// Puts [entry] back exactly where it was, for Undo.
Future<void> converterPutBack(NexModuleStore store, ConverterEntry entry) =>
    store.put(
      entry.starred ? 'favorite' : 'recent',
      store.newId(),
      entry.toBody(),
    );

/// [entry] out of the list it is in.
Future<void> converterForget(NexModuleStore store, ConverterEntry entry) =>
    store.delete(entry.starred ? 'favorite' : 'recent', entry.id);

const _recentCap = 20;
