/// Word by Word's home: the review panel (what is due now, what is new
/// today, and the honest «nothing to review»), the search and filters,
/// and the person's words. One primary action: adding a word.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_batch_sheet.dart';
import 'words_card_page.dart';
import 'words_card_row.dart';
import 'words_daily_cap.dart';
import 'words_models.dart';
import 'words_reminder.dart';
import 'words_review_page.dart';
import 'words_scheduler.dart';
import 'words_store.dart';
import 'words_strings.dart';
import 'words_visuals.dart';
part 'words_home_logic.dart';

enum _StatusFilter { all, newWords, due, learned, paused }

class WordsScreen extends StatefulWidget {
  const WordsScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen>
    with WidgetsBindingObserver, _WordsHomeLogic {
  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    final visible = _visible;
    final due = _dueCount;
    final fresh = _newToday;

    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'title')),
        actions: [
          IconButton(
            key: const ValueKey('words-copy-list'),
            tooltip: strings(context, 'copyListTip'),
            onPressed: visible.isEmpty ? null : () => unawaited(_copyList()),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            key: const ValueKey('words-batch'),
            tooltip: strings(context, 'batchEntryTip'),
            onPressed: () => unawaited(
              showWordsBatchSheet(context, _repository, onDone: _reload),
            ),
            icon: const Icon(Icons.content_paste_outlined),
          ),
        ],
      ),
      // One primary action per page: with nothing yet it is the button in
      // the empty state, not a second one floating beside it.
      floatingActionButton: _loading || _failed || _cards.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('words-add'),
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  NexPageRoute<void>(
                    builder: (_) => WordsCardPage(store: widget.store),
                  ),
                ),
              ),
              label: Text(strings(context, 'addWord')),
              icon: const Icon(Icons.add),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? NexEmptyState(
              icon: Icons.cloud_off_outlined,
              message: strings(context, 'loadError'),
              action: TextButton(
                onPressed: () => unawaited(_reload()),
                child: Text(strings(context, 'retry')),
              ),
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
                children: [
                  const SizedBox(height: NexSpacing.md),
                  // Nothing yet: no hero — only the empty state's own button.
                  if (_cards.isNotEmpty) ...[
                    _reviewPanel(context, due, fresh),
                    const SizedBox(height: NexSpacing.md),
                  ],
                  _searchAndFilters(context, theme),
                  if (_cards.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: NexSpacing.xl),
                      child: NexEmptyState(
                        icon: Icons.translate_outlined,
                        message: strings(context, 'emptyWords'),
                        // The empty state carries its own first action, not
                        // only the floating button below the fold.
                        action: FilledButton.tonalIcon(
                          key: const ValueKey('words-empty-add'),
                          onPressed: () => unawaited(
                            Navigator.of(context).push(
                              NexPageRoute<void>(
                                builder: (_) =>
                                    WordsCardPage(store: widget.store),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.add),
                          label: Text(strings(context, 'addWord')),
                          // Material caps buttons at 40dp tall — a label a
                          // 2× text scale cannot fit into; let it grow with
                          // the words instead of clipping them.
                          style: const ButtonStyle(
                            maximumSize: WidgetStatePropertyAll<Size?>(
                              Size(double.infinity, double.infinity),
                            ),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    for (final card in visible)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          bottom: NexSpacing.sm,
                        ),
                        child: WordsCardRow(
                          card: card,
                          todayIso: _todayIso,
                          onTap: () => unawaited(
                            Navigator.of(context).push(
                              NexPageRoute<void>(
                                builder: (_) => WordsCardPage(
                                  store: widget.store,
                                  card: card,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(NexSpacing.lg),
                        child: Text(
                          // Some filter or search emptied the list — not
                          // the day's schedule.
                          strings(context, 'noMatches'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: NexSpacing.xl * 2),
                ],
              ),
            ),
    );
  }

  Widget _reviewPanel(BuildContext context, int due, int fresh) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    final waiting = due + fresh;
    const white = Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WordsDeckCard(
          key: const ValueKey('words-hero'),
          cards: _cards,
          headline: nexDigits(
            waiting > 0
                ? strings(context, 'heroWaiting', {'count': waiting})
                : strings(context, 'heroDone'),
            persian: NexModuleStrings.persian(context),
          ),
          caption:
              '${strings(context, 'dueNowCount', {'count': due})} · '
              '${strings(context, 'newTodayCount', {'count': fresh})}',
          action: waiting > 0
              ? FilledButton.icon(
                  key: const ValueKey('words-start-review'),
                  style: FilledButton.styleFrom(
                    backgroundColor: white,
                    foregroundColor: wordsDeckFrom,
                  ),
                  onPressed: () => unawaited(
                    Navigator.of(context).push(
                      NexPageRoute<void>(
                        builder: (_) => WordsReviewPage(store: widget.store),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(strings(context, 'startReview')),
                )
              : Text(
                  strings(context, 'nothingToReview'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: white.withValues(alpha: 0.9),
                  ),
                ),
          settings: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('words-review-settings'),
              style: TextButton.styleFrom(foregroundColor: white),
              onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
              icon: Icon(
                _settingsOpen ? Icons.expand_less : Icons.tune_outlined,
              ),
              label: Text(strings(context, 'reviewSettings')),
            ),
          ),
        ),
        if (_settingsOpen) ...[
          const SizedBox(height: NexSpacing.sm),
          NexPanel(
            child: Column(
              children: [
                WordsDailyCapRow(settings: _settings, repository: _repository),
                WordsDailyCapRow(
                  settings: _settings,
                  repository: _repository,
                  session: true,
                ),
                const Divider(),
                WordsReminderRow(store: widget.store),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _searchAndFilters(BuildContext context, ThemeData theme) {
    final strings = wordsStrings;
    final tags =
        _cards
            .map((card) => card.tag)
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NexSearchField(
          fieldKey: const ValueKey('words-search'),
          controller: _search,
          hintText: strings(context, 'searchHint'),
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: NexSpacing.sm),
        // One row that scrolls sideways, statuses then tags: two wrapped
        // rows of chips used to break apart at odd places (2.4.0).
        SingleChildScrollView(
          key: const ValueKey('words-filters'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in [
                (_StatusFilter.all, 'filterAll'),
                (_StatusFilter.newWords, 'filterNew'),
                (_StatusFilter.due, 'filterDue'),
                (_StatusFilter.learned, 'filterLearned'),
                (_StatusFilter.paused, 'filterPaused'),
              ]) ...[
                ChoiceChip(
                  key: ValueKey('words-filter-${entry.$2}'),
                  label: Text(strings(context, entry.$2)),
                  selected: _filter == entry.$1,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = entry.$1),
                ),
                const SizedBox(width: NexSpacing.xs + 2),
              ],
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.xs,
                  ),
                  child: SizedBox(
                    height: 24,
                    child: VerticalDivider(
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
              for (final tag in _showAllTags ? tags : tags.take(8)) ...[
                const SizedBox(width: NexSpacing.xs + 2),
                FilterChip(
                  avatar: const Icon(Icons.sell_outlined, size: 16),
                  label: Text(tag),
                  selected: _tagFilter == tag,
                  showCheckmark: false,
                  onSelected: (_) => setState(
                    () => _tagFilter = _tagFilter == tag ? null : tag,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (tags.length > 8)
          TextButton(
            onPressed: () => setState(() => _showAllTags = !_showAllTags),
            child: Text(
              strings(context, _showAllTags ? 'tagsLess' : 'tagsAll', {
                'count': tags.length,
              }),
            ),
          ),
        if (_tagFilter != null ||
            _filter != _StatusFilter.all ||
            _query.isNotEmpty)
          TextButton(
            key: const ValueKey('words-clear-filters'),
            onPressed: () {
              _search.clear();
              setState(() {
                _tagFilter = null;
                _filter = _StatusFilter.all;
                _query = '';
              });
            },
            child: Text(strings(context, 'clearFilters')),
          ),
        const SizedBox(height: NexSpacing.md),
      ],
    );
  }
}
