import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../modules/module_hero.dart';
import '../modules/module_registry.dart';
import '../modules/module_shared.dart';
import '../modules/nex_module_store.dart';
import '../modules/nex_stored_module.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';

/// One line of the home screen's dates from your tools.
class NexToolDate {
  const NexToolDate({
    required this.id,
    required this.module,
    required this.title,
    required this.at,
    this.count = 1,
  });

  /// Stable and unique on the card: the due item's id, or the module's for
  /// its private line.
  final String id;
  final NexModule module;

  /// The item in the person's own words — or, for money and health, the
  /// module's name only.
  final String title;
  final DateTime at;

  /// How many private items of the module this line stands for.
  final int count;
}

/// What the home screen says about the modules' dates (2.8.4): what is
/// overdue and what falls due in the coming week, from every module that is
/// on, through each module's own `duesBetween`. Pure, so the rules are
/// tested as written.
///
/// - Done items are left out; overdue ones are looked for up to 60 days back.
/// - A private item (money, health) never shows its title or amount: a
///   module's private items share one line under the module's name, at the
///   earliest of their days, with how many there are.
/// - Oldest first, at most [limit] lines; the caller says how many more.
List<NexToolDate> nexToolDates(
  Map<NexModule, List<ModuleDue>> byModule,
  AppLocalizations l10n,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(const Duration(days: 8));
  final lines = <NexToolDate>[];
  for (final MapEntry(key: module, value: dues) in byModule.entries) {
    final open = [
      for (final due in dues)
        if (!due.done && due.at.isBefore(end)) due,
    ];
    final private = open.where((d) => d.private).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (private.isNotEmpty) {
      lines.add(
        NexToolDate(
          id: 'private:${module.id}',
          module: module,
          title: module.title(l10n),
          at: private.first.at,
          count: private.length,
        ),
      );
    }
    for (final due in open.where((d) => !d.private)) {
      final what = module is NexStoredModule
          ? module.dueLabel(l10n, due.kind)
          : null;
      lines.add(
        NexToolDate(
          id: '${module.id}:${due.id}',
          module: module,
          title: what == null ? due.title : l10n.toolDatesWhat(due.title, what),
          at: due.at,
        ),
      );
    }
  }
  return lines..sort((a, b) => a.at.compareTo(b.at));
}

/// The card itself, above the notes, when there is anything to say.
class NexToolDates extends StatefulWidget {
  const NexToolDates({
    super.key,
    required this.services,
    required this.preferences,
    this.hidden = false,
    this.clock,
  });

  final NexServices services;
  final NexPreferences preferences;
  final bool hidden;
  final DateTime Function()? clock;

  static const limit = 4;

  @override
  State<NexToolDates> createState() => _NexToolDatesState();
}

class _NexToolDatesState extends State<NexToolDates> {
  Map<NexModule, List<ModuleDue>> _dues = const {};
  StreamSubscription<String>? _changes;
  String _modulesOn = '';
  int _loads = 0;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _changes = widget.services.moduleChanges.listen((_) => _load());
    widget.preferences.addListener(_onPreferences);
    _modulesOn = _onIds();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    widget.preferences.removeListener(_onPreferences);
    super.dispose();
  }

  String _onIds() => [
    if (widget.preferences.showToolDates)
      for (final module in nexModulesOn(widget.preferences)) module.id,
  ].join(',');

  void _onPreferences() {
    final ids = _onIds();
    if (ids == _modulesOn) return;
    _modulesOn = ids;
    unawaited(_load());
  }

  Future<void> _load() async {
    final load = ++_loads;
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: 60));
    final to = today.add(const Duration(days: 8));
    final result = <NexModule, List<ModuleDue>>{};
    if (widget.preferences.showToolDates) {
      for (final module in nexModulesOn(widget.preferences)) {
        if (module is! NexStoredModule) continue;
        try {
          final dues = await module.dues(
            NexModuleStore(widget.services, module.id),
            from,
            to,
          );
          if (dues.isNotEmpty) result[module] = dues;
        } catch (_) {
          // One module's unreadable records never hide the others.
        }
      }
    }
    if (!mounted || load != _loads) return;
    setState(() => _dues = result);
  }

  void _open(NexModule module) {
    unawaited(
      Navigator.of(context).push(
        NexPageRoute<void>(
          builder: (_) => module.open(
            services: widget.services,
            preferences: widget.preferences,
          ),
        ),
      ),
    );
  }

  String _when(AppLocalizations l10n, DateTime at, DateTime today) {
    final day = DateTime(at.year, at.month, at.day);
    final days = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    if (days < 0) return l10n.toolDatesLate(-days);
    if (days == 0) return l10n.toolDatesToday;
    if (days == 1) return l10n.toolDatesTomorrow;
    return l10n.toolDatesIn(days);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    final lines = widget.hidden
        ? const <NexToolDate>[]
        : nexToolDates(_dues, l10n, now);
    return AnimatedSize(
      duration: NexMotion.of(context, NexMotion.standard),
      curve: NexMotion.curve,
      alignment: Alignment.topCenter,
      child: lines.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.xs,
                NexSpacing.md,
                NexSpacing.sm,
              ),
              child: _card(context, l10n, lines, today),
            ),
    );
  }

  Widget _card(
    BuildContext context,
    AppLocalizations l10n,
    List<NexToolDate> lines,
    DateTime today,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = lines.take(NexToolDates.limit).toList();
    final more = lines.length - shown.length;
    return Semantics(
      container: true,
      label: l10n.toolDatesTitle,
      child: DecoratedBox(
        key: const ValueKey('tool-dates'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_note_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.toolDatesTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (more > 0)
                      Text(
                        l10n.toolDatesMore(more),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              for (final line in shown) _row(context, l10n, line, today),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    NexToolDate line,
    DateTime today,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final late = line.at.isBefore(today);
    final accent = nexModuleAccent(context, line.module.id);
    return InkWell(
      key: ValueKey('tool-date-${line.id}'),
      onTap: () => _open(line.module),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.md,
          vertical: NexSpacing.xs + 2,
        ),
        child: Row(
          children: [
            Icon(line.module.icon, size: 18, color: accent),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Text(
                line.count > 1
                    ? l10n.toolDatesCount(line.title, line.count)
                    : line.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            Text(
              _when(l10n, line.at, today),
              style: theme.textTheme.labelMedium?.copyWith(
                color: late ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: late ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
