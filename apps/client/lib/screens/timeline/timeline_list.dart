part of '../timeline_screen.dart';

/// Keeps the sliver lazy. Only changed rows move; ordinary rebuilds and
/// scrolling do not restart entrances or create a second copy of the list.
class _TimelineList extends StatefulWidget {
  const _TimelineList({
    required this.rows,
    required this.revision,
    required this.builder,
    required this.removedBuilder,
  });

  final List<_TimelineRow> rows;
  // Folding already animates its own rows. It does not change this snapshot.
  final List<Note> revision;
  final Widget Function(BuildContext, _TimelineRow, int) builder;
  final Widget Function(BuildContext, _TimelineRow) removedBuilder;

  @override
  State<_TimelineList> createState() => _TimelineListState();
}

class _TimelineListState extends State<_TimelineList> {
  final _list = GlobalKey<SliverAnimatedListState>();
  late List<_TimelineRow> _rows = List.of(widget.rows);
  final _mountedRows = <String, int>{};
  late Map<String, int> _indices = _indexRows();
  Map<String, int> _indexRows() => {
    for (var i = 0; i < _rows.length; i++) _rows[i].key: i,
  };

  void _track(String key, int delta) {
    final count = (_mountedRows[key] ?? 0) + delta;
    if (count <= 0) {
      _mountedRows.remove(key);
    } else {
      _mountedRows[key] = count;
    }
  }

  @override
  void didUpdateWidget(_TimelineList old) {
    super.didUpdateWidget(old);
    final list = _list.currentState;
    if (list == null) {
      _rows = List.of(widget.rows);
      _indices = _indexRows();
      return;
    }
    final animate =
        !identical(old.revision, widget.revision) &&
        !MediaQuery.disableAnimationsOf(context);
    final next = {
      for (var i = 0; i < widget.rows.length; i++) widget.rows[i].key: i,
    };
    final stable = _stableKeys(next);
    // Limit entrances to a viewport-sized neighbourhood, even when a filter
    // changes hundreds of rows. Unbuilt departures have zero duration too.
    final firstBuilt = _rows.indexWhere(
      (row) => _mountedRows.containsKey(row.key),
    );
    final first = math.min(
      math.max(0, firstBuilt),
      math.max(0, widget.rows.length - 1),
    );
    for (var i = _rows.length - 1; i >= 0; i--) {
      final row = _rows[i];
      if (stable.contains(row.key)) continue;
      final visible = animate && _mountedRows.containsKey(row.key);
      list.removeItem(
        i,
        (context, animation) => ExcludeSemantics(
          child: IgnorePointer(
            child: _transition(
              animation,
              widget.removedBuilder(context, row),
              leaving: true,
            ),
          ),
        ),
        duration: visible ? NexMotion.exit : Duration.zero,
      );
    }
    for (var i = 0; i < widget.rows.length; i++) {
      final row = widget.rows[i];
      if (!stable.contains(row.key)) {
        list.insertItem(
          i,
          duration: animate && i >= first && i < first + 24
              ? NexMotion.enter
              : Duration.zero,
        );
      }
    }
    // Sliver mutations schedule the next build. Replace the data snapshot
    // once, avoiding a list splice for every filtered or reordered row.
    _rows = List.of(widget.rows);
    _indices = _indexRows();
  }

  /// Longest increasing subsequence in O(n log n): keep the largest set of
  /// unchanged rows in place, including their swipe, fold and selection state.
  Set<String> _stableKeys(Map<String, int> next) {
    final keys = [
      for (final row in _rows)
        if (next.containsKey(row.key)) row.key,
    ];
    final tails = <int>[];
    final previous = List.filled(keys.length, -1);
    for (var i = 0; i < keys.length; i++) {
      var lo = 0;
      var hi = tails.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (next[keys[tails[mid]]]! < next[keys[i]]!) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo > 0) previous[i] = tails[lo - 1];
      if (lo == tails.length) {
        tails.add(i);
      } else {
        tails[lo] = i;
      }
    }
    final stable = <String>{};
    for (var i = tails.isEmpty ? -1 : tails.last; i >= 0; i = previous[i]) {
      stable.add(keys[i]);
    }
    return stable;
  }

  Widget _transition(
    Animation<double> animation,
    Widget child, {
    bool leaving = false,
  }) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return leaving ? const SizedBox.shrink() : child;
    }
    final eased = animation.drive(
      CurveTween(curve: leaving ? NexMotion.exitCurve : NexMotion.curve),
    );
    return SizeTransition(
      sizeFactor: eased,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: eased.drive(
            Tween(
              begin: Offset(leaving ? -0.025 : 0, leaving ? 0 : 0.035),
              end: Offset.zero,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SliverAnimatedList(
    key: _list,
    initialItemCount: _rows.length,
    findChildIndexCallback: (key) =>
        key is ValueKey<String> ? _indices[key.value] : null,
    itemBuilder: (context, index, animation) {
      final row = _rows[index];
      return _LiveTimelineRow(
        key: ValueKey(row.key),
        onMount: () => _track(row.key, 1),
        onUnmount: () => _track(row.key, -1),
        child: _transition(animation, widget.builder(context, row, index)),
      );
    },
  );
}

class _LiveTimelineRow extends StatefulWidget {
  const _LiveTimelineRow({
    super.key,
    required this.onMount,
    required this.onUnmount,
    required this.child,
  });
  final VoidCallback onMount;
  final VoidCallback onUnmount;
  final Widget child;

  @override
  State<_LiveTimelineRow> createState() => _LiveTimelineRowState();
}

class _LiveTimelineRowState extends State<_LiveTimelineRow> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onUnmount();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
