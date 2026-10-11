import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';

/// How old someone born on [birthday] is on [today], and how many days until
/// they turn a year older.
///
/// By the calendar they read dates in: a Persian birthday comes round on its
/// Persian day, which drifts a day either way against the Gregorian one. A
/// birthday on a day the year does not have — 29 February, 30 Esfand — falls
/// on the month's last day instead.
({int age, int daysUntil}) profileBirthdayInfo(
  DateTime birthday,
  DateTime today, {
  required bool solar,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final ({int year, int month, int day}) born;
  final int thisYear;
  final DateTime Function(int year) on;
  if (solar && birthday.year >= 561 && day.year <= 3797) {
    born = nexPersianDate(birthday);
    thisYear = nexPersianDate(day).year;
    on = (year) => nexGregorianDate(
      year,
      born.month,
      math.min(born.day, nexPersianMonthDays(year, born.month)),
    );
  } else {
    born = (year: birthday.year, month: birthday.month, day: birthday.day);
    thisYear = day.year;
    on = (year) => DateTime(
      year,
      born.month,
      math.min(born.day, DateTime(year, born.month + 1, 0).day),
    );
  }
  var year = thisYear;
  var next = on(year);
  if (next.isBefore(day)) next = on(++year);
  // Counted between UTC dates, so a clock change on the way does not lose a
  // day to a 23-hour difference.
  final days = DateTime.utc(
    next.year,
    next.month,
    next.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  return (age: year - born.year - (days == 0 ? 0 : 1), daysUntil: days);
}

/// "Birthday in 23 days", "tomorrow", or a happy birthday on the day.
String profileBirthdayCountdown(AppLocalizations l10n, int days) =>
    switch (days) {
      0 => l10n.profileBirthdayToday,
      1 => l10n.profileBirthdayTomorrow,
      _ => l10n.profileBirthdayIn(
        nexDigits('$days', persian: l10n.localeName == 'fa'),
      ),
    };

/// The top of the profile: the person as the app sees them.
///
/// The name and bio are drawn from what is being typed below, so the page
/// shows the result while it is being written. Behind them sits a small
/// constellation — Nex's "one mind, a thousand connections" — laid out from
/// the name itself: every name draws its own, and it rearranges as the name
/// is typed.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.photo,
    required this.name,
    required this.bio,
    required this.birthdayLine,
    required this.onPhoto,
  });

  final File? photo;
  final String name;
  final String bio;

  /// The countdown to the next birthday, or null when none is set.
  final String? birthdayLine;

  /// Opens the photo choices.
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = scheme.onPrimaryContainer;
    final trimmed = name.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(NexRadius.xl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: CustomPaint(
                    key: ValueKey(trimmed),
                    painter: _Constellation(seed: _seedOf(trimmed), color: ink),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.lg,
                NexSpacing.xl,
                NexSpacing.lg,
                NexSpacing.lg,
              ),
              child: Column(
                children: [
                  _ProfileAvatar(
                    photo: photo,
                    name: trimmed,
                    tooltip: l10n.profileChangePhoto,
                    onTap: onPhoto,
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Text(
                    trimmed.isEmpty ? l10n.yourName : trimmed,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: trimmed.isEmpty ? ink.withValues(alpha: 0.6) : ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (bio.trim().isNotEmpty) ...[
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      bio.trim(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ink.withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (birthdayLine case final line?) ...[
                    const SizedBox(height: NexSpacing.sm),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(NexRadius.xl),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.md,
                          vertical: NexSpacing.xs,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cake_outlined, size: 16, color: ink),
                            const SizedBox(width: NexSpacing.xs),
                            Text(
                              line,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A seed that is the same for the same name on every run — unlike
  /// [String.hashCode], which is free to change between them.
  static int _seedOf(String name) {
    var seed = 17;
    for (final unit in name.codeUnits) {
      seed = (seed * 31 + unit) & 0x3fffffff;
    }
    return seed;
  }
}

/// The picture, or the name's initials, on a ring the colour of the page —
/// with a camera badge saying it can be changed. The whole of it is the
/// button, and nothing outside it is.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.photo,
    required this.name,
    required this.tooltip,
    required this.onTap,
  });

  final File? photo;
  final String name;
  final String tooltip;
  final VoidCallback onTap;

  static const _size = 112.0;

  String get _initials {
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    final first = words.first.characters.first;
    return words.length == 1 ? first : '$first‌${words.last.characters.first}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final photo = this.photo;
    final initials = _initials;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox.square(
          dimension: _size,
          child: Stack(
            children: [
              Positioned.fill(
                child: Material(
                  shape: CircleBorder(
                    side: BorderSide(color: scheme.surface, width: 4),
                  ),
                  color: scheme.secondaryContainer,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: photo != null
                        ? Image.file(
                            photo,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Center(
                            child: initials.isEmpty
                                ? Icon(
                                    Icons.person_outline,
                                    size: 48,
                                    color: scheme.onSecondaryContainer,
                                  )
                                : Text(
                                    initials,
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                          color: scheme.onSecondaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                          ),
                  ),
                ),
              ),
              PositionedDirectional(
                end: 2,
                bottom: 2,
                child: IgnorePointer(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                      border: Border.all(color: scheme.surface, width: 3),
                    ),
                    child: Icon(
                      Icons.photo_camera_outlined,
                      size: 16,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scatter of points joined to their nearest neighbours, laid out from
/// [seed]. Kept faint and to the edges' side of the middle, so it is texture
/// behind the name rather than something competing with it.
class _Constellation extends CustomPainter {
  _Constellation({required this.seed, required this.color});

  final int seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final points = [
      for (var i = 0; i < 16; i++)
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
    ];
    final line = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    final dot = Paint()..color = color.withValues(alpha: 0.28);
    for (final a in points) {
      final nearest = [...points]
        ..sort((x, y) => (x - a).distance.compareTo((y - a).distance));
      // nearest[0] is the point itself.
      for (final b in nearest.skip(1).take(2)) {
        canvas.drawLine(a, b, line);
      }
    }
    for (final a in points) {
      canvas.drawCircle(a, 1.5 + random.nextDouble() * 2, dot);
    }
  }

  @override
  bool shouldRepaint(_Constellation old) =>
      old.seed != seed || old.color != color;
}
