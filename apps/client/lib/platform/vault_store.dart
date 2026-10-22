import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

enum VaultKind { password, card, message }

/// This data never enters the note database, FTS, widgets or AI context.
class VaultEntry {
  VaultEntry({
    required this.id,
    required this.kind,
    required this.fields,
    required this.updatedAt,
    this.favorite = false,
  });
  final String id;
  final VaultKind kind;
  final Map<String, String> fields;
  final DateTime updatedAt;
  final bool favorite;
  String get title => fields['title'] ?? '';
  String value(String key) => fields[key] ?? '';
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'fields': fields,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'favorite': favorite,
  };
  factory VaultEntry.fromJson(Map<String, dynamic> data) {
    final fields = Map<String, String>.from(data['fields'] as Map);
    // Sixteen leaves room for the card's own fields (CVV2 came in 1.93.4)
    // plus its colour, with a margin for the next one.
    if (fields.length > 16 || fields.values.any((v) => v.length > 10000)) {
      throw const FormatException('Invalid vault fields');
    }
    return VaultEntry(
      id: data['id'] as String,
      kind: VaultKind.values.byName(data['kind'] as String),
      fields: fields,
      updatedAt: DateTime.parse(data['updatedAt'] as String),
      favorite: data['favorite'] as bool,
    );
  }
}

class VaultSnapshot {
  const VaultSnapshot(this.entries, this.draft);

  /// The most items the vault holds. Raised from 2,000 in 1.93.4: a single
  /// browser export is often that size on its own, and an import that could
  /// not fit was refused whole.
  static const maxEntries = 10000;
  final List<VaultEntry> entries;
  final VaultEntry? draft;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'entries': entries.map((e) => e.toJson()).toList(),
    'draft': draft?.toJson(),
  };
  factory VaultSnapshot.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 1 ||
        value['entries'] is! List ||
        (value['entries'] as List).length > maxEntries) {
      throw const FormatException('Invalid vault');
    }
    final entries = (value['entries'] as List)
        .map((e) => VaultEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (entries.map((e) => e.id).toSet().length != entries.length) {
      throw const FormatException('Duplicate vault identifiers');
    }
    final draft = value['draft'];
    return VaultSnapshot(
      entries,
      draft == null
          ? null
          : VaultEntry.fromJson(Map<String, dynamic>.from(draft as Map)),
    );
  }
}

/// What an import did with each password it was given.
class VaultImportOutcome {
  const VaultImportOutcome({
    required this.added,
    required this.duplicates,
    required this.overCapacity,
  });
  final int added;

  /// Already in the vault with the same website, login and password.
  final int duplicates;

  /// Left out because the vault was full.
  final int overCapacity;
}

