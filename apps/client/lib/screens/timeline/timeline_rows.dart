part of '../timeline_screen.dart';

/// What an arranged home is sorted by, and everything that shapes its
/// shelves (2.7.0) — compared as a whole by [_TimelineRowsCache.assemble].
///
/// [counts] and [tags] are compared by identity: the model replaces each
/// whenever its contents change, as it does the notes.
class _Arrange {
  const _Arrange({
    required this.by,
    required this.counts,
    required this.tags,
    required this.selectedTagIds,
    required this.onlyUntagged,
    required this.filtering,
    required this.order,
  });

  final NexTimelineArrangement by;
  final Map<String, int>? counts;
  final List<Tag> tags;
  final Set<String> selectedTagIds;
  final bool onlyUntagged;
  final bool filtering;
  final List<String> order;

  @override
  bool operator ==(Object other) =>
      other is _Arrange &&
      other.by == by &&
      identical(other.counts, counts) &&
      identical(other.tags, tags) &&
      setEquals(other.selectedTagIds, selectedTagIds) &&
      other.onlyUntagged == onlyUntagged &&
      other.filtering == filtering &&
      listEquals(other.order, order);

  @override
  int get hashCode => Object.hash(by, filtering, onlyUntagged, order.length);
}

/// Caches grouping and stable per-group rows against the notes, view and day.
class _TimelineRowsCache {
  List<Note>? _notes;
  String? _locale;
  String? _dayKey;
  List<_NoteGroup>? _groups;
  _Arrange? _arrange;

  /// What the list is a view of — arrangement and filters — when it was last
  /// asked; see `_fadeOnViewChange`.
  String? view;

  /// Whether the list may load older notes as it nears its end — always by
  /// day; arranged, only while one shelf is the list ([nexShelvesGrow]).
  bool grows = true;

  /// Read by `TimelineScreenState.debugRowBuilds` to verify reuse.
  int builds = 0;

  List<_NoteGroup> assemble(
    BuildContext context, {
    required List<Note> notes,
    required AppLocalizations l10n,
    _Arrange? arrange,
  }) {
    final locale = Localizations.maybeLocaleOf(context)?.toString();
    final dayKey = nexDayKey(DateTime.now());
    if (identical(_notes, notes) &&
        _locale == locale &&
        _dayKey == dayKey &&
        _arrange == arrange) {
      return _groups!;
    }
    _notes = notes;
    _locale = locale;
    _dayKey = dayKey;
    _arrange = arrange;
    builds++;
    return _groups = arrange == null
        ? _groupNotes(notes, l10n)
        : _shelveNotes(notes, arrange, l10n);
  }

  /// The shelves of a home arranged by kind or tag, as groups.
  List<_NoteGroup> _shelveNotes(
    List<Note> notes,
    _Arrange arrange,
    AppLocalizations l10n,
  ) {
    final shelves = nexArrangeShelves(
      notes,
      by: arrange.by,
      counts: arrange.counts,
      tags: arrange.tags,
      selectedTagIds: arrange.selectedTagIds,
      onlyUntagged: arrange.onlyUntagged,
      filtering: arrange.filtering,
      order: arrange.order,
    );
    grows = nexShelvesGrow(shelves);
    final seen = <String>{};
    return [
      for (final shelf in shelves)
        _NoteGroup(
          key: shelf.key,
          label: switch (shelf.kind) {
            NexShelfKind.pinned => l10n.timelineGroupPinned,
            NexShelfKind.type => l10n.timelineShelfType(shelf.type!.wireName),
            NexShelfKind.code => l10n.code,
            // The tag row's own words for a tag — a built-in tag reads in the
            // reader's language there, and must read the same here.
            NexShelfKind.tag =>
              shelf.tag == null ? '' : nexTagLabel(shelf.tag!, l10n),
            NexShelfKind.untagged => l10n.filterUntagged,
          },
          notes: shelf.notes,
          shelf: shelf,
          echoes: {
            for (final note in shelf.notes)
              if (!seen.add(note.id)) note.id,
          },
        ),
    ];
  }

