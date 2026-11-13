import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';

/// One change in a release, split the way the changelog writes it:
/// `**Title.** what changed`.
@immutable
class WhatsNewItem {
  const WhatsNewItem({required this.title, required this.body});

  final String title;
  final String body;

  bool matches(String query) =>
      title.toLowerCase().contains(query) || body.toLowerCase().contains(query);
}

/// One `## vX.Y.Z` section: an optional opening paragraph and its changes.
@immutable
class WhatsNewRelease {
  const WhatsNewRelease({
    required this.version,
    required this.intro,
    required this.items,
  });

  final String version;
  final String intro;
  final List<WhatsNewItem> items;
}

/// Every release in a changelog, newest first, as the file is written.
///
/// Older sections are not all bullets: some open with a paragraph, and some
/// bullets wrap onto indented lines. Both are kept, so the oldest release
/// reads as well as the newest.
@visibleForTesting
List<WhatsNewRelease> parseWhatsNewReleases(String raw) {
  final releases = <WhatsNewRelease>[];
  String? version;
  final intro = StringBuffer();
  final items = <StringBuffer>[];
  void flush() {
    if (version != null && (items.isNotEmpty || intro.isNotEmpty)) {
      releases.add(
        WhatsNewRelease(
          version: version,
          intro: _clean(intro.toString()),
          items: [for (final text in items) _item(text.toString())],
        ),
      );
    }
    intro.clear();
    items.clear();
  }

  for (final line in raw.split('\n')) {
    if (line.startsWith('## ')) {
      flush();
      final heading = line.substring(3).trim();
      version = heading.startsWith('v') ? heading.substring(1) : null;
      continue;
    }
    if (version == null) continue;
    if (line.startsWith('- ')) {
      items.add(StringBuffer(line.substring(2).trim()));
    } else if (line.trim().isEmpty) {
      continue;
    } else if (items.isNotEmpty) {
      items.last.write(' ${line.trim()}');
    } else {
      intro.write('${intro.isEmpty ? '' : ' '}${line.trim()}');
    }
  }
  flush();
  return releases;
}

String _clean(String s) => s.replaceAll('**', '').trim();

WhatsNewItem _item(String text) {
  final match = RegExp(r'^\*\*(.+?)\*\*\s*(.*)$').firstMatch(text);
  if (match == null) return WhatsNewItem(title: '', body: _clean(text));
  return WhatsNewItem(
    title: _clean(match.group(1)!).replaceAll(RegExp(r'[.:]$'), ''),
    body: _clean(match.group(2)!),
  );
}

/// The changes of [version] in a changelog.
@visibleForTesting
List<WhatsNewItem> whatsNewItems(String raw, String version) =>
    parseWhatsNewReleases(raw)
        .where((r) => r.version == version)
        .firstOrNull
        ?.items ??
    const [];

/// The whole history, in the reader's language where it was written in it:
/// each release takes its Persian notes when CHANGELOG.fa.md has them, its
/// English otherwise (the Persian file starts later than the English one).
@visibleForTesting
List<WhatsNewRelease> mergeWhatsNew(
  List<WhatsNewRelease> english,
  List<WhatsNewRelease>? persian,
) {
  if (persian == null) return english;
  final byVersion = {for (final r in persian) r.version: r};
  return [for (final r in english) byVersion[r.version] ?? r];
}

/// "What's new" (2.3.1): every release Nex has had, opened from About.
///
/// The current version on top, lit, with its changes laid out in full; under
/// it the earlier releases as a strand, newest first, each folded to its
/// headlines until tapped. A search runs through all of them at once, to
/// answer "when did this arrive?".
class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  static Future<void> show(BuildContext context, NexPreferences preferences) {
    unawaited(preferences.setWhatsNewSeen(nexAppVersion));
    return Navigator.of(context)
        .push<void>(NexPageRoute<void>(builder: (_) => const WhatsNewScreen()));
  }

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

