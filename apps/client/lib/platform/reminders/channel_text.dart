part of '../reminders.dart';

/// The names and descriptions of Nex's notification channels, in one
/// language.
///
/// [daily] is also the name the native daily nudge gives the same channel
/// (`nex.daily`) when it posts — the plan carries it from here. Two names for
/// one channel took turns: Android's settings showed "Daily digest" after the
/// app had run and "Daily nudge" after a notification had.
class NexChannelText {
  const NexChannelText._({
    required this.reminders,
    required this.remindersAbout,
    required this.daily,
    required this.dailyAbout,
    required this.updates,
    required this.updatesAbout,
    required this.done,
    required this.snooze,
  });

  final String reminders;
  final String remindersAbout;
  final String daily;
  final String dailyAbout;
  final String updates;
  final String updatesAbout;

  /// The two buttons under a reminder (2.3.0).
  final String done;
  final String snooze;

  static const en = NexChannelText._(
    reminders: 'Reminders',
    remindersAbout: 'Notes you asked Nex to bring back up',
    daily: 'Daily nudge',
    dailyAbout: 'One reminder a day, at a time you chose',
    updates: 'Updates',
    updatesAbout: 'Downloading a new version of Nex',
    done: 'Done',
    snooze: 'In an hour',
  );

  static const fa = NexChannelText._(
    reminders: 'یادآورها',
    remindersAbout: 'یادداشت‌هایی که خواستید Nex دوباره نشانتان بدهد',
    daily: 'یادآوری روزانه',
    dailyAbout: 'روزی یک یادآوری، در ساعتی که خودتان انتخاب کردید',
    updates: 'به‌روزرسانی‌ها',
    updatesAbout: 'دریافت نسخهٔ تازهٔ Nex',
    done: 'انجام شد',
    snooze: 'یک ساعت دیگر',
  );
}