  /// Splits an already-ordered list into date runs.
  ///
  /// Walks the list rather than sorting it: the order is the repository's —
  /// pinned first, then newest — and re-deriving it here would be a second
  /// answer to the same question that could disagree with the first. A group
  /// simply ends where the bucket changes, which only works because the list
  /// arrives ordered, and which is why the pin gets its own group instead of
  /// interrupting whichever day it belongs to.
  List<_NoteGroup> _groupNotes(List<Note> source, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <_NoteGroup>[];
    grows = true;

    for (final note in source) {
      final (key, label) = _bucketFor(note, today, l10n);
      if (groups.isEmpty || groups.last.key != key) {
        groups.add(_NoteGroup(key: key, label: label, notes: [note]));
      } else {
        groups.last.notes.add(note);
      }
    }
    return groups;
  }

  (String, String) _bucketFor(
    Note note,
    DateTime today,
    AppLocalizations l10n,
  ) => _dayBucket(note, today, l10n);

  /// The stable key and the label of the date run a note belongs to.
  ///
  /// Static, because the reveal path (`_revealSpotlight`) asks for a single
  /// note's bucket without assembling the whole list — and because the
  /// grouping that walks the notes is the same rule, kept here so the two
  /// can never drift apart.
  static (String, String) _dayBucket(
    Note note,
    DateTime today,
    AppLocalizations l10n,
  ) {
    // Pinned before dated: a pinned note is held at the top on purpose, and
    // filing it under "Today" would put a heading over one row that then
    // repeats itself two rows later.
    if (note.pinnedAt != null) return ('pinned', l10n.timelineGroupPinned);

    // The same timestamp the list is ordered by. Grouping by createdAt while
    // sorting by updatedAt would scatter a group across the whole list.
    final at = note.updatedAt.toLocal();
    final day = DateTime(at.year, at.month, at.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return ('today', l10n.timelineGroupToday);
    if (days == 1) return ('yesterday', l10n.timelineGroupYesterday);
    if (days <= 7) return ('week', l10n.timelineGroupWeek);
    if (days <= 31) return ('month', l10n.timelineGroupMonth);
    return ('older', l10n.timelineGroupOlder);
  }
}

/// Values read by a timeline card and its wrappers. Returning the same
/// widget while these match lets Flutter skip rebuilding unchanged rows.
class _RowInputs {
  const _RowInputs({
    required this.note,
    required this.l10n,
    required this.label,
    required this.expanded,
    required this.selected,
    required this.ringing,
    required this.anchored,
    required this.spotlighted,
    required this.landed,
    required this.density,
    required this.haptics,
    required this.leading,
    required this.trailing,
    required this.age,
    required this.dueLabel,
    required this.clock24h,
  });

  final Note note;
  final AppLocalizations l10n;
  final String label;
  final bool expanded;
  final bool? selected;
  final bool ringing;
  final bool anchored;
  final bool spotlighted;
  final bool landed;
  final NexCardDensity density;
  final bool haptics;
  final SwipeAction leading;
  final SwipeAction trailing;
  final (NexRelativeUnit, int) age;
  final String? dueLabel;
  final bool clock24h;

  bool matches(_RowInputs other) =>
      nexSameNote(note, other.note) &&
      identical(l10n, other.l10n) &&
      label == other.label &&
      expanded == other.expanded &&
      selected == other.selected &&
      ringing == other.ringing &&
      anchored == other.anchored &&
      spotlighted == other.spotlighted &&
      landed == other.landed &&
      density == other.density &&
      haptics == other.haptics &&
      leading == other.leading &&
      trailing == other.trailing &&
      age == other.age &&
      dueLabel == other.dueLabel &&
      clock24h == other.clock24h;
}

/// Each shelf has its own row even when another shelf shows the same note.
class _RowWidgetCache {
  static const _capacity = 600;

