import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'occasion_math.dart';
import 'occasion_model.dart';
import 'occasion_text.dart';

/// The look of each kind of date (2.4.0): a pair of colours for its card,
/// and the mark that goes with it. A birthday is warm, an anniversary rose,
/// a remembrance a quiet dusk, anything else violet.
class OccasionLook {
  const OccasionLook(this.from, this.to, this.mark, this.icon);

  final Color from;
  final Color to;
  final String mark;

  /// In the ring on the day itself.
  final IconData icon;

  static OccasionLook of(OccasionKind kind) => switch (kind) {
    OccasionKind.birthday => const OccasionLook(
      Color(0xFFFF7A59),
      Color(0xFFFFB347),
      '🎂',
      Icons.cake_rounded,
    ),
    OccasionKind.anniversary => const OccasionLook(
      Color(0xFFE2557B),
      Color(0xFF9B4DCA),
      '💞',
      Icons.favorite_rounded,
    ),
    OccasionKind.memorial => const OccasionLook(
      Color(0xFF55657F),
      Color(0xFF353F66),
      '🕯️',
      Icons.local_florist_rounded,
    ),
    OccasionKind.other => const OccasionLook(
      Color(0xFF7B61FF),
      Color(0xFF3FA9F5),
      '📅',
      Icons.celebration_rounded,
    ),
  };

  LinearGradient get gradient => LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [from, to],
  );
}

/// The day and month a date falls on, in the occasion's own calendar.
({int month, int day}) occasionCalendarDay(Occasion occasion, DateTime date) {
  if (occasion.calendar == OccasionCalendar.jalali) {
    final d = nexPersianDate(date);
    return (month: d.month, day: d.day);
  }
  return (month: date.month, day: date.day);
}

/// A page torn from a desk calendar: the month on a coloured band, the day
/// large under it — in the calendar the occasion is kept in.
class OccasionDateTile extends StatelessWidget {
  const OccasionDateTile({
    super.key,
    required this.occasion,
    required this.date,
    this.size = 54,
  });

  final Occasion occasion;

