/// A portrait of somebody drawn from their own notes (2.1.7).
///
/// Two halves, on purpose. [nexWritingStats] is arithmetic over the library —
/// when somebody writes, what kind of notes they keep, how often, about what
/// — and needs nothing but the phone. [NexPortrait] is the written half, a
/// few sentences and five traits a model reads out of a sample of the notes,
/// and is only ever asked for by the person, from their profile.
///
/// Pure and in core: no wording and no locale. What each of these reads as
/// is the client's.
library;

import 'dart:convert';

import '../models/note.dart';

/// The four parts of a day a note can be written in, by local hour.
enum NexDayPart {
  /// 05:00–11:59.
  morning,

  /// 12:00–16:59.
  afternoon,

  /// 17:00–21:59.
  evening,

  /// 22:00–04:59.
  night;

  static NexDayPart of(DateTime local) => switch (local.hour) {
    >= 5 && < 12 => morning,
    >= 12 && < 17 => afternoon,
    >= 17 && < 22 => evening,
    _ => night,
  };
}

/// What can be counted about somebody's writing without asking anyone.
class NexWritingStats {
  const NexWritingStats({
    required this.notes,
    required this.days,
    required this.activeLast30,
    required this.dayParts,
    required this.types,
    required this.tags,
    required this.checklistItems,
    required this.checklistDone,
  });

  /// Below either of these there is not enough to read a person from: a
  /// handful of notes is a handful of errands, and a library written in one
  /// afternoon says what that afternoon was about.
  static const minNotes = 30;
  static const minDays = 7;

  /// Live notes counted.
  final int notes;

  /// Distinct days, in local time, that have a note written on them.
  final int days;

  /// Of the last 30 days, how many have a note.
  final int activeLast30;

  /// Notes per [NexDayPart], indexed by the enum's order.
  final List<int> dayParts;

  /// Notes per kind, largest first.
  final List<(NoteType, int)> types;

  /// The five tags used most, with how many notes carry each.
  final List<(String, int)> tags;

  final int checklistItems;
  final int checklistDone;

  bool get unlocked => notes >= minNotes && days >= minDays;

  /// How many more notes before [unlocked] — zero once there are enough.
  int get notesToGo => (minNotes - notes).clamp(0, minNotes);

  /// How many more days with a note before [unlocked].
  int get daysToGo => (minDays - days).clamp(0, minDays);

  /// The part of the day most notes are written in, or null with no notes.
  NexDayPart? get peak {
    if (notes == 0) return null;
    var best = 0;
    for (var i = 1; i < dayParts.length; i++) {
      if (dayParts[i] > dayParts[best]) best = i;
    }
    return NexDayPart.values[best];
  }

  /// Ticked checklist items as a fraction, or null with none.
  double? get checklistRate =>
      checklistItems == 0 ? null : checklistDone / checklistItems;
}

/// Counts [notes] — live ones only — in the zone [now] is in.
NexWritingStats nexWritingStats(List<Note> notes, {DateTime? now}) {
  final local = now ?? DateTime.now();
  DateTime zoned(DateTime value) =>
      local.isUtc ? value.toUtc() : value.toLocal();
  final today = DateTime.utc(local.year, local.month, local.day);
  final days = <DateTime>{};
  final recent = <DateTime>{};
  final parts = List<int>.filled(NexDayPart.values.length, 0);
  final types = <NoteType, int>{};
  final tags = <String, int>{};
  var count = 0;
  var items = 0;
  var done = 0;
  for (final note in notes) {
    if (note.deletedAt != null) continue;
    count++;
    final written = zoned(note.createdAt);
    final day = DateTime.utc(written.year, written.month, written.day);
    days.add(day);
    if (today.difference(day).inDays < 30) recent.add(day);
    parts[NexDayPart.of(written).index]++;
    types[note.type] = (types[note.type] ?? 0) + 1;
    for (final tag in note.tags) {
      final name = tag.name.trim();
      if (name.isNotEmpty) tags[name] = (tags[name] ?? 0) + 1;
    }
    if (note.type == NoteType.checklist) {
      items += note.checklistItems.length;
      done += note.checklistItems.where((item) => item.done).length;
    }
  }
  List<(K, int)> ranked<K>(Map<K, int> counts, int take) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(take)) (e.key, e.value)];
  }

  return NexWritingStats(
    notes: count,
    days: days.length,
    activeLast30: recent.length,
    dayParts: parts,
    types: ranked(types, NoteType.values.length),
    tags: ranked(tags, 5),
    checklistItems: items,
    checklistDone: done,
  );
}

