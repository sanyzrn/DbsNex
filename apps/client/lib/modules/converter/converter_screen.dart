import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_date.dart';
import 'converter_date_tools.dart';
import 'converter_dates_view.dart';
import 'converter_format.dart';
import 'converter_history.dart';
import 'converter_number.dart';
import 'converter_outcome.dart';
import 'converter_recent.dart';
import 'converter_size_tables.dart';
import 'converter_sizes.dart';
import 'converter_sizes_view.dart';
import 'converter_strings.dart';
import 'converter_units.dart';
import 'converter_units_view.dart';
import 'converter_widgets.dart';

/// The module's one screen: three segments, one answer held at the top in the
/// module's own hero, and the fields that produce it underneath.
///
/// The answer follows every keystroke, so there is no Convert button to
/// forget. Nothing typed is thrown away: the whole state is kept as the
/// module's `draft` record, and the conversions made are kept as `recent`
/// (twenty at most) and `favorite`.
class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  ConverterTab _tab = ConverterTab.dates;

  ConverterCalendar _dateCalendar = ConverterCalendar.solar;
  final TextEditingController _dateField = TextEditingController();
  ConverterDate? _date;

  UnitCategory _category = UnitCategory.length;
  String _fromId = 'm';
  String _toId = 'foot';
  final TextEditingController _valueField = TextEditingController(text: '1');

  String _chartId = 'womenTops';
  String _systemId = 'eu';
  int _sizeRow = 2;

  List<ConverterEntry> _recents = const [];
  List<ConverterEntry> _favorites = const [];
  bool _failed = false;
  int _token = 0;
  bool _started = false;
  StreamSubscription<void>? _changes;
  Timer? _settle;

  /// The conversion waiting to be kept, taken when it was made — not when
  /// the timer fires, by which time another tab may be on screen (2.7.1).
  ConverterEntry? _pending;

  /// The row the last kept conversion went to, and what it was about, so the
  /// next change to the same thing replaces it — see [converterRemember].
  String? _keptId;
  String? _keptSubject;
  DateTime? _keptAt;

  /// Whether a number has been typed on the Units tab since its category was
  /// chosen. Until then, the units on either side are only a starting point.
  bool _unitsTyped = false;

  @override
  void initState() {
    super.initState();
    final pair = converterDefaultPair(_category);
    _fromId = pair.from;
    _toId = pair.to;
    _changes = widget.store.changes.listen((_) => unawaited(_loadHistory()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _dateCalendar = NexModuleCalendar.solarOf(context)
        ? ConverterCalendar.solar
        : ConverterCalendar.gregorian;
    _date = ConverterDate.today(_dateCalendar);
    _dateField.text = converterDateNumeric(context, _date!);
    unawaited(_loadHistory(withDraft: true));
  }

  @override
  void dispose() {
    _settle?.cancel();
    unawaited(_changes?.cancel());
    // The last state is kept even if the screen closes mid-typing; the store
    // is the app's, not this screen's, and outlives it. So is a conversion
    // made just before Back, which was waiting out its pause.
    unawaited(_saveDraft());
    if (_pending case final entry?) {
      unawaited(
        converterRemember(
          widget.store,
          entry,
          replacing: _keptSubject == _subjectOf(entry) ? _keptId : null,
        ).then((_) {}, onError: (Object _) {}),
      );
    }
    _dateField.dispose();
    _valueField.dispose();
    super.dispose();
  }

  /* ------------------------------------------------------------- records */

  Future<void> _loadHistory({bool withDraft = false}) async {
    final token = ++_token;
    try {
      final recents = await widget.store.list('recent');
      final favorites = await widget.store.list('favorite');
      final draft = withDraft ? await widget.store.get('draft', 'state') : null;
      if (!mounted || token != _token) return;
      final history = converterReadHistory(recents, favorites);
      setState(() {
        _recents = history.recents;
        _favorites = history.favorites;
        _failed = false;
      });
      if (draft != null) _applyDraft(draft);
    } catch (_) {
      if (mounted && token == _token) setState(() => _failed = true);
    }
  }

  Future<void> _saveDraft() async {
    try {
      await widget.store.put('draft', 'state', {
        'v': 1,
        'tab': _tab.name,
        'calendar': _dateCalendar.name,
        'dateText': _dateField.text,
        'category': _category.name,
        'from': _fromId,
        'to': _toId,
        'value': _valueField.text,
        'chart': _chartId,
        'sys': _systemId,
        'row': _sizeRow,
      });
    } catch (_) {
      // A draft that cannot be written must not stop a conversion.
    }
  }

  /// Keeps the draft once the person has stopped changing things for a
  /// moment, and — when [keep] — the conversion as it is now, as a recent one.
  ///
  /// Only what the person actually converted is kept (2.7.1): a date typed or
  /// picked, a number typed, a size chosen. Switching tabs, calendars,
  /// categories or charts is looking around, not converting, and used to
  /// fill Recent with the defaults each of them opens on.
  void _schedule({bool keep = false}) {
    if (keep) _pending = _entryNow();
    _settle?.cancel();
    _settle = Timer(
      const Duration(milliseconds: 1500),
      () => unawaited(_commit()),
    );
  }

  /// The conversion on screen as an entry, or null when there is none.
  ConverterEntry? _entryNow() {
    final outcome = _outcome(context);
    if (outcome == null) return null;
    return ConverterEntry(
      id: '',
      tab: _tab,
      label: outcome.label,
      payload: outcome.payload,
      at: DateTime.now(),
    );
  }

  /// What a conversion is about, for telling a correction from a new one:
  /// any date; the same category of units; the same size chart.
  static String _subjectOf(ConverterEntry entry) => switch (entry.tab) {
    ConverterTab.dates => 'dates',
    ConverterTab.units => 'units:${entry.payload['cat']}',
    ConverterTab.sizes => 'sizes:${entry.payload['chart']}',
  };

  Future<void> _commit({ConverterEntry? now}) async {
    if (!mounted) return;
    await _saveDraft();
    if (!mounted) return;
    final entry = now ?? _pending;
    _pending = null;
    if (entry == null) return;
    final subject = _subjectOf(entry);
    final at = _keptAt;
    final correcting =
        _keptId != null &&
        _keptSubject == subject &&
        at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 45);
    try {
      _keptId = await converterRemember(
        widget.store,
        entry,
        replacing: correcting ? _keptId : null,
      );
      _keptSubject = subject;
      _keptAt = DateTime.now();
    } catch (_) {
      // Out of space or busy: the screen is still the place to convert.
    }
    if (!mounted) return;
    await _loadHistory();
  }

  void _applyDraft(Map<String, Object?> body) {
    final tab = ConverterTab.values.firstWhere(
      (value) => value.name == body['tab'],
      orElse: () => _tab,
    );
    final calendar = _calendarOf(body['calendar'], fallback: _dateCalendar);
    final dateText = body['dateText'];
    final category = _categoryOf(body['category'], fallback: _category);
    final pair = converterDefaultPair(category);
    final chartId = body['chart'];
    final chart = converterSizeChartById(
      chartId is String ? chartId : _chartId,
    );
    final row = _intOf(body['row']);
    final value = body['value'];
    setState(() {
      _tab = tab;
      _dateCalendar = calendar;
      if (dateText is String && dateText.trim().isNotEmpty) {
        _dateField.text = dateText;
        _date = ConverterDate.parse(dateText, calendar);
      }
      _category = category;
      _fromId = _unitIn(category, body['from'], fallback: pair.from);
      _toId = _unitIn(category, body['to'], fallback: pair.to);
      if (value is String) {
        _valueField.text = value;
        // A number that was typed before is still a typed number.
        _unitsTyped = value.trim().isNotEmpty && value.trim() != '1';
      }
      if (chart != null) {
        _chartId = chart.id;
        final system = _systemIn(chart, body['sys']);
        _systemId = system?.id ?? chart.systems.first.id;
        _sizeRow = row != null && row >= 0 && row < chart.rows.length ? row : 0;
      }
    });
  }

  /* ------------------------------------------------------------- answers */

  ConverterOutcome? _outcome(BuildContext context) {
    switch (_tab) {
      case ConverterTab.dates:
        final date = _date;
        return date == null ? null : converterDatesOutcome(context, date);
      case ConverterTab.units:
        return converterUnitsOutcome(
          context,
          category: _category,
          fromId: _fromId,
          toId: _toId,
          rawValue: _valueField.text,
        );
      case ConverterTab.sizes:
        final chart = converterSizeChartById(_chartId);
        if (chart == null) return null;
        final system = _systemIn(chart, _systemId);
        if (system == null) return null;
        return converterSizesOutcome(context, chart, system, _sizeRow);
    }
  }

  /* -------------------------------------------------------------- actions */

  void _selectTab(ConverterTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    // A tab of its own is not a conversion; only the draft follows it.
    unawaited(_saveDraft());
  }

  void _setCalendar(ConverterCalendar calendar) {
    if (calendar == _dateCalendar) return;
    final converted = ConverterDate.of(
      _date?.civilDay ?? DateTime.now(),
      calendar,
    );
    setState(() {
      _dateCalendar = calendar;
      if (converted != null) {
        _date = converted;
        _dateField.text = converterDateNumeric(context, converted);
      }
    });
    _schedule();
  }

  void _dateChanged(String text) {
    setState(() => _date = ConverterDate.parse(text, _dateCalendar));
    _schedule(keep: _date != null);
  }

  void _useToday() {
    final today = ConverterDate.today(_dateCalendar);
    setState(() {
      _date = today;
      _dateField.text = converterDateNumeric(context, today);
    });
    _schedule();
  }

  Future<void> _pickDate() async {
    final picked = await nexPickModuleDate(
      context,
      initial: _date?.civilDay ?? DateTime.now(),
      first: DateTime(converterFirstCivilYear),
      last: DateTime(converterLastCivilYear, 12, 31),
    );
    if (picked == null || !mounted) return;
    final converted = ConverterDate.of(picked, _dateCalendar);
    if (converted == null) return;
    setState(() {
      _date = converted;
      _dateField.text = converterDateNumeric(context, converted);
    });
    _schedule(keep: true);
  }

  void _setCategory(UnitCategory category) {
    if (category == _category) return;
    final pair = converterDefaultPair(category);
    setState(() {
      _category = category;
      _fromId = pair.from;
      _toId = pair.to;
      _unitsTyped = false;
    });
    _schedule();
  }

  void _setFrom(String id) {
    setState(() => _fromId = id);
    _schedule(keep: _unitsTyped);
  }

  void _setTo(String id) {
    setState(() => _toId = id);
    _schedule(keep: _unitsTyped);
  }

  void _swap() {
    setState(() {
      final from = _fromId;
      _fromId = _toId;
      _toId = from;
    });
    _schedule(keep: _unitsTyped);
  }

  void _valueChanged(String text) {
    setState(() => _unitsTyped = text.trim().isNotEmpty);
    _schedule(keep: _unitsTyped);
  }

  void _setChart(String id) {
    final chart = converterSizeChartById(id);
    if (chart == null) return;
    setState(() {
      _chartId = id;
      _systemId = chart.systems.first.id;
      _sizeRow = 0;
    });
    _schedule();
  }

  void _setSystem(String id) {
    setState(() {
      _systemId = id;
      _sizeRow = 0;
    });
    _schedule();
  }

  void _setRow(int index) {
    setState(() => _sizeRow = index);
    _schedule(keep: true);
  }

  Future<void> _copy(String text) async {
    await nexModuleCopyText(text);
    if (!mounted) return;
    nexShowBanner(context, message: converterText(context, 'copied'));
    // Copying is converting, whatever was or was not typed.
    _settle?.cancel();
    unawaited(_commit(now: _entryNow()));
  }

  Future<void> _star(ConverterOutcome outcome, bool star) async {
    await _starEntry(
      ConverterEntry(
        id: '',
        tab: _tab,
        label: outcome.label,
        payload: outcome.payload,
        at: DateTime.now(),
      ),
      star,
    );
  }

  Future<void> _starEntry(ConverterEntry entry, bool star) async {
    try {
      await converterStar(widget.store, entry, star: star);
    } catch (_) {
      // Nothing to tell the person: the star simply did not change.
    }
    await _loadHistory();
  }

  Future<void> _remove(ConverterEntry entry) async {
    // A conversion still waiting to be kept must not put it straight back.
    _settle?.cancel();
    _pending = null;
    if (entry.id == _keptId) _keptId = null;
    try {
      await converterForget(widget.store, entry);
    } catch (_) {
      return;
    }
    await _loadHistory();
    if (!mounted) return;
    nexShowBanner(
      context,
      message: converterText(context, 'deleted'),
      actionLabel: converterText(context, 'undo'),
      onAction: () => unawaited(_putBack(entry)),
    );
  }

  Future<void> _putBack(ConverterEntry entry) async {
    try {
      await converterPutBack(widget.store, entry);
    } catch (_) {
      return;
    }
    await _loadHistory();
  }

  void _restore(ConverterEntry entry) {
    final payload = entry.payload;
    switch (entry.tab) {
      case ConverterTab.dates:
        final calendar = _calendarOf(payload['cal'], fallback: _dateCalendar);
        final year = _intOf(payload['y']);
        final month = _intOf(payload['m']);
        final day = _intOf(payload['d']);
        if (year == null || month == null || day == null) return;
        final date = ConverterDate(calendar, year, month, day);
        if (date.civilDay == null) return;
        setState(() {
          _tab = ConverterTab.dates;
          _dateCalendar = calendar;
          _date = date;
          _dateField.text = converterDateNumeric(context, date);
        });
        break;
      case ConverterTab.units:
        final category = _categoryOf(payload['cat'], fallback: _category);
        final pair = converterDefaultPair(category);
        final from = payload['from'];
        final to = payload['to'];
        if (from is! String || to is! String) return;
        setState(() {
          _tab = ConverterTab.units;
          _category = category;
          _fromId = _unitIn(category, from, fallback: pair.from);
          _toId = _unitIn(category, to, fallback: pair.to);
          if (payload['value'] is String) {
            _valueField.text = payload['value']! as String;
            _unitsTyped = true;
          }
        });
        break;
      case ConverterTab.sizes:
        final chartId = payload['chart'];
        final chart = converterSizeChartById(chartId is String ? chartId : '');
        if (chart == null) return;
        final system = _systemIn(chart, payload['sys']);
        if (system == null) return;
        final row = _intOf(payload['row']);
        setState(() {
          _tab = ConverterTab.sizes;
          _chartId = chart.id;
          _systemId = system.id;
          _sizeRow = row != null && row >= 0 && row < chart.rows.length
              ? row
              : 0;
        });
        break;
    }
    _schedule();
  }

  /* ---------------------------------------------------------------- view */

  @override
  Widget build(BuildContext context) {
    final strings = converterStrings;
    final outcome = _outcome(context);
    final current = outcome == null
        ? null
        : ConverterEntry(
            id: '',
            tab: _tab,
            label: outcome.label,
            payload: outcome.payload,
            at: DateTime.now(),
          );
    final starred = current != null && converterIsFavorite(current, _favorites);
    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'title')),
        actions: [
          if (outcome != null)
            IconButton(
              key: const ValueKey('converter-star'),
              tooltip: strings(context, starred ? 'unfavorite' : 'favorite'),
              onPressed: () => unawaited(_star(outcome, !starred)),
              icon: Icon(
                starred ? Icons.star_rounded : Icons.star_outline_rounded,
              ),
            ),
          IconButton(
            key: const ValueKey('converter-copy'),
            tooltip: strings(context, 'copy'),
            onPressed: outcome == null
                ? null
                : () => unawaited(_copy(outcome.copyText)),
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              NexSpacing.md,
              NexSpacing.sm,
              NexSpacing.md,
              0,
            ),
            child: NexAdaptiveSegments<ConverterTab>(
              segments: [
                for (final tab in ConverterTab.values)
                  ButtonSegment<ConverterTab>(
                    value: tab,
                    label: Text(strings(context, _tabKey(tab))),
                  ),
              ],
              selected: {_tab},
              onSelectionChanged: (choice) {
                if (choice.isNotEmpty) _selectTab(choice.first);
              },
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsetsDirectional.fromSTEB(
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.xl + nexBottomInset(context),
              ),
              children: [
                if (outcome != null) ...[
                  NexModuleHero(
                    key: const ValueKey('converter-hero'),
                    moduleId: 'converter',
                    icon: Icons.swap_horiz_rounded,
                    eyebrow: outcome.eyebrow,
                    headline: outcome.headline,
                    caption: outcome.caption,
                    chips: outcome.chips,
                  ),
                  if (outcome.note != null) ConverterNote(text: outcome.note!),
                  const SizedBox(height: NexSpacing.md),
                ],
                ..._content(context),
                const SizedBox(height: NexSpacing.lg),
                if (_failed)
                  NexEmptyState(
                    icon: Icons.error_outline,
                    message: strings(context, 'loadError'),
                    action: TextButton(
                      onPressed: () => unawaited(_loadHistory()),
                      child: Text(strings(context, 'retry')),
                    ),
                  )
                else
                  ConverterHistory(
                    tab: _tab,
                    recents: _recents,
                    favorites: _favorites,
                    onOpen: _restore,
                    onRemove: (entry) => unawaited(_remove(entry)),
                    onStar: (entry, star) => unawaited(_starEntry(entry, star)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context) => switch (_tab) {
    ConverterTab.dates => [
      ConverterDatesView(
        calendar: _dateCalendar,
        controller: _dateField,
        errorText: _date == null ? converterText(context, 'dateInvalid') : null,
        onCalendar: _setCalendar,
        onChanged: _dateChanged,
        onToday: _useToday,
        onPick: _pickDate,
        onDaysBetween: () => unawaited(
          converterShowDaysBetween(
            context,
            calendar: _dateCalendar,
            initial: _date ?? ConverterDate.today(_dateCalendar),
          ),
        ),
        onAddDays: () => unawaited(
          converterShowAddDays(
            context,
            calendar: _dateCalendar,
            initial: _date ?? ConverterDate.today(_dateCalendar),
          ),
        ),
      ),
    ],
    ConverterTab.units => [
      ConverterUnitsView(
        category: _category,
        fromId: _fromId,
        toId: _toId,
        controller: _valueField,
        errorText:
            converterParseNumber(_valueField.text) == null &&
                _valueField.text.trim().isNotEmpty
            ? converterText(context, 'unitInvalid')
            : null,
        onCategory: _setCategory,
        onFrom: _setFrom,
        onTo: _setTo,
        onSwap: _swap,
        onChanged: _valueChanged,
      ),
    ],
    ConverterTab.sizes => _sizeView(context),
  };

  List<Widget> _sizeView(BuildContext context) {
    final chart = converterSizeChartById(_chartId);
    final system = chart == null ? null : _systemIn(chart, _systemId);
    if (chart == null || system == null) return const [];
    return [
      ConverterSizesView(
        chart: chart,
        system: system,
        rowIndex: _sizeRow,
        onChart: _setChart,
        onSystem: _setSystem,
        onRow: _setRow,
      ),
    ];
  }
}

String _tabKey(ConverterTab tab) => switch (tab) {
  ConverterTab.dates => 'tabDates',
  ConverterTab.units => 'tabUnits',
  ConverterTab.sizes => 'tabSizes',
};

ConverterCalendar _calendarOf(
  Object? value, {
  required ConverterCalendar fallback,
}) {
  for (final calendar in ConverterCalendar.values) {
    if (calendar.name == value) return calendar;
  }
  return fallback;
}

UnitCategory _categoryOf(Object? value, {required UnitCategory fallback}) {
  for (final category in UnitCategory.values) {
    if (category.name == value) return category;
  }
  return fallback;
}

String _unitIn(UnitCategory category, Object? id, {required String fallback}) {
  if (id is! String) return fallback;
  final unit = converterUnitById(id);
  return unit != null && unit.category == category ? unit.id : fallback;
}

SizeSystem? _systemIn(SizeChart chart, Object? id) {
  for (final system in chart.systems) {
    if (system.id == id) return system;
  }
  return null;
}

int? _intOf(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(converterLatinDigits(text)),
  _ => null,
};
