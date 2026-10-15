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
import 'words_review_page.dart';
import 'words_scheduler.dart';
import 'words_store.dart';
import 'words_strings.dart';
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
            key: const ValueKey('words-batch'),
            tooltip: strings(context, 'batchEntryTip'),
            onPressed: () => unawaited(
              showWordsBatchSheet(context, _repository, onDone: _reload),
            ),
            icon: const Icon(Icons.content_paste_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
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
                  _reviewPanel(context, due, fresh),
                  const SizedBox(height: NexSpacing.md),
                  _searchAndFilters(context, theme),
                  if (_cards.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: NexSpacing.xl),
                      child: NexEmptyState(
                        icon: Icons.translate_outlined,
                        message: strings(context, 'emptyWords'),
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
                          strings(context, 'nothingToReview'),
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
    return NexPanel(
      title: strings(context, 'collection'),
      icon: Icons.translate_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Text(
                  '${strings(context, 'dueNowCount', {'count': due})} · '
                  '${strings(context, 'newTodayCount', {'count': fresh})}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          if (waiting > 0)
            FilledButton.tonalIcon(
              key: const ValueKey('words-start-review'),
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  NexPageRoute<void>(
                    builder: (_) => WordsReviewPage(store: widget.store),
                  ),
                ),
              ),
              icon: const Icon(Icons.play_arrow_outlined),
              label: Text(strings(context, 'startReview')),
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
              child: Text(
                strings(context, 'nothingToReview'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: NexSpacing.sm),
          TextButton.icon(
            key: const ValueKey('words-review-settings'),
            onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
            icon: Icon(_settingsOpen ? Icons.expand_less : Icons.tune_outlined),
            label: Text(strings(context, 'reviewSettings')),
          ),
          if (_settingsOpen) ...[
            WordsDailyCapRow(settings: _settings, repository: _repository),
            WordsDailyCapRow(
              settings: _settings,
              repository: _repository,
              session: true,
            ),
          ],
        ],
      ),
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
        NexAutoDirection(
          controller: _search,
          builder: (context, _) => TextField(
            key: const ValueKey('words-search'),
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: strings(context, 'searchHint'),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: AppLocalizations.of(context).cancel,
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Wrap(
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.xs,
          children: [
            for (final entry in [
              (_StatusFilter.all, 'filterAll'),
              (_StatusFilter.newWords, 'filterNew'),
              (_StatusFilter.due, 'filterDue'),
              (_StatusFilter.learned, 'filterLearned'),
              (_StatusFilter.paused, 'filterPaused'),
            ])
              ChoiceChip(
                key: ValueKey('words-filter-${entry.$2}'),
                label: Text(strings(context, entry.$2)),
                selected: _filter == entry.$1,
                onSelected: (_) => setState(() => _filter = entry.$1),
              ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: NexSpacing.xs),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            children: [
              for (final tag in _showAllTags ? tags : tags.take(8))
                FilterChip(
                  label: Text(tag),
                  selected: _tagFilter == tag,
                  onSelected: (_) => setState(
                    () => _tagFilter = _tagFilter == tag ? null : tag,
                  ),
                ),
            ],
          ),
        ],
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