  final _entries = <(bool, String, String), (_RowInputs, Widget)>{};

  /// Read by timeline performance tests.
  int hits = 0;

  Widget row(
    (bool, String, String) key,
    _RowInputs inputs,
    Widget Function(String label) build,
  ) {
    final cached = _entries.remove(key);
    if (cached != null && cached.$1.matches(inputs)) {
      hits++;
      _entries[key] = cached;
      return cached.$2;
    }
    if (_entries.length == _capacity) _entries.remove(_entries.keys.first);
    final widget = build(inputs.label);
    _entries[key] = (inputs, widget);
    return widget;
  }
}

/// Working the flattened rows out of the notes the stream delivered.
extension _TimelineRows on TimelineScreenState {
  /// The date run a note belongs to — see `_TimelineRowsCache._dayBucket`.
  (String, String) _bucketFor(
    Note note,
    DateTime today,
    AppLocalizations l10n,
  ) => _TimelineRowsCache._dayBucket(note, today, l10n);

  /// What the model's last notification does to the screen.
  ///
  /// Only notes and folds move the cards. A tags or commitments change is the
  /// filter row's and the brief card's business — they listen to the model
  /// themselves — so the second notification after a delivery (the tag row
  /// refreshing) no longer rebuilds every card on screen with it.
  void _onModelChange() {
    if (!mounted) return;
    final kind = _model.lastChange;
    if (kind == TimelineChange.folds) {
      _groupFoldPulse.value++;
      return;
    }
    if (kind == TimelineChange.notes) _fadeOnViewChange();
    // The first notes of a launch arrive the way a search's results do —
    // eased in over the placeholders they replace, once — rather than being
    // there on one frame where grey bars were on the last.
    if (!_firstNotesShown && _model.all != null) {
      _firstNotesShown = true;
      _fadeInBody();
      _startLinkArt();
    }
    // Links saved without their picture ask for it once (2.8.3).
    if (kind == TimelineChange.notes) {
      NexLinkArt.instance.fillIn(_model.all ?? const []);
    }
    // By tag, the tags are the headings: a renamed or new tag is a change to
    // the rows, not just to the filter row.
    final tagShelves =
        widget.preferences.timelineArrangement == NexTimelineArrangement.tag;
    if ((kind != TimelineChange.tags || tagShelves) &&
        kind != TimelineChange.commitments) {
      _rebuild(() {});
      if (kind == TimelineChange.notes) {
        // Rows replaced under a list that is already scrolled: the sticky day
        // names whichever card is passing under the filter row, and it is
        // stale until a scroll moves again.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateStickyDay();
        });
      }
    }
    if (_model.all?.isEmpty ?? false) unawaited(_countSetAside());
    // Commitments and notes can arrive independently of the timeline stream.
    // A tag or shelf-count refresh cannot change what the brief says, and the
    // pass reads the waiting notes, the habits and the whole library before it
    // can decide nothing moved; it is not spent on a change that never
    // reaches its source.
    if (kind == TimelineChange.notes || kind == TimelineChange.commitments) {
      unawaited(_loadAiSummary());
    }
  }

  /// Link pictures: what is on disk known before the first tile, words a
  /// later fetch finds saved on their note, and the pictures of notes that
  /// are gone let go of (2.8.3).
  void _startLinkArt() {
    final art = NexLinkArt.instance;
    art.onPageWords = (id, title, excerpt) async {
      // Found later, in the background: not an edit, so the link keeps its
      // place in the timeline (2.8.4).
      await widget.services.setLinkMetadata(
        id,
        title: title,
        excerpt: excerpt,
        keepTime: true,
      );
      if (mounted) await widget.services.refreshTimeline();
    };
    unawaited(() async {
      await art.open();
      if (!mounted) return;
      art.fillIn(_model.all ?? const []);
      await art.sweep(widget.services.existingNoteIds);
    }());
  }
}
