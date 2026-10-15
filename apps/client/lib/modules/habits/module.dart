import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habits_screen.dart';

/// Habits — an encouraging, one-tap habit tracker. Small progress made
/// visible, without guilt: missed intervals are forgiven explicitly, never
/// silently counted, and every number is a civil-date calculation the
/// README spells out.
class HabitsModule extends NexStoredModule {
  const HabitsModule();

  @override
  String get id => 'habits';

  @override
  IconData get icon => Icons.event_repeat_outlined;

  @override
  NexHue get hue => NexHue.teal;

  @override
  NexModuleStrings get strings => habitsStrings;

  @override
  Widget screen(NexModuleStore store) => HabitsScreen(store: store);
}

const habitsStrings = NexModuleStrings(
  en: {
    'weekStart': 'Week starts on',
    'weekStartHint':
        'Applies to all weekly targets. Changing it recalculates summaries; check-ins stay intact.',
    'weekday1': 'Monday',
    'weekday2': 'Tuesday',
    'weekday3': 'Wednesday',
    'weekday4': 'Thursday',
    'weekday5': 'Friday',
    'weekday6': 'Saturday',
    'weekday7': 'Sunday',
    'freshStreak': 'A fresh start today',
    'saveError': 'Could not save. Your changes are still here; try again.',
    'loadError': 'Could not load records. Try again.',
    'retry': 'Try again',

    'title': 'Habits',
    'tagline': 'Small progress, one tap at a time',
    'about': 'Check habits off with one tap and watch gentle streaks grow.',
    'point1': 'One-tap check-in',
    'point2': 'Forgiving streaks',
    'point3': 'Daily or weekly target',
    'point4': 'Fully offline',
    'today': 'Today',
    'todaySummary': '{done} of {total} done',
    'newHabit': 'New habit',
    'editHabit': 'Edit habit',
    'nameLabel': 'Name',
    'nameHint': 'e.g. Morning stretch',
    'noteLabel': 'Note (optional)',
    'noteHint': 'e.g. 5 minutes, before coffee',
    'daily': 'Daily',
    'weekly': 'Weekly',
    'targetLabel': '{n} times a week',
    'streakDay': '{n}-day streak',
    'streakWeek': '{n}-week streak',
    'graceNow':
        'One missed day is forgiven — check in today to keep the streak.',
    'graceNowWeek':
        'One missed week is forgiven — reach this week’s target to keep it.',
    'graceInside': 'Includes one forgiven day',
    'graceInsideWeek': 'Includes one forgiven week',
    'checkIn': 'Check in for today',
    'undoCheckIn': 'Undo today’s check-in',
    'weekProgress': '{done} of {target} this week',
    'totalCheckins': '{n} check-ins',
    'recentDays': 'Last {n} days',
    'recentSummary': '{done} of {n} days completed',
    'noCheckins': 'No check-ins yet.',
    'firstCheckin': 'The first one is the hardest — and the most interesting.',
    'archived': 'Archived',
    'noArchived': 'No archived habits.',
    'archive': 'Archive',
    'unarchive': 'Unarchive',
    'archivedHint': 'Hidden from Today; history kept',
    'habitDeleted': 'Habit deleted',
    'checkinDeleted': 'Check-in removed',
    'empty': 'No habits yet. Start with one small thing.',
    'allArchived':
        'All your habits are archived. Unarchive one, or start a new one.',
    'untitled': 'Untitled habit',
    'more': 'More',
    'history': 'Recent check-ins',
    'schedule': 'Schedule',
    'yesterday': 'Yesterday',
    'daysAgo': '{n} days ago',
    'dayAgo': '{n} day ago',
    'nameRequired': 'Give the habit a name first',
  },
  fa: {
    'weekStart': 'روز شروع هفته',
    'weekStartHint':
        'برای همهٔ هدف‌های هفتگی است. با تغییر آن، آمار دوباره محاسبه می‌شود و ثبت‌ها می‌مانند.',
    'weekday1': 'دوشنبه',
    'weekday2': 'سه‌شنبه',
    'weekday3': 'چهارشنبه',
    'weekday4': 'پنجشنبه',
    'weekday5': 'جمعه',
    'weekday6': 'شنبه',
    'weekday7': 'یکشنبه',
    'freshStreak': 'امروز، شروعی تازه',
    'saveError': 'ذخیره نشد. تغییراتتان باقی است؛ دوباره تلاش کنید.',
    'loadError': 'اطلاعات بارگذاری نشد. دوباره تلاش کنید.',
    'retry': 'تلاش دوباره',

    'title': 'عادت‌ها',
    'tagline': 'پیشرفتِ کوچک، با هر بار یک لمس',
    'about': 'عادت‌ها را با یک لمس ثبت کنید و پیشرفتتان را ببینید.',
    'point1': 'ثبت با یک لمس',
    'point2': 'تداوم با فرصت جبران',
    'point3': 'روزانه یا هدف هفتگی',
    'point4': 'کاملاً آفلاین',
    'today': 'امروز',
    'todaySummary': '{done} از {total} انجام شد',
    'newHabit': 'عادت جدید',
    'editHabit': 'ویرایش عادت',
    'nameLabel': 'نام',
    'nameHint': 'مثلاً: کشش صبحگاهی',
    'noteLabel': 'یادداشت (اختیاری)',
    'noteHint': 'مثلاً: ۵ دقیقه، قبل از قهوه',
    'daily': 'روزانه',
    'weekly': 'هفتگی',
    'targetLabel': '{n} بار در هفته',
    'streakDay': 'تداومِ {n} روزه',
    'streakWeek': 'تداومِ {n} هفته‌ای',
    'graceNow': 'یک روز جاافتاده بخشیده شده؛ امروز ثبت کنید تا تداوم حفظ شود.',
    'graceNowWeek':
        'یک هفته جاافتاده بخشیده شده؛ این هفته به هدف برسید تا تداوم حفظ شود.',
    'graceInside': 'شامل یک روز بخشیده‌شده',
    'graceInsideWeek': 'شامل یک هفته بخشیده‌شده',
    'checkIn': 'ثبت برای امروز',
    'undoCheckIn': 'برداشتن ثبتِ امروز',
    'weekProgress': '{done} از {target} این هفته',
    'totalCheckins': '{n} ثبت',
    'recentDays': '{n} روز اخیر',
    'recentSummary': '{done} از {n} روز ثبت شده',
    'noCheckins': 'هنوز ثبتی نیست.',
    'firstCheckin': 'اولین ثبت سخت‌ترین است — و جالب‌ترین.',
    'archived': 'بایگانی‌شده',
    'noArchived': 'عادت بایگانی‌شده‌ای نیست.',
    'archive': 'بایگانی',
    'unarchive': 'خروج از بایگانی',
    'archivedHint': 'از امروز پنهان است؛ تاریخچه می‌ماند',
    'habitDeleted': 'عادت حذف شد',
    'checkinDeleted': 'ثبت برداشته شد',
    'empty': 'هنوز عادتی نیست. با یک چیز کوچک شروع کنید.',
    'allArchived':
        'همهٔ عادت‌ها بایگانی شده‌اند. یکی را بیرون بیاورید یا تازه‌ای بسازید.',
    'untitled': 'عادت بی‌نام',
    'more': 'بیشتر',
    'history': 'ثبت‌های اخیر',
    'schedule': 'برنامه',
    'yesterday': 'دیروز',
    'daysAgo': '{n} روز پیش',
    'dayAgo': '{n} روز پیش',
    'nameRequired': 'اول یک نام برای عادت بنویسید',
  },
);
