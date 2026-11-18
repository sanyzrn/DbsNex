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
import 'module_peek.dart';
import 'nex_fold_pill.dart';

/// One line of the home screen's dates from your tools.
class NexToolDate {
  const NexToolDate({
    required this.id,
    required this.module,
    required this.title,
    required this.at,
    this.count = 1,
    this.grouped = false,
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

  /// A module's private items under its name: said with how many there
  /// are even when it is one (2.8.6) — the name alone read as the module
  /// itself being due.
  final bool grouped;
}

/// What the home screen says about the modules' dates (2.8.4): what is
/// overdue and what falls due in the coming week, from every module that is
/// on, through each module's own `duesBetween`. Pure, so the rules are
/// tested as written.
///
/// - Done items are left out, and so is a day that has gone by (a birthday,
///   a warranty's end: [ModuleDue.passes]); a task still to do is looked
///   for up to 60 days back and said to be late.
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
        if (!due.isOver(today) && due.at.isBefore(end)) due,
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
          grouped: true,
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
          title: what == null
              ? due.title
              : due.title.isEmpty
              ? what
              : l10n.toolDatesWhat(due.title, what),
          at: due.at,
        ),
      );
    }
  }
  return lines..sort((a, b) => a.at.compareTo(b.at));
}

/// «today», «tomorrow», «in 3 days» or «2 days late» — see [nexDueWhen].
String nexToolDateWhen(AppLocalizations l10n, DateTime at, DateTime today) =>
    nexDueWhen(l10n, at, today);

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

  /// Lines shown while the card is folded, like the recap's two (2.8.6).
  static const folded = 2;

  /// Lines shown open; the rest are counted.
  static const limit = 10;

  @override
  State<NexToolDates> createState() => _NexToolDatesState();
}

class _NexToolDatesState extends State<NexToolDates> {
  Map<NexModule, List<ModuleDue>> _dues = const {};
  StreamSubscription<String>? _changes;
  String _modulesOn = '';
  int _loads = 0;
  late bool _opened = widget.preferences.toolDatesOpen;