/// The notes a portrait is written from: up to [limit] of them, spread across
/// the whole library rather than the newest, one line each.
///
/// ```
/// 3 months ago | checklist #trip | tickets · passport · charger
/// 2 days ago | text | idea: a small shelf for the hallway
/// ```
///
/// Spread, because the newest eighty notes of someone who has spent a week
/// moving house describe the move, not the person. Notes with no words of
/// their own — a photo without a caption — are left out, and every line is
/// cut at [maxTextLength] so one long note cannot take the budget.
///
/// Returns the lines and the ids of the notes they came from, so the
/// disclosure log can say which notes went out.
({String text, List<String> ids}) nexPortraitSource(
  List<Note> notes, {
  int limit = 80,
  int maxTextLength = 200,
  DateTime? now,
}) {
  final local = now ?? DateTime.now();
  final live = [
    for (final note in notes)
      if (note.deletedAt == null && (note.displayText ?? '').trim().isNotEmpty)
        note,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final picked = <Note>[];
  if (live.length <= limit) {
    picked.addAll(live);
  } else {
    final step = live.length / limit;
    for (var i = 0; i < limit; i++) {
      picked.add(live[(i * step).floor()]);
    }
  }
  final lines = <String>[];
  for (final note in picked) {
    final flat = note.displayText!.replaceAll(RegExp(r'\s+'), ' ').trim();
    final text = flat.length <= maxTextLength
        ? flat
        : '${flat.substring(0, maxTextLength).trimRight()}…';
    final tags = [
      for (final tag in note.tags.take(3))
        ' #${tag.name.trim().replaceAll(RegExp(r'\s+'), '_')}',
    ].join();
    lines.add(
      '${_age(local.difference(note.createdAt))} | '
      '${note.type.name}$tags | $text',
    );
  }
  return (text: lines.join('\n'), ids: [for (final note in picked) note.id]);
}

String _age(Duration age) {
  final days = age.inDays;
  if (days < 1) return 'today';
  if (days < 30) return '$days days ago';
  if (days < 365) return '${days ~/ 30} months ago';
  return '${days ~/ 365} years ago';
}

/// One quality a portrait names, how strongly it shows, and why.
class NexPortraitTrait {
  const NexPortraitTrait({
    required this.name,
    required this.score,
    required this.line,
  });

  final String name;

  /// 0–100.
  final int score;

  /// One sentence of evidence from the notes.
  final String line;

  Map<String, Object> toJson() => {'name': name, 'score': score, 'line': line};
}

/// The written half of a portrait, as a model returned it and as it is kept.
class NexPortrait {
  const NexPortrait({
    required this.headline,
    required this.portrait,
    required this.traits,
    required this.strengths,
    required this.invitation,
    required this.writtenAt,
    required this.basedOn,
  });

  /// A few words: who this person is as somebody who writes things down.
  final String headline;

  /// Three or four sentences, in the second person.
  final String portrait;
  final List<NexPortraitTrait> traits;
  final List<String> strengths;

  /// One gentle, practical suggestion. May be empty.
  final String invitation;
  final DateTime writtenAt;

  /// How many notes it was read from.
  final int basedOn;

  Map<String, Object> toJson() => {
    'headline': headline,
    'portrait': portrait,
    'traits': [for (final trait in traits) trait.toJson()],
    'strengths': strengths,
    'invitation': invitation,
    'writtenAt': writtenAt.toUtc().toIso8601String(),
    'basedOn': basedOn,
  };

  String encode() => jsonEncode(toJson());

  /// What was kept, or null when it is missing or unreadable.
  static NexPortrait? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final value = jsonDecode(stored);
      if (value is! Map<String, dynamic>) return null;
      return _from(
        value,
        writtenAt: DateTime.tryParse(value['writtenAt'] as String? ?? ''),
        basedOn: value['basedOn'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// A model's reply, read leniently — fences, a sentence before the object —
  /// and checked strictly: a portrait missing its headline, its paragraph or
  /// its traits is no portrait, and null says so.
  static NexPortrait? parse(
    String? reply, {
    required DateTime writtenAt,
    required int basedOn,
  }) {
    if (reply == null) return null;
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final value = jsonDecode(reply.substring(start, end + 1));
      if (value is! Map<String, dynamic>) return null;
      return _from(value, writtenAt: writtenAt, basedOn: basedOn);
    } catch (_) {
      return null;
    }
  }

  static NexPortrait? _from(
    Map<String, dynamic> value, {
    required DateTime? writtenAt,
    required int basedOn,
  }) {
    String text(Object? raw, int max) {
      final flat = raw is String
          ? raw.replaceAll(RegExp(r'[ \t]+'), ' ').trim()
          : '';
      return flat.length <= max ? flat : '${flat.substring(0, max).trim()}…';
    }

    final headline = text(value['headline'], 60);
    final portrait = text(value['portrait'], 900);
    final traits = <NexPortraitTrait>[
      for (final raw
          in (value['traits'] is List ? value['traits'] as List : []))
        if (raw is Map && text(raw['name'], 32).isNotEmpty)
          NexPortraitTrait(
            name: text(raw['name'], 32),
            score: switch (raw['score']) {
              final num n when n.isFinite => n.round().clamp(0, 100),
              _ => 50,
            },
            line: text(raw['line'], 200),
          ),
    ].take(6).toList();
    final strengths = <String>[
      for (final raw
          in (value['strengths'] is List ? value['strengths'] as List : []))
        if (text(raw, 40).isNotEmpty) text(raw, 40),
    ].take(5).toList();
    if (headline.isEmpty || portrait.isEmpty || traits.length < 3) {
      return null;
    }
    return NexPortrait(
      headline: headline,
      portrait: portrait,
      traits: traits,
      strengths: strengths,
      invitation: text(value['invitation'], 240),
      writtenAt: writtenAt ?? DateTime.now().toUtc(),
      basedOn: basedOn,
    );
  }
}

/// [stats] as the plain facts a portrait's prompt is given, in English for
/// the model: counts it should not have to guess at from a sample.
String nexWritingFacts(NexWritingStats stats) {
  final parts = [
    for (final part in NexDayPart.values)
      '${part.name} ${stats.dayParts[part.index]}',
  ].join(', ');
  return [
    'notes counted: ${stats.notes}',
    'days with a note: ${stats.days}',
    'days with a note in the last 30: ${stats.activeLast30}',
    'when notes are written: $parts',
    'kinds: ${[for (final (type, n) in stats.types) '${type.name} $n'].join(', ')}',
    if (stats.tags.isNotEmpty)
      'most used tags: ${[for (final (name, n) in stats.tags) '$name ($n)'].join(', ')}',
    if (stats.checklistRate case final rate?)
      'checklist items ticked: ${(rate * 100).round()}%',
  ].join('\n');
}