  /// When it next falls; null for a date that cannot be worked out.
  final DateTime? date;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = OccasionLook.of(occasion.kind);
    final persian = NexModuleStrings.persian(context);
    final when = date;
    final shown = when == null ? null : occasionCalendarDay(occasion, when);
    final month = shown == null
        ? '—'
        : nexModuleMonthName(
            context,
            solar: occasion.calendar == OccasionCalendar.jalali,
            month: shown.month,
          );
    return SizedBox(
      width: size,
      height: size * 1.08,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(NexRadius.md),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NexRadius.md - 1),
          child: Column(
            children: [
              Container(
                height: size * 0.34,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: look.gradient),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NexSpacing.xs,
                    ),
                    child: Text(
                      month,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    shown == null
                        ? '?'
                        : nexDigits('${shown.day}', persian: persian),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1,
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

/// How close it is, drawn: a ring that fills as the year turns towards the
/// date, with the days left in the middle — or the mark itself on the day.
class OccasionCountdownRing extends StatelessWidget {
  const OccasionCountdownRing({
    super.key,
    required this.days,
    required this.icon,
    this.size = 84,
    this.color = Colors.white,
  });

  final int days;
  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final progress = days <= 0 ? 1.0 : (1 - days / 366).clamp(0.04, 1.0);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(progress: progress, color: color),
        child: Center(
          child: days <= 0
              ? Icon(icon, color: color, size: size * 0.42)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nexDigits('$days', persian: persian),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    Text(
                      occasionsStrings(
                        context,
                        days == 1 ? 'ringDay' : 'ringDays',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(4);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = color.withValues(alpha: 0.22);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Soft dots scattered over a card — confetti for a birthday, sparks for
/// the rest — drawn once from a fixed seed, so the card looks the same each
/// time it is seen. On the day itself they fall gently once.
class OccasionSparkle extends StatefulWidget {
  const OccasionSparkle({super.key, required this.celebrate});

  final bool celebrate;

  @override
  State<OccasionSparkle> createState() => _OccasionSparkleState();
}

class _OccasionSparkleState extends State<OccasionSparkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fall = AnimationController(
    vsync: this,
    // A slow fall: seven of the app's slow beats.
    duration: NexMotion.slow * 7,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.celebrate &&
        !MediaQuery.disableAnimationsOf(context) &&
        _fall.value == 1) {
      _fall.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _fall,
      builder: (context, _) => CustomPaint(
        painter: _SparklePainter(
          fall: Curves.easeOutCubic.transform(_fall.value),
        ),
      ),
    ),
  );
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter({required this.fall});

  /// 0 at the top of the drop, 1 settled.
  final double fall;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(11);
    for (var i = 0; i < 26; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = 1.5 + random.nextDouble() * 3;
      final lift = (1 - fall) * (size.height * 0.6 + random.nextDouble() * 40);
      final alpha = 0.12 + random.nextDouble() * 0.22;
      final paint = Paint()..color = Colors.white.withValues(alpha: alpha);
      final at = Offset(x, y - lift);
      if (i.isEven) {
        canvas.drawCircle(at, r, paint);
      } else {
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(random.nextDouble() * math.pi);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: r * 2.6, height: r),
            Radius.circular(r / 2),
          ),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.fall != fall;
}

/// The card at the top of the list and of an occasion's page: what it is,
/// who, how far away, the age it comes to — on its kind's colours.
class OccasionHeroCard extends StatelessWidget {
  const OccasionHeroCard({
    super.key,
    required this.occasion,
    required this.next,
    required this.today,
    required this.eyebrow,
    this.onTap,
    this.actions,
  });

  final Occasion occasion;
  final OccasionDay next;
  final DateTime today;
  final String eyebrow;
  final VoidCallback? onTap;

  /// Under the words, on the day: copy and share a greeting.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = OccasionLook.of(occasion.kind);
    final days = daysUntil(today, next.date);
    final years = yearsText(context, occasion, next);
    final title = occasion.title.isEmpty
        ? occasionsStrings(context, 'untitled')
        : occasion.title;
    const white = Colors.white;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        gradient: look.gradient,
        borderRadius: BorderRadius.circular(NexRadius.xl),
        boxShadow: [
          BoxShadow(
            color: look.from.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NexRadius.xl),
        child: Stack(
          children: [
            Positioned.fill(child: OccasionSparkle(celebrate: days == 0)),
            Padding(
              padding: const EdgeInsets.all(NexSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              eyebrow,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: white.withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(height: NexSpacing.xs),
                            Text(
                              title,
                              key: const ValueKey('occasion-hero-title'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: NexSpacing.xs),
                            Text(
                              [
                                occasionDateText(
                                  context,
                                  next.date,
                                  solar:
                                      occasion.calendar ==
                                      OccasionCalendar.jalali,
                                ),
                                ?years,
                              ].join(' · '),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: white.withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: NexSpacing.md),
                      OccasionCountdownRing(days: days, icon: look.icon),
                    ],
                  ),
                  if (actions case final actions?) ...[
                    const SizedBox(height: NexSpacing.md),
                    actions,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

/// «Today», «Tomorrow», «in 5 days» as a pill: the accent on the day, the
/// kind's colour this week, quiet further off.
class OccasionCountdownPill extends StatelessWidget {
  const OccasionCountdownPill({
    super.key,
    required this.occasion,
    required this.days,
  });

  final Occasion occasion;
  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = OccasionLook.of(occasion.kind);
    final near = days <= 7;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: days == 0 ? look.gradient : null,
        color: days == 0
            ? null
            : near
            ? look.from.withValues(alpha: 0.14)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.sm + 2,
          vertical: NexSpacing.xs,
        ),
        child: Text(
          countdownText(context, days),
          key: ValueKey('occasion-days-${occasion.id}'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: days == 0
                ? Colors.white
                : near
                ? look.from
                : scheme.onSurfaceVariant,
            fontWeight: near ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