  /// Modules a change announced, waiting for one debounce window to pass.
  /// A burst of writes — ticking a habit a few times, a restore replaying a
  /// module's records — lands as one read of the modules that changed,
  /// rather than a read of every one of them per write.
  final _pendingModules = <String>{};
  Timer? _reload;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _changes = widget.services.moduleChanges.listen(_onModuleChange);
    widget.preferences.addListener(_onPreferences);
    _modulesOn = _onIds();
    unawaited(_load());
  }

  @override
  void dispose() {
    _reload?.cancel();
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

  /// Only the module that wrote is re-read. Every module used to be: one
  /// ticked habit re-read the words, the cheques, the car and the rest —
  /// each a full-record walk on this isolate — for a line that says what
  /// one module holds.
  void _onModuleChange(String module) {
    _pendingModules.add(module);
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 250), () {
      final ids = List.of(_pendingModules);
      _pendingModules.clear();
      if (mounted) unawaited(_loadModules(ids));
    });
  }

  ({DateTime from, DateTime to}) _range() {
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    return (
      from: today.subtract(const Duration(days: 60)),
      to: today.add(const Duration(days: 8)),
    );
  }

  /// The window of every module that is on — overdues live in the past
  /// sixty days, the coming week in the next eight.
  Future<Map<NexModule, List<ModuleDue>>> _readAll() async {
    if (!widget.preferences.showToolDates) return const {};
    final (:from, :to) = _range();
    final modules = [
      for (final module in nexModulesOn(widget.preferences))
        if (module is NexStoredModule) module,
    ];
    // One flight per module, together: the reads go to the database worker
    // as separate commands, and asking for them one after another made the
    // card's first paint wait for a chain of them.
    final dues = await Future.wait([
      for (final module in modules) _readOne(module, from, to),
    ]);
    return {
      for (var i = 0; i < modules.length; i++)
        if (dues[i].isNotEmpty) modules[i]: dues[i],
    };
  }

  Future<List<ModuleDue>> _readOne(
    NexStoredModule module,
    DateTime from,
    DateTime to,
  ) async {
    try {
      return await module.dues(
        NexModuleStore(widget.services, module.id),
        from,
        to,
      );
    } catch (_) {
      // One module's unreadable records never hide the others.
      return const [];
    }
  }

  Future<void> _load() async {
    final load = ++_loads;
    final result = await _readAll();
    if (!mounted || load != _loads) return;
    setState(() => _dues = result);
  }

  /// Re-reads only [ids]' dues and merges them into what is shown.
  Future<void> _loadModules(List<String> ids) async {
    final load = ++_loads;
    final result = Map.of(_dues);
    for (final id in ids) {
      // Whatever this module holds now replaces what it held — including
      // nothing, when it was emptied or switched off between the write and
      // this read.
      result.removeWhere((module, _) => module.id == id);
      if (!widget.preferences.showToolDates) continue;
      NexStoredModule? module;
      for (final m in nexModulesOn(widget.preferences)) {
        if (m is NexStoredModule && m.id == id) {
          module = m;
          break;
        }
      }
      if (module == null) continue;
      final (:from, :to) = _range();
      final dues = await _readOne(module, from, to);
      if (dues.isNotEmpty) result[module] = dues;
    }
    if (!mounted || load != _loads) return;
    setState(() => _dues = result);
  }

  // The card's lines, remembered between rebuilds: every full-screen
  // rebuild below this card used to re-filter and re-sort every module's
  // dues and re-string every line, for a list that only changes when the
  // dues, the day, or the language do.
  List<NexToolDate> _lines = const [];
  Map<NexModule, List<ModuleDue>>? _linesFor;
  int _linesDay = 0;
  Locale? _linesLocale;
  bool? _linesHidden;

  List<NexToolDate> _linesOf(
    AppLocalizations l10n,
    Locale locale,
    DateTime now,
  ) {
    final day = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    if (!identical(_linesFor, _dues) ||
        _linesDay != day ||
        _linesLocale != locale ||
        _linesHidden != widget.hidden) {
      _lines = widget.hidden ? const [] : nexToolDates(_dues, l10n, now);
      _linesFor = _dues;
      _linesDay = day;
      _linesLocale = locale;
      _linesHidden = widget.hidden;
    }
    return _lines;
  }

  void _open(NexModule module) {
    // The quick view first, like a pinned tile (2.8.5): what is due and
    // the module's facts, with the module itself one button away.
    if (module is NexStoredModule) {
      unawaited(
        nexShowModulePeek(
          context,
          module: module,
          services: widget.services,
          preferences: widget.preferences,
        ),
      );
      return;
    }
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

  void _toggle() {
    nexTick();
    setState(() => _opened = !_opened);
    unawaited(widget.preferences.setToolDatesOpen(_opened));
  }

  String _when(AppLocalizations l10n, DateTime at, DateTime today) =>
      nexToolDateWhen(l10n, at, today);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    final lines = _linesOf(
      l10n,
      Localizations.maybeLocaleOf(context) ?? const Locale('en'),
      now,
    );
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
    final folds = lines.length > NexToolDates.folded;
    final open = _opened && folds;
    final shown = lines
        .take(open ? NexToolDates.limit : NexToolDates.folded)
        .toList();
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
              InkWell(
                key: const ValueKey('tool-dates-fold'),
                onTap: folds ? _toggle : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.md,
                    vertical: NexSpacing.xs,
                  ),
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
                      if (folds)
                        NexFoldPill(
                          id: 'tool-dates',
                          collapsed: !open,
                          more: open
                              ? null
                              : l10n.toolDatesMore(lines.length - shown.length),
                          style: theme.textTheme.labelMedium,
                        ),
                    ],
                  ),
                ),
              ),
              for (final line in shown) _row(context, l10n, line, today),
              if (open && more > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.md,
                    vertical: NexSpacing.xs,
                  ),
                  child: Text(
                    l10n.toolDatesMore(more),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
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
                line.grouped || line.count > 1
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
