import 'package:flutter/material.dart';

import 'quit_model.dart';

/// What can be quit, ready to pick: the words and the numbers that suit it.
///
/// A preset only chooses wording and sensible defaults; every number is the
/// person's to change, and nothing here is advice. [custom] is the person's
/// own habit, named by them.
class QuitPreset {
  const QuitPreset(
    this.key,
    this.icon, {
    this.packs = false,
    this.perDay = 1,
    this.minutesPerUnit = 0,
    this.safety = false,
  });

  final String key;
  final IconData icon;

  /// Sold in packs, so the price is asked per pack and per pieces in it
  /// (cigarettes). Everything else is priced per unit.
  final bool packs;

  /// The usual number a day, offered as the starting value.
  final int perDay;

  /// Minutes each unit usually takes, offered as the starting value; 0 when
  /// the time is not worth counting.
  final int minutesPerUnit;

  /// Stopping suddenly can be unsafe for some people (heavy drinking): the
  /// setup says so once, and does not claim to advise.
  final bool safety;
}

const quitPresets = <QuitPreset>[
  QuitPreset(
    'cigarette',
    Icons.smoke_free_outlined,
    packs: true,
    perDay: 20,
    minutesPerUnit: 5,
  ),
  QuitPreset('vape', Icons.cloud_off_outlined, perDay: 10, minutesPerUnit: 3),
  QuitPreset('alcohol', Icons.no_drinks_outlined, perDay: 2, safety: true),
  QuitPreset('caffeine', Icons.coffee_outlined, perDay: 3),
  QuitPreset('sugar', Icons.cookie_outlined, perDay: 3),
  QuitPreset(
    'social',
    Icons.phone_android_outlined,
    perDay: 10,
    minutesPerUnit: 10,
  ),
  QuitPreset('gambling', Icons.casino_outlined, perDay: 1),
  QuitPreset('custom', Icons.edit_outlined, perDay: 1),
];

QuitPreset quitPresetOf(String habit) => quitPresets.firstWhere(
  (p) => p.key == habit,
  orElse: () => quitPresets.last,
);

/// The days it takes for a mark to be earned, kept short and unromantic.
const quitMilestones = <int>[1, 3, 7, 14, 30, 60, 90, 180, 365];

/// The habits that have an attempt, one entry each: the attempt that is
/// running, or — when none is — the latest that ended. Running ones first,
/// newest start first within each group.
List<QuitAttempt> quitHabitsOf(List<QuitAttempt> attempts) {
  final byKey = <String, QuitAttempt>{};
  for (final attempt in attempts) {
    final held = byKey[attempt.key];
    if (held == null || _better(attempt, held)) byKey[attempt.key] = attempt;
  }
  return byKey.values.toList()..sort((a, b) {
    if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
    final byStart = b.startedAt.compareTo(a.startedAt);
    return byStart != 0 ? byStart : b.id.compareTo(a.id);
  });
}

bool _better(QuitAttempt a, QuitAttempt b) {
  if (a.isActive != b.isActive) return a.isActive;
  final byStart = a.startedAt.compareTo(b.startedAt);
  return byStart != 0 ? byStart > 0 : a.id.compareTo(b.id) > 0;
}