/// Platform-encrypted storage only. A corrupt/unavailable store fails closed;
/// it must never be replaced with an empty vault following a read failure.
class VaultStore {
  VaultStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'nex_private_vault',
              resetOnError: false,
              migrateWithBackup: true,
            ),
          );
  static const storageKey = 'nex.private_vault.v1';
  final FlutterSecureStorage _storage;
  static Future<void>? _writes;

  Future<VaultSnapshot> read() async {
    final pending = _writes;
    if (pending != null) await pending;
    return _read();
  }

  Future<VaultSnapshot> _read() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return const VaultSnapshot([], null);
    if (raw.length > 8 * 1024 * 1024) {
      throw const FormatException('Vault too large');
    }
    return VaultSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _change(VaultSnapshot Function(VaultSnapshot) apply) {
    final result = (_writes ?? Future<void>.value()).then((_) async {
      final next = apply(await _read());
      final encoded = jsonEncode(next.toJson());
      if (encoded.length > 8 * 1024 * 1024) {
        throw const FormatException('Vault too large');
      }
      // Validate before writing, including the entry-count bound.
      VaultSnapshot.fromJson(next.toJson());
      await _storage.write(key: storageKey, value: encoded);
      if (await _storage.read(key: storageKey) != encoded) {
        throw StateError('Vault write could not be verified');
      }
    });
    final tail = result.catchError((Object _) {});
    _writes = tail;
    unawaited(
      tail.then((_) {
        if (identical(_writes, tail)) _writes = null;
      }),
    );
    return result;
  }

  Future<void> save(VaultEntry entry) => _change(
    (old) => VaultSnapshot([
      for (final existing in old.entries)
        if (existing.id != entry.id) existing,
      entry,
    ], old.draft?.id == entry.id ? null : old.draft),
  );

  /// Adds [imported] passwords that are not already in the vault, as many as
  /// fit under [VaultSnapshot.maxEntries], and says what happened to each.
  Future<VaultImportOutcome> importPasswords(List<VaultEntry> imported) async {
    var added = 0, duplicates = 0, overCapacity = 0;
    await _change((old) {
      added = duplicates = overCapacity = 0;
      String identity(VaultEntry e) => jsonEncode([
        e.value('website'),
        e.value('login'),
        e.value('password'),
      ]);
      final seen = old.entries
          .where((e) => e.kind == VaultKind.password)
          .map(identity)
          .toSet();
      final room = VaultSnapshot.maxEntries - old.entries.length;
      final next = [...old.entries];
      for (final e in imported) {
        if (e.kind != VaultKind.password) continue;
        if (!seen.add(identity(e))) {
          duplicates++;
        } else if (added >= room) {
          overCapacity++;
        } else {
          next.add(e);
          added++;
        }
      }
      return VaultSnapshot(next, old.draft);
    });
    return VaultImportOutcome(
      added: added,
      duplicates: duplicates,
      overCapacity: overCapacity,
    );
  }

  /// Deletes every item of [kind], leaving the other kinds as they are. A
  /// draft of that kind goes with them.
  Future<void> deleteAll(VaultKind kind) => _change(
    (old) => VaultSnapshot(
      old.entries.where((e) => e.kind != kind).toList(),
      old.draft?.kind == kind ? null : old.draft,
    ),
  );
  Future<void> delete(String id) => _change(
    (old) => VaultSnapshot(
      old.entries.where((e) => e.id != id).toList(),
      old.draft?.id == id ? null : old.draft,
    ),
  );
  Future<void> saveDraft(VaultEntry? draft) =>
      _change((old) => VaultSnapshot(old.entries, draft));
  Future<Map<String, dynamic>> backup() async => (await read()).toJson();
  Future<void> restore(Map<String, dynamic> value) {
    final next = VaultSnapshot.fromJson(value);
    return _change((_) => next);
  }

  static VaultEntry empty(VaultKind kind) => VaultEntry(
    id: const Uuid().v4(),
    kind: kind,
    fields: {},
    updatedAt: DateTime.now(),
  );
}

String generateVaultPassword({int length = 20, bool symbols = true}) {
  if (length < 12 || length > 64) throw RangeError.range(length, 12, 64);
  final random = Random.secure();
  final groups = [
    'abcdefghijkmnopqrstuvwxyz',
    'ABCDEFGHJKLMNPQRSTUVWXYZ',
    '23456789',
    if (symbols) '!@#%+-_=?',
  ];
  final alphabet = groups.join();
  final characters = [
    for (final group in groups) group[random.nextInt(group.length)],
  ];
  while (characters.length < length) {
    characters.add(alphabet[random.nextInt(alphabet.length)]);
  }
  for (var i = characters.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final v = characters[i];
    characters[i] = characters[j];
    characters[j] = v;
  }
  return characters.join();
}

String vaultLatinDigits(String text) =>
    text.replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) {
      final code = m[0]!.codeUnitAt(0);
      return '${code >= 0x6f0 ? code - 0x6f0 : code - 0x660}';
    });
String vaultCardDigits(String text) =>
    vaultLatinDigits(text).replaceAll(RegExp(r'[\s-]'), '');

