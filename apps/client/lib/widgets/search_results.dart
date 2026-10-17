import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/note_search.dart';
import 'card_strings.dart';
import 'search_field_header.dart' show nexSearchTapGroup;

/// Search results as slivers, so they can replace the timeline's cards inside
/// the timeline's own scroll view rather than on a screen of their own.
///
/// Returning slivers rather than a widget is the whole reason search no longer
/// needs a route: the query field stays pinned where it was typed into, and the
/// list under it simply becomes the answer.
List<Widget> searchResultSlivers({
  required BuildContext context,
  required NoteSearchController search,
  required ValueChanged<Note> onOpen,
  NexPreferences? preferences,
  ValueChanged<String>? onUseSaved,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);

  if (search.query.text.trim().isEmpty && search.activeFilterCount == 0) {
    final saved = preferences?.savedSearches ?? const <String>[];
    // What was searched lately, but not what is kept already: one chip for
    // one search, under the heading where it is easiest to find again.
    final recent = [
      for (final query in preferences?.recentSearches ?? const <String>[])
        if (!saved.contains(query)) query,
    ];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.searchStart, style: theme.textTheme.bodyMedium),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.recentSearches,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('recent-searches-clear'),
                      tooltip: l10n.clearRecentSearches,
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: () =>
                          unawaited(preferences!.clearRecentSearches()),
                      icon: const Icon(Icons.clear_all),
                    ),
                  ],
                ),
                const SizedBox(height: NexSpacing.xs),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final query in recent)
                      ActionChip(
                        key: ValueKey('recent-search-$query'),
                        avatar: const Icon(Icons.history, size: 16),
                        label: Text(
                          query,
                          textDirection: nexDirectionOf(query),
                        ),
                        onPressed: () => onUseSaved?.call(query),
                      ),
                  ],
                ),
              ],
              // Kept searches live here rather than behind a menu: the empty
              // search screen is the one moment they are useful, and it is
              // otherwise a screen with a sentence on it.
              if (saved.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.lg),
                Text(l10n.savedSearches, style: theme.textTheme.titleSmall),
                const SizedBox(height: NexSpacing.sm),
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    for (final query in saved)
                      InputChip(
                        label: Text(query),
                        onPressed: () => onUseSaved?.call(query),
                        onDeleted: () =>
                            unawaited(preferences!.removeSavedSearch(query)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  /// Offered above the results, and only when there is something to keep that
  /// is not kept already — a button that saves what is already saved is a
  /// button that teaches people it does nothing.
  Widget? saveAction() {
    final query = search.query.text.trim();
    if (preferences == null || query.isEmpty) return null;
    if (preferences.savedSearches.contains(query)) return null;
    return SliverToBoxAdapter(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
          child: TextButton.icon(
            onPressed: () => unawaited(preferences.saveSearch(query)),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(l10n.saveSearch),
          ),
        ),
      ),
    );
  }

  // Before "no results": a search that threw found nothing in the sense that
  // matters here, and saying "nothing matches" would blame the query for the
  // database's problem.
  if (search.failure != null) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.searchFailed, style: theme.textTheme.bodyMedium),
              const SizedBox(height: NexSpacing.sm),
              // The one thing worth offering. A search is cheap and the
              // failure may not repeat, so the way out is to ask again rather
              // than to leave search altogether — which was the only way out
              // before.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => unawaited(search.run()),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.retry),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  if (!search.hasRun) {
    return [
      SliverList.builder(
        itemCount: 3,
        itemBuilder: (_, __) => const NexCardSkeleton(),
      ),
    ];
  }

  if (search.results.isEmpty) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.nothingMatches(search.query.text),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: NexSpacing.lg),
              // The nearest miss is the point of this state: an empty result
              // that shows the closest thing you actually wrote is a different
              // experience from one that says "no results".
              if (search.nearest != null) ...[
                Text(l10n.closestThing, style: theme.textTheme.bodySmall),
                const SizedBox(height: NexSpacing.sm),
              ] else
                Text(l10n.nothingClose, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
      if (search.nearest != null)
        SliverToBoxAdapter(
          child: TapRegion(
            groupId: nexSearchTapGroup,
            child: NoteCard(
              note: search.nearest!,
              strings: nexCardStrings(context),
              onTap: () => onOpen(search.nearest!),
            ),
          ),
        ),
    ];
  }

  return [
    if (saveAction() case final action?) action,
    if (search.narrowed)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.sm,
          ),
          child: Text(
            l10n.resultCount(search.results.length),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
    SliverList.builder(
      itemCount: search.results.length,
      // A result that stays in the list as the query grows keeps its place
      // and its state, rather than playing its entrance again.
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final at = search.results.indexWhere((n) => n.id == key.value);
        return at < 0 ? null : at;
      },
      itemBuilder: (context, index) {
        final note = search.results[index];
        final card = NoteCard(
          note: note,
          strings: nexCardStrings(context),
          onTap: () => onOpen(note),
        );
        final result = TapRegion(
          groupId: nexSearchTapGroup,
          // Ranked in with the rest (W2.2), and marked: a note that shares
          // no word with the query needs a reason to be in the list.
          child: search.meaningOnly.contains(note.id)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        NexSpacing.lg,
                        NexSpacing.xs,
                        NexSpacing.lg,
                        0,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: NexSpacing.xs),
                          Text(
                            l10n.searchByMeaning,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    card,
                  ],
                )
              : card,
        );
        return _Arrive(key: ValueKey(note.id), index: index, child: result);
      },
    ),
    if (search.hasMore)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.md),
          child: Column(
            children: [
              if (search.pageFailed)
                Text(l10n.searchFailed, style: theme.textTheme.bodySmall),
              TextButton.icon(
                onPressed: search.loadingMore
                    ? null
                    : () => unawaited(search.loadMore()),
                icon: search.loadingMore
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(search.pageFailed ? l10n.retry : l10n.searchMore),
              ),
            ],
          ),
        ),
      ),
  ];
}

/// A result easing into the list: it fades in and rises a little, a beat
/// after the one above it, the first time it is shown — so opening search
/// reads as the results arriving, not as one list swapped for another.
/// Still when animations are off.
class _Arrive extends StatefulWidget {
  const _Arrive({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<_Arrive> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: NexMotion.enter,
  );
  Timer? _wait;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _in.value = 1;
      return;
    }
    // A short cascade down the first screenful; past it, at once.
    final delay = NexMotion.fast ~/ 3 * widget.index.clamp(0, 8);
    if (delay == Duration.zero) {
      unawaited(_in.forward());
    } else {
      _wait = Timer(delay, () {
        if (mounted) unawaited(_in.forward());
      });
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _in,
    builder: (context, child) {
      final t = NexMotion.curve.transform(_in.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}
