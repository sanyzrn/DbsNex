import 'package:nex_core/nex_core.dart';

import 'dart:isolate';

import 'reminders.dart';

/// Builds dated, local-only notification text. Native delivery chooses the
/// matching date and never repeats a dated factual message indefinitely.
///
/// Each planned day carries two windows, because the two kinds of text age
/// differently: `expires` for the recap (a sentence about now) and
/// `localExpires` for the note-and-reminder bodies (facts about that date).
/// The native side reads both — see `NexDailyNudgeReceiver.deliver`.
abstract final class NexDailyNudgeContent {
  static String dayKey(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';

  static String short(String text, [int limit = 160]) {
    final plain = NexMarkdownText.preview(text)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return plain.runes.length <= limit
        ? plain
        : '${String.fromCharCodes(plain.runes.take(limit - 1))}…';
  }

  static const emptyFa = [
    'یه ایده توی ذهنت داری؟ قبل از اینکه فراموش بشه، توی Nex ثبتش کن.',
    'برای امروز برنامه‌ای داری؟ حتی یه یادداشت کوچیک هم می‌تونه شروع خوبی باشه.',
    'چیزی هست که بخوای بعداً یادت بیاد؟ Nex می‌تونه نگهش داره.',
    'گاهی بهترین ایده‌ها یهویی به ذهن می‌رسن. یه جا برای ثبتشون داشته باش!',
    'هنوز چیزی توی Nex ثبت نکردی؟ اولین یادداشتت فقط چند ثانیه فاصله داره.',
  ];
  static const emptyEn = [
    'Got an idea? Capture it in Nex before it slips away.',
    'Any plans for today? Even a quick note is a good place to start.',
    'Something you want to remember later? Let Nex keep it for you.',
    'The best ideas can arrive out of nowhere. Give yours a place to stay!',
    'Nothing in Nex yet? Your first note is only a few seconds away.',
  ];
  static const quietFa = [
    'یه مرور کوتاه روی یادداشت‌هات؛ شاید ایده‌ای آمادهٔ قدم بعدی باشه.',
    'چیزی از امروز هست که بخوای نگهش داری؟ Nex آماده‌ست.',
    'گاهی برگشتن به یک یادداشت، شروع یک ایدهٔ تازه‌ست.',
    'چند لحظه برای فکرهات وقت بذار؛ یادداشت‌هات همین‌جا هستن.',
    'امروز می‌تونی یک فکر نیمه‌کاره رو کمی جلوتر ببری.',
  ];
  static const quietEn = [
    'Take a quick look through your notes. An idea may be ready for its next step.',
    'Anything from today worth keeping? Nex is ready.',
    'Revisiting a note can be the start of a new idea.',
    'Make a little space for your thoughts. Your notes are here when you need them.',
    'Today could be a good day to take one unfinished thought a little further.',
  ];

  static List<String> local(
    NexNudgeSnapshot source,
    DateTime at, {
    required bool persian,
    bool solarCalendar = false,
    Map<String, List<ChecklistItem>>? itemsById,
  }) {
    final facts = <({int rank, DateTime when, String id, String text})>[];
    String quoted(String value) =>
        persian ? '«${short(value, 48)}»' : '“${short(value, 48)}”';
    final active = source.notes.where(
      (note) => !note.isDeleted && !note.isSetAside(at),
    );
    for (final note in active) {
      final items = itemsById?[note.id] ?? note.checklistItems;
      if (note.type == NoteType.checklist &&
          (items.isEmpty || items.every((i) => i.done))) {
        continue;
      }
      // What a note is called when it has no words of its own. Every branch
      // below can come out empty — a checklist whose remaining items have
      // blank text, a photo with no caption — and an empty quotation («»)
      // reads as a broken notification, not as a note worth looking at.
      final typeLabel = switch (note.type) {
        NoteType.photo => persian ? 'یادداشت تصویری' : 'Photo note',
        NoteType.voice => persian ? 'یادداشت صوتی' : 'Voice note',
        NoteType.file => persian ? 'فایل' : 'File',
        _ => persian ? 'یادداشت' : 'Note',
      };
      final titled = note.type == NoteType.checklist
          ? items
                .where((item) => !item.done && item.text.trim().isNotEmpty)
                .take(3)
                .map((item) => item.text)
                .join(' · ')
          : (note.displayText?.trim().isNotEmpty == true
                ? note.displayText!
                : note.originalFilename ?? '');
      final title = quoted(titled.trim().isEmpty ? typeLabel : titled);
      if (note.isUrgent) {
        facts.add((
          rank: 0,
          when: note.updatedAt,
          id: note.id,
          text: persian ? 'فوری: $title' : 'Urgent: $title',
        ));
      }
      if (note.dueAt case final stored?) {
        final due = NexReminders.computeNextOccurrence(
          stored,
          note.dueRepeat,
          at,
        );
        final gap = due.difference(at);
        if (gap.isNegative && gap >= const Duration(days: -7)) {
          facts.add((
            rank: 1,
            when: due,
            id: note.id,
            text: persian
                ? 'یادآور عقب‌افتاده: $title'
                : 'Overdue reminder: $title',
          ));
        } else if (!gap.isNegative && gap <= const Duration(days: 2)) {
          final local = at.isUtc ? due.toUtc() : due.toLocal();
          final day = DateTime(
            local.year,
            local.month,
            local.day,
          ).difference(DateTime(at.year, at.month, at.day)).inDays;
          final word = persian
              ? ['امروز', 'فردا', 'پس‌فردا'][day.clamp(0, 2)]
              : ['today', 'tomorrow', 'the day after tomorrow'][day.clamp(
                  0,
                  2,
                )];
          final clock = nexDigits(
            '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
            persian: persian,
          );
          facts.add((
            rank: 2,
            when: due,
            id: note.id,
            text: persian
                ? '$title، $word ساعت $clock'
                : '$title, $word at $clock',
          ));
        }
      }
      final left = items.where((i) => !i.done).length;
      if (left > 0 &&
          at.difference(note.updatedAt) <= const Duration(days: 30)) {
        final count = nexDigits('$left', persian: persian);
        facts.add((
          rank: 4,
          when: note.updatedAt,
          id: note.id,
          text: persian
              ? '$count مورد ناتمام در $title'
              : '$count unfinished ${left == 1 ? 'item' : 'items'} in $title',
        ));
      }
    }
    for (final item in source.commitments) {
      if (item.paused) continue;
      final gap = item.dueAt.difference(at);
      if (gap < const Duration(days: -7) || gap > const Duration(days: 2)) {
        continue;
      }
      final title = quoted(item.title);
      facts.add((
        rank: gap.isNegative ? 1 : 3,
        when: item.dueAt,
        id: 'commitment:${item.id}',
        text: persian
            ? '${gap.isNegative ? 'نوبت عقب‌افتاده' : 'نوبت پیش رو'}: $title'
            : '${gap.isNegative ? 'Overdue' : 'Upcoming'} occurrence: $title',
      ));
    }
    facts.sort((a, b) {
      final rank = a.rank.compareTo(b.rank);
      return rank == 0 ? a.when.compareTo(b.when) : rank;
    });
    final seen = <String>{};
    final picked = facts
        .where((f) => seen.add(f.id))
        .take(2)
        .map((f) => f.text)
        .join(persian ? '؛ ' : '; ');
    if (picked.isEmpty) {
      // A day with nothing due is the day for something old: a line the
      // person wrote on this date, in place of a line anyone could be sent.
      final memory = onThisDay(
        source.memories,
        at,
        persian: persian,
        solarCalendar: solarCalendar,
      );
      if (memory != null) return [memory];
      return source.hasData
          ? (persian ? quietFa : quietEn)
          : (persian ? emptyFa : emptyEn);
    }
    return persian
        ? [
            short(picked, 210),
            short('یادآوری کوتاه: $picked', 210),
            short('نگاهی به این‌ها بنداز: $picked', 210),
          ]
        : [
            short(picked, 210),
            short('A quick reminder: $picked', 210),
            short('Worth a look: $picked', 210),
          ];
  }

  /// "A year ago today you wrote …", from [memories], or null when no note
  /// with words of its own was written on [at]'s date in an earlier year.
  ///
  /// The date is the one the person reads: with [solarCalendar] an
  /// anniversary is the same day of the same Persian month, which the
  /// Gregorian date misses by a day in some years. The nearest year wins —
  /// last year is the memory most likely to still mean something — and the
  /// longest note of that day, which is how the snapshot orders them.
  static String? onThisDay(
    List<Note> memories,
    DateTime at, {
    required bool persian,
    bool solarCalendar = false,
  }) {
    ({int year, int month, int day}) dateOf(DateTime value) => solarCalendar
        ? nexPersianDate(value)
        : (year: value.year, month: value.month, day: value.day);
    final today = dateOf(at);
    ({int years, String text})? best;
    for (final note in memories) {
      if (note.isDeleted || note.isSetAside(at)) continue;
      final text = note.displayText?.trim() ?? '';
      if (text.isEmpty) continue;
      final written = dateOf(
        at.isUtc ? note.createdAt.toUtc() : note.createdAt.toLocal(),
      );
      final years = today.year - written.year;
      if (years < 1 ||
          written.month != today.month ||
          written.day != today.day) {
        continue;
      }
      if (best == null || years < best.years) best = (years: years, text: text);
    }
    if (best == null) return null;
    final quote = short(best.text, 120);
    if (persian) {
      final ago = best.years == 1
          ? 'پارسال'
          : '${nexDigits('${best.years}', persian: true)} سال پیش';
      return short('$ago، همین روز نوشتی: «$quote»', 210);
    }
    final ago = best.years == 1 ? 'A year ago' : '${best.years} years ago';
    return short('$ago today you wrote: “$quote”', 210);
  }

  static bool canUseSummary({
    required bool aiEnabled,
    required bool summaryEnabled,
    required bool sourceMatches,
    required DateTime? writtenAt,
    required DateTime deliveryAt,
    required String? text,
  }) =>
      aiEnabled &&
      summaryEnabled &&
      sourceMatches &&
      writtenAt != null &&
      text != null &&
      text.trim().isNotEmpty &&
      !deliveryAt.isBefore(writtenAt) &&
      deliveryAt.difference(writtenAt) <= const Duration(hours: 1) &&
      dayKey(deliveryAt) == dayKey(writtenAt);

  static Map<String, Object?> plan({
    required NexNudgeSnapshot source,
    required DateTime now,
    required int minutes,
    required bool persian,
    required String title,
    required bool aiEnabled,
    required bool summaryEnabled,
    required bool sourceMatches,
    required String? summary,
    required DateTime? summaryAt,
    required bool secret,
    bool solarCalendar = false,
  }) {
    final days = <String, Object?>{};
    final parsed = {
      for (final note in source.notes)
        if (note.type == NoteType.checklist) note.id: note.checklistItems,
    };
    for (var i = 0; i < 32; i++) {
      final at = DateTime(
        now.year,
        now.month,
        now.day + i,
        minutes ~/ 60,
        minutes % 60,
      );
      if (!at.isAfter(now)) continue;
      final ai = canUseSummary(
        aiEnabled: aiEnabled,
        summaryEnabled: summaryEnabled,
        sourceMatches: sourceMatches,
        writtenAt: summaryAt,
        deliveryAt: at,
        text: summary,
      );
      final alternatives = local(
        source,
        at,
        persian: persian,
        solarCalendar: solarCalendar,
        itemsById: parsed,
      );
      // Local bodies describe the day they were planned for — "tomorrow at
      // 09:00", "3 unfinished items" — so they stay true until that day ends.
      // They used to expire one hour after the slot, and an alarm Android
      // delivers late (an inexact alarm under Doze, on a phone that refused
      // the exact-alarm permission) then arrived with every dated body
      // rejected: not a stale line sometimes, but the neutral rotation every
      // day on exactly the phones that needed the nudge most.
      final localExpires =
          DateTime(at.year, at.month, at.day + 1).millisecondsSinceEpoch - 1;
      // A recap is a sentence about now rather than about a date, so it keeps
      // its one-hour freshness — and never outlives the day it describes.
      final aiExpires = ai
          ? summaryAt!.add(const Duration(hours: 1)).millisecondsSinceEpoch
          : localExpires;
      days[dayKey(at)] = {
        'ai': ai,
        'zone': at.timeZoneOffset.inMinutes,
        'bodies': ai ? [short(summary!, 210)] : alternatives,
        'localBodies': alternatives,
        'expires': aiExpires < localExpires ? aiExpires : localExpires,
        'localExpires': localExpires,
      };
    }
    return {
      'version': 1,
      'enabled': true,
      'minutes': minutes,
      'title': title,
      'secret': secret,
      'generatedAt': now.millisecondsSinceEpoch,
      'zone': now.timeZoneOffset.inMinutes,
      'channelName': persian ? 'یادآوری روزانه' : 'Daily nudge',
      'days': days,
      'fallback': source.hasData
          ? (persian ? quietFa : quietEn)
          : (persian ? emptyFa : emptyEn),
    };
  }
}

typedef NexNudgePlanInput = ({
  NexNudgeSnapshot source,
  DateTime now,
  int minutes,
  bool persian,
  String title,
  bool aiEnabled,
  bool summaryEnabled,
  bool sourceMatches,
  String? summary,
  DateTime? summaryAt,
  bool secret,
  bool solarCalendar,
});

/// Isolate entry point: planning a month's text never runs on the UI thread.
Map<String, Object?> nexBuildDailyNudgePlan(NexNudgePlanInput input) =>
    NexDailyNudgeContent.plan(
      source: input.source,
      now: input.now,
      minutes: input.minutes,
      persian: input.persian,
      title: input.title,
      aiEnabled: input.aiEnabled,
      summaryEnabled: input.summaryEnabled,
      sourceMatches: input.sourceMatches,
      summary: input.summary,
      summaryAt: input.summaryAt,
      secret: input.secret,
      solarCalendar: input.solarCalendar,
    );

Future<Map<String, Object?>> nexComputeDailyNudgePlan(
  NexNudgePlanInput input,
) => Isolate.run(() => nexBuildDailyNudgePlan(input));
