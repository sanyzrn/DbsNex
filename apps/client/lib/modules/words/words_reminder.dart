/// The review reminder (2.4.0): one notification at the time the person
/// chose, on the next day there are words to review — never on a day with
/// nothing waiting. Off until it is turned on.
///
/// A module reminder rings once, so this one is moved forward whenever Nex
/// starts or returns (the module's `keepUp`), whenever the home page loads,
/// and when the setting changes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';
import 'words_scheduler.dart';
import 'words_store.dart';
import 'words_strings.dart';

const _reminderId = 'reminder';
const _reminderKey = 'words:review';
const wordsReminderDefaultMinutes = 20 * 60;

/// Whether the reminder is on, and its time of day in minutes.
typedef WordsReminder = ({bool on, int minutes});

Future<WordsReminder> wordsReadReminder(NexModuleStore store) async {
  final body = await store.get(WordsRepository.settingsKind, _reminderId);
  final minutes = body?['minutes'];
  return (
    on: body?['on'] == true,
    minutes: minutes is int && minutes >= 0 && minutes < 1440
        ? minutes
        : wordsReminderDefaultMinutes,
  );
}

/// How many cards are waiting on [day]: due on or before it, plus the new
/// ones a session may introduce.
int wordsWaitingOn(List<WordCard> cards, DateTime day, int newPerDay) {
  final iso = isoDay(day);
  var due = 0;
  var fresh = 0;
  for (final card in cards) {
    if (card.paused) continue;
    if (card.isNew) {
      fresh++;
    } else if (card.due.isNotEmpty && card.due.compareTo(iso) <= 0) {
      due++;
    }
  }
  return due + (newPerDay == 0 ? fresh : fresh.clamp(0, newPerDay));
}

/// When the reminder should next ring, and for how many cards; null when
/// nothing is waiting in the next two months.
({DateTime at, int count})? wordsNextReminder(
  List<WordCard> cards, {
  required int minutes,
  required int newPerDay,
  required DateTime now,
}) {
  for (var ahead = 0; ahead <= 60; ahead++) {
    final day = DateTime(now.year, now.month, now.day + ahead);
    final at = DateTime(
      day.year,
      day.month,
      day.day,
      minutes ~/ 60,
      minutes % 60,
    );
    if (!at.isAfter(now)) continue;
    final count = wordsWaitingOn(cards, day, newPerDay);
    if (count > 0) return (at: at, count: count);
  }
  return null;
}

/// Sets the reminder for its next day, or clears it. False when it should
/// ring and could not be set.
Future<bool> wordsArmReminder(
  NexModuleStore store,
  AppLocalizations l10n, {
  DateTime? now,
  bool preserveShown = false,
}) async {
  final reminder = await wordsReadReminder(store);
  if (!reminder.on) {
    await (preserveShown
        ? store.withdrawReminder(_reminderKey)
        : store.clearReminder(_reminderKey));
    return true;
  }
  final repository = WordsRepository(store);
  final cards = await repository.loadCards();
  final settings = await repository.loadSettings();
  final next = wordsNextReminder(
    cards,
    minutes: reminder.minutes,
    newPerDay: settings.newPerDay,
    now: now ?? DateTime.now(),
  );
  if (next == null) {
    await (preserveShown
        ? store.withdrawReminder(_reminderKey)
        : store.clearReminder(_reminderKey));
    return true;
  }
  return store.setReminder(
    _reminderKey,
    sourceKind: WordsRepository.settingsKind,
    sourceId: _reminderId,
    at: next.at,
    title: wordsStrings.text(l10n, 'title'),
    body: wordsStrings.text(l10n, 'remindBody', {'count': next.count}),
  );
}

/// The reminder's switch and time, in the review settings.
class WordsReminderRow extends StatefulWidget {
  const WordsReminderRow({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<WordsReminderRow> createState() => _WordsReminderRowState();
}

class _WordsReminderRowState extends State<WordsReminderRow> {
  WordsReminder? _reminder;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final reminder = await wordsReadReminder(widget.store);
    if (mounted) setState(() => _reminder = reminder);
  }

  Future<void> _save({bool? on, int? minutes}) async {
    final current = _reminder;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final failed = wordsStrings(context, 'remindFailed');
    void say() {
      if (mounted) {
        nexShowBanner(context, message: failed, kind: NexBannerKind.failed);
      }
    }

    try {
      final next = (on: on ?? current.on, minutes: minutes ?? current.minutes);
      await widget.store.put(WordsRepository.settingsKind, _reminderId, {
        ...?await widget.store.get(WordsRepository.settingsKind, _reminderId),
        'on': next.on,
        'minutes': next.minutes,
      });
      if (mounted) setState(() => _reminder = next);
      final ok = await wordsArmReminder(widget.store, l10n);
      if (!ok && next.on) say();
    } catch (_) {
      say();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime() async {
    final current = _reminder;
    if (current == null) return;
    final picked = await nexPickModuleTime(
      context,
      initial: TimeOfDay(
        hour: current.minutes ~/ 60,
        minute: current.minutes % 60,
      ),
    );
    if (picked == null || !mounted) return;
    await _save(minutes: picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final reminder = _reminder;
    if (reminder == null) return const SizedBox.shrink();
    final persian = NexModuleStrings.persian(context);
    final time = nexDigits(
      '${nexPad2(reminder.minutes ~/ 60)}:${nexPad2(reminder.minutes % 60)}',
      persian: persian,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexSwitchTile(
          key: const ValueKey('words-remind'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.notifications_active_outlined),
          title: Text(wordsStrings(context, 'remindLabel')),
          subtitle: Text(wordsStrings(context, 'remindHint')),
          value: reminder.on,
          onChanged: _busy ? null : (value) => unawaited(_save(on: value)),
        ),
        if (reminder.on)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('words-remind-time'),
              onPressed: _busy ? null : () => unawaited(_pickTime()),
              icon: const Icon(Icons.schedule),
              label: Text(wordsStrings(context, 'remindAt', {'time': time})),
            ),
          ),
      ],
    );
  }
}