Future<List<WhatsNewRelease>> _load(bool persian) async {
  // Not through the bundle's cache: a cached future belongs to the zone that
  // first asked, and the page is read once per opening anyway. Under a test
  // run in random order the first test's fake clock owned it, and every test
  // after it waited on a read that never finished.
  final english = parseWhatsNewReleases(
    await rootBundle.loadString('assets/CHANGELOG.md', cache: false),
  );
  if (!persian) return english;
  List<WhatsNewRelease>? fa;
  try {
    fa = parseWhatsNewReleases(
      await rootBundle.loadString('assets/CHANGELOG.fa.md', cache: false),
    );
  } catch (_) {}
  return mergeWhatsNew(english, fa);
}

class _WhatsNewScreenState extends State<WhatsNewScreen>
    with SingleTickerProviderStateMixin {
  Future<List<WhatsNewRelease>>? _releases;
  final _search = TextEditingController();
  final _open = <String>{};
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: NexMotion.receipt * 3,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    // Read each time the page opens: a few hundred kilobytes, parsed in a
    // blink, and only what is on screen is ever built.
    _releases ??= _load(persian);
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock.value = 1;
    } else if (_clock.value == 0 && !_clock.isAnimating) {
      unawaited(_clock.forward());
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: NexAppBar(title: Text(l10n.whatsNewTitle)),
      body: FutureBuilder<List<WhatsNewRelease>>(
        future: _releases,
        builder: (context, snapshot) {
          final all = snapshot.data;
          if (all == null) {
            return snapshot.hasError
                ? Center(child: Text(l10n.changelogEmpty))
                : const SizedBox.shrink();
          }
          if (all.isEmpty) return Center(child: Text(l10n.changelogEmpty));
          return _list(context, all);
        },
      ),
    );
  }

  Widget _list(BuildContext context, List<WhatsNewRelease> all) {
    final l10n = AppLocalizations.of(context);
    final query = _search.text.trim().toLowerCase();
    final current =
        all.where((r) => r.version == nexAppVersion).firstOrNull ?? all.first;
    final earlier = [
      for (final r in all)
        if (r != current)
          if (query.isEmpty) r else ?_filter(r, query),
    ];
    final currentHit = query.isEmpty ? current : _filter(current, query);
    final rows = <Widget Function()>[
      // First, so a search is one tap away however long the newest
      // release's notes are.
      () => _searchField(context),
      if (query.isEmpty) () => _hero(context, current),
      if (query.isNotEmpty && currentHit != null)
        () => _ReleaseCard(
          release: currentHit,
          expanded: true,
          latest: true,
          first: true,
          last: earlier.isEmpty,
          onTap: null,
        ),
      if (query.isEmpty && earlier.isNotEmpty)
        () => _sectionLabel(context, l10n.whatsNewEarlier),
      if (query.isNotEmpty && earlier.isEmpty && currentHit == null)
        () => Padding(
          padding: const EdgeInsets.all(NexSpacing.xl),
          child: Text(
            l10n.whatsNewNoMatch,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (var i = 0; i < earlier.length; i++)
        () => _ReleaseCard(
          key: ValueKey('whats-new-${earlier[i].version}'),
          release: earlier[i],
          expanded: query.isNotEmpty || _open.contains(earlier[i].version),
          latest: false,
          first: i == 0 && (query.isEmpty || currentHit == null),
          last: i == earlier.length - 1,
          onTap: query.isNotEmpty
              ? null
              : () => setState(() {
                  final v = earlier[i].version;
                  if (!_open.remove(v)) _open.add(v);
                }),
        ),
    ];
    return ListView.builder(
      padding: EdgeInsets.only(bottom: NexSpacing.xl + nexBottomInset(context)),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i](),
    );
  }

  /// [release] cut down to what [query] finds, or null when nothing does.
  WhatsNewRelease? _filter(WhatsNewRelease release, String query) {
    final items = release.items.where((it) => it.matches(query)).toList();
    final introHit = release.intro.toLowerCase().contains(query);
    if (items.isEmpty && !introHit && !release.version.contains(query)) {
      return null;
    }
    return WhatsNewRelease(
      version: release.version,
      intro: release.intro,
      items: items.isEmpty && !introHit ? release.items : items,
    );
  }

  Widget _searchField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.sm,
      ),
      child: NexSearchField(
        fieldKey: const ValueKey('whats-new-search'),
        controller: _search,
        hintText: l10n.whatsNewSearchHint,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      NexSpacing.lg,
      NexSpacing.md,
      NexSpacing.lg,
      NexSpacing.sm,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  /// The version that is running, as a lit capsule with a burst of sparks
  /// behind it, and each of its changes arriving in turn.
  Widget _hero(BuildContext context, WhatsNewRelease release) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final version = nexDigits(release.version, persian: persian);
    final tints = [scheme.primary, scheme.tertiary, scheme.secondary];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 124,
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => CustomPaint(
              painter: _SparkPainter(t: _clock.value, colors: tints),
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
          child: Text(
            l10n.whatsNewSubtitle(version),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        for (var i = 0; i < release.items.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.md,
              0,
              NexSpacing.md,
              NexSpacing.sm,
            ),
            child: _Arriving(
              clock: _clock,
              index: i,
              child: _ItemCard(
                item: release.items[i],
                number: nexDigits('${i + 1}', persian: persian),
                tint: tints[i % 3],
              ),
            ),
          ),
      ],
    );
  }
}

