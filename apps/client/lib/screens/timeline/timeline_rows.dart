part of '../timeline_screen.dart';

/// The timeline's flattened rows, built once per change rather than once per
/// rebuild (T-01).
///
/// Grouping and row assembly walked the whole window on *every* build of the
/// screen — a per-note `DateTime` allocation, a fresh wrapper per note, and
/// the whole list handed to `SliverAnimatedList`'s differ — for a screen that
/// rebuilds far more often than its notes move: a selection toggle, a recap
/// landing, a sponsor pulse, a ringing change. This holds the answer keyed on
/// the only inputs that can change it, and hands the same list back until one
/// of them does.
///
/// Identity is the whole contract: the same list instance flows into
/// `_TimelineList`, whose `didUpdateWidget` then skips its diff entirely, so
/// an unrelated rebuild costs neither the walk nor the wrappers nor the
/// longest-increasing-subsequence pass over notes that were never touched.
class _TimelineRowsCache {
  /// The last computation's inputs and answer, all of it replaced together.
  List<Note>? _notes;
  String? _locale;
  String? _dayKey;
  List<String>? _collapsed;
  List<String>? _closing;
  List<_NoteGroup>? _groups;
  List<_TimelineRow>? _rows;

  /// How many times the rows have actually been assembled. A test reads it
  /// through `TimelineScreenState.debugRowBuilds` to prove that a change
  /// which moves no note reuses what is on screen.
  int builds = 0;

  /// The groups and rows for [notes], reusing the last answer when nothing
  /// that shapes them has moved.
  ///
  /// - [notes] by identity: the model replaces the list whenever its contents
  ///   change, so a same-instance list is a same-contents list;
  /// - [collapsed] and [closing] by content: a fold flips them one group at a
  ///   time, and they are never more than the six day keys plus `pinned`;
  /// - the locale, because the headings are words;
  /// - the local day, because "Today" is a place notes fall out of at
  ///   midnight without any write — see [_bucketFor].
  ///
  /// [opening] is not an input: it changes only how a row *animates in when
  /// the rows are already changing*, never which rows there are — see
  /// `_openingGroups`.
  (List<_NoteGroup>, List<_TimelineRow>) assemble(
    BuildContext context, {
    required List<Note> notes,
    required Set<String> collapsed,
    required Set<String> closing,
    required AppLocalizations l10n,
  }) {
    final locale = Localizations.maybeLocaleOf(context)?.toString();
    final dayKey = nexDayKey(DateTime.now());
    if (_notes != null &&
        identical(_notes, notes) &&
        _locale == locale &&
        _dayKey == dayKey &&
        _sameKeyList(_collapsed, collapsed) &&
        _sameKeyList(_closing, closing)) {
      return (_groups!, _rows!);
    }
    _notes = notes;
    _locale = locale;
    _dayKey = dayKey;
    _collapsed = List.of(collapsed);
    _closing = List.of(closing);
    final groups = _groupNotes(notes, l10n);
    final rows = <_TimelineRow>[
      for (final group in groups) ...[
        _TimelineRow.header(group),
        // A closing group keeps its rows for one animation. Without that the
        // fold was a jump cut: the rows were simply gone on the next frame,
        // which is the report this fixes. See `_toggleGroup`.
        if (!collapsed.contains(group.key) || closing.contains(group.key))
          for (final (i, note) in group.notes.indexed)
            _TimelineRow.note(note, group.key, i),
      ],
    ];
    _groups = groups;
    _rows = rows;
    builds++;
    return (groups, rows);
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

  /// Set equality over the day keys, which are few and cheap to compare.
  static bool _sameKeyList(List<String>? before, Set<String> after) {
    if (before == null || before.length != after.length) return false;
    for (final key in before) {
      if (!after.contains(key)) return false;
    }
    return true;
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
    if (kind != TimelineChange.tags && kind != TimelineChange.commitments) {
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
    unawaited(_loadAiSummary());
  }
}
