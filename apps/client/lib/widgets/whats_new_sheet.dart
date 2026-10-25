import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import 'nex_dialog.dart';

/// One line of a release, split the way the changelog writes it:
/// `**Title.** what changed`.
@immutable
class WhatsNewItem {
  const WhatsNewItem({required this.title, required this.body});

  final String title;
  final String body;
}

/// The bullets of [version]'s section in a changelog, newest file format:
/// `## vX.Y.Z` headings, `- **Title.** body` bullets.
@visibleForTesting
List<WhatsNewItem> whatsNewItems(String raw, String version) {
  final items = <WhatsNewItem>[];
  var inside = false;
  final bold = RegExp(r'^\*\*(.+?)\*\*\s*(.*)$');
  for (final line in raw.split('\n')) {
    if (line.startsWith('## ')) {
      if (inside) break;
      inside = line.substring(3).trim() == 'v$version';
      continue;
    }
    if (!inside || !line.startsWith('- ')) continue;
    final text = line.substring(2).trim();
    final match = bold.firstMatch(text);
    String clean(String s) => s.replaceAll('**', '').trim();
    items.add(
      match == null
          ? WhatsNewItem(title: '', body: clean(text))
          : WhatsNewItem(
              title: clean(match.group(1)!).replaceAll(RegExp(r'[.:]$'), ''),
              body: clean(match.group(2)!),
            ),
    );
  }
  return items;
}

/// Shows "What's new" once after an update (2.3.0).
///
/// Not on a fresh install — the first launch has its own welcome — and not
/// twice for one version. A launch that something else is already using (a
/// tapped reminder, the app lock) leaves it for the next one.
Future<void> nexMaybeShowWhatsNew(
  BuildContext context,
  NexPreferences preferences,
) async {
  final seen = preferences.whatsNewSeen;
  if (seen == nexAppVersion) return;
  if (seen == null && !preferences.onboardingComplete) {
    await preferences.setWhatsNewSeen(nexAppVersion);
    return;
  }
  final persian = Localizations.localeOf(context).languageCode == 'fa';
  String raw;
  try {
    raw = await rootBundle.loadString(
      persian ? 'assets/CHANGELOG.fa.md' : 'assets/CHANGELOG.md',
    );
  } catch (_) {
    return;
  }
  await preferences.setWhatsNewSeen(nexAppVersion);
  final items = whatsNewItems(raw, nexAppVersion);
  if (items.isEmpty || !context.mounted) return;
  await nexShowSheet<void>(
    context: context,
    builder: (_) => WhatsNewSheet(version: nexAppVersion, items: items),
  );
}

/// The sheet: the version as a lit capsule with a burst of sparks behind it,
/// then each change arriving in turn.
class WhatsNewSheet extends StatefulWidget {
  const WhatsNewSheet({super.key, required this.version, required this.items});

  final String version;
  final List<WhatsNewItem> items;

  @override
  State<WhatsNewSheet> createState() => _WhatsNewSheetState();
}

class _WhatsNewSheetState extends State<WhatsNewSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: NexMotion.receipt * 3,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = 1;
    } else if (_clock.value == 0 && !_clock.isAnimating) {
      unawaited(_clock.forward());
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final version = nexDigits(widget.version, persian: persian);
    final media = MediaQuery.sizeOf(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 132,
              child: AnimatedBuilder(
                animation: _clock,
                builder: (context, _) => CustomPaint(
                  painter: _SparkPainter(
                    t: _clock.value,
                    colors: [scheme.primary, scheme.tertiary, scheme.secondary],
                  ),
                  child: Center(
                    child: Transform.scale(
                      scale: Curves.easeOutBack.transform(
                        (_clock.value * 3).clamp(0.0, 1.0),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.lg,
                          vertical: NexSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(NexRadius.pill),
                          gradient: LinearGradient(
                            colors: [scheme.primary, scheme.tertiary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Text(
                          version,
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
              child: Column(
                children: [
                  Text(
                    l10n.whatsNewTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  Text(
                    l10n.whatsNewSubtitle(version),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
                itemCount: widget.items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: NexSpacing.sm),
                itemBuilder: (context, i) => _Arriving(
                  clock: _clock,
                  index: i,
                  child: _ItemCard(
                    item: widget.items[i],
                    number: nexDigits('${i + 1}', persian: persian),
                    tint: [
                      scheme.primary,
                      scheme.tertiary,
                      scheme.secondary,
                    ][i % 3],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(NexSpacing.md),
              child: FilledButton(
                key: const ValueKey('whats-new-done'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.whatsNewDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A change, sliding up into place a beat after the one above it.
class _Arriving extends StatelessWidget {
  const _Arriving({
    required this.clock,
    required this.index,
    required this.child,
  });

  final Animation<double> clock;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: clock,
    child: child,
    builder: (context, child) {
      final start = 0.18 + math.min(index, 8) * 0.06;
      final p = NexMotion.curve.transform(
        ((clock.value - start) / 0.3).clamp(0.0, 1.0),
      );
      return Opacity(
        opacity: p,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - p)),
          child: child,
        ),
      );
    },
  );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.number,
    required this.tint,
  });

  final WhatsNewItem item;
  final String number;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        border: BorderDirectional(start: BorderSide(color: tint, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: theme.textTheme.labelLarge?.copyWith(
                color: tint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.title.isNotEmpty) ...[
                  Text(item.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: NexSpacing.xs),
                ],
                Text(
                  item.body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sparks thrown out from behind the version once, as it lands.
class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.t, required this.colors});

  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final burst = ((t - 0.05) / 0.45).clamp(0.0, 1.0);
    if (burst <= 0 || burst >= 1) return;
    final center = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(burst);
    const count = 18;
    for (var i = 0; i < count; i++) {
      final angle = i * 2 * math.pi / count + (i.isEven ? 0.1 : -0.1);
      final reach = (i.isEven ? 92.0 : 70.0) * eased;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * reach;
      canvas.drawCircle(
        point,
        (i % 3 == 0 ? 3.5 : 2.4) * (1 - burst * 0.6),
        Paint()..color = colors[i % colors.length].withValues(alpha: 1 - burst),
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}