/// Whether [raw] has the shape of a card number: twelve to nineteen digits (some
/// Maestro cards have twelve),
/// not all the same one. This is what stops a save.
bool validVaultCardShape(String raw) {
  final value = vaultCardDigits(raw);
  return RegExp(r'^\d{12,19}$').hasMatch(value) &&
      !RegExp(r'^(\d)\1+$').hasMatch(value);
}

/// Whether [raw] also passes the Luhn check digit.
///
/// Only ever a warning. Most cards pass it, but a number copied from a card
/// that is perfectly good can still fail it — a bank's own range, a typo in
/// the one place the person cannot see — and refusing to keep a number the
/// owner is looking at on the card in their hand is worse than saying the
/// check digit looks off.
bool validVaultCard(String raw) {
  final value = vaultCardDigits(raw);
  if (!validVaultCardShape(value)) return false;
  var sum = 0;
  for (var i = value.length - 1; i >= 0; i--) {
    var n = int.parse(value[i]);
    if ((value.length - 1 - i).isOdd) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
  }
  return sum % 10 == 0;
}

/// Whether [raw] reads as an expiry date: a month and a year, in either order,
/// the year of two or four digits. Persian cards print the Solar Hijri year and
/// month — «۱۴۰۵/۰۸», «۰۸/۰۵» — and a field that only accepted month-first
/// refused what the person was reading off their own card. Blank is fine; it is
/// optional.
bool validVaultExpiry(String raw) {
  final value = vaultLatinDigits(raw).trim();
  if (value.isEmpty) return true;
  bool month(String text) {
    final n = int.tryParse(text);
    return n != null && n >= 1 && n <= 12;
  }

  final monthFirst = RegExp(
    r'^(\d{1,2})\s*/\s*(\d{2}|\d{4})$',
  ).firstMatch(value);
  if (monthFirst != null && month(monthFirst[1]!)) return true;
  final yearFirst = RegExp(r'^(\d{2}|\d{4})\s*/\s*(\d{2})$').firstMatch(value);
  return yearFirst != null && month(yearFirst[2]!);
}

/// The part of [entry] that means something, spelled the way it is saved:
/// empty fields dropped, a card's digits in Latin form and its number and IBAN
/// without spaces. Two entries with the same meaning compare equal.
Map<String, String> vaultMeaning(VaultEntry entry) {
  final meaning = <String, String>{};
  for (final field in entry.fields.entries) {
    var value = field.key == 'password' ? field.value : field.value.trim();
    if (entry.kind == VaultKind.card) {
      value = switch (field.key) {
        'number' => vaultCardDigits(value),
        'iban' => vaultLatinDigits(
          value,
        ).replaceAll(RegExp(r'\s'), '').toUpperCase(),
        'account' || 'expiry' || 'cvv2' => vaultLatinDigits(value),
        _ => value,
      };
    }
    if (value.isNotEmpty) meaning[field.key] = value;
  }
  return meaning;
}

/// Whether [entry] holds anything beyond [original] — the entry as saved, or
/// null for one that was never saved, in which case anything at all counts.
///
/// What decides whether an edit is worth keeping as an unfinished draft: opening
/// a card and leaving it, or opening "new" and typing nothing, changes nothing
/// and must leave nothing behind to resume.
bool vaultEntryDiffers(VaultEntry entry, VaultEntry? original) {
  final now = vaultMeaning(entry);
  if (original == null) return now.isNotEmpty || entry.favorite;
  final before = vaultMeaning(original);
  if (entry.favorite != original.favorite || now.length != before.length) {
    return true;
  }
  return now.entries.any((e) => before[e.key] != e.value);
}

bool validVaultIban(String raw) {
  final value = vaultLatinDigits(
    raw,
  ).replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(value)) return false;
  if (value.startsWith('IR') && value.length != 26) return false;
  final rearranged = value.substring(4) + value.substring(0, 4);
  var remainder = 0;
  for (final char in rearranged.codeUnits) {
    final digits = char >= 65 ? '${char - 55}' : String.fromCharCode(char);
    for (final digit in digits.codeUnits) {
      remainder = (remainder * 10 + digit - 48) % 97;
    }
  }
  return remainder == 1;
}