/// An earlier release on the strand: a bead and a line down the start edge,
/// the version and how many changes it brought, its headlines while folded
/// and everything once opened.
class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    super.key,
    required this.release,
    required this.expanded,
    required this.latest,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final WhatsNewRelease release;
  final bool expanded;
  final bool latest;
  final bool first;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final tint = latest ? scheme.primary : scheme.secondary;
    final headlines = [
      for (final item in release.items)
        if (item.title.isNotEmpty) item.title,
    ];
    final preview = headlines.isNotEmpty
        ? headlines.take(3).join(' · ')
        : (release.intro.isNotEmpty
              ? release.intro
              : release.items.firstOrNull?.body ?? '');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: NexSpacing.xl,
            child: CustomPaint(
              painter: _StrandPainter(
                color: scheme.outlineVariant,
                bead: tint,
                first: first,
                last: last,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                end: NexSpacing.md,
                bottom: NexSpacing.sm,
              ),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(NexRadius.lg),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: AnimatedSize(
                    duration: NexMotion.standard,
                    curve: NexMotion.curve,
                    alignment: AlignmentDirectional.topStart,
                    child: Padding(
                      padding: const EdgeInsets.all(NexSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: NexSpacing.sm,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tint.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(
                                    NexRadius.pill,
                                  ),
                                ),
                                child: Text(
                                  nexDigits(release.version, persian: persian),
                                  textDirection: TextDirection.ltr,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: tint,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: NexSpacing.sm),
                              Expanded(
                                child: Text(
                                  l10n.whatsNewChanges(release.items.length),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (onTap != null)
                                AnimatedRotation(
                                  turns: expanded ? 0.5 : 0,
                                  duration: NexMotion.standard,
                                  child: Icon(
                                    Icons.expand_more,
                                    size: 20,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: NexSpacing.sm),
                          if (!expanded)
                            Text(
                              preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            )
                          else ...[
                            if (release.intro.isNotEmpty) ...[
                              NexMarkdown(
                                release.intro,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: NexSpacing.sm),
                            ],
                            for (final item in release.items)
                              _ItemLine(item: item, tint: tint),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One change inside an opened release.
class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.item, required this.tint});

  final WhatsNewItem item;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.title.isNotEmpty)
                  Text(item.title, style: theme.textTheme.titleSmall),
                NexMarkdown(
                  item.body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

/// The thread the releases hang on, with a bead level with each card's top.
class _StrandPainter extends CustomPainter {
  _StrandPainter({
    required this.color,
    required this.bead,
    required this.first,
    required this.last,
  });

  final Color color;
  final Color bead;
  final bool first;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    const beadY = NexSpacing.md + 10;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(x, first ? beadY : 0),
      Offset(x, last ? beadY : size.height),
      line,
    );
    canvas.drawCircle(Offset(x, beadY), 6, Paint()..color = bead);
    canvas.drawCircle(
      Offset(x, beadY),
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = bead.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(_StrandPainter old) =>
      old.color != color ||
      old.bead != bead ||
      old.first != first ||
      old.last != last;
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
                NexMarkdown(
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
