import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'occasions_screen.dart';

/// Birthdays and occasions — dates that matter, kept in the calendar they
/// are celebrated in. A Jalali date returns on the same Jalali day every
/// year, a Gregorian date on its Gregorian day; the countdown, the greeting
/// to copy and the optional reminder follow from that. Nothing is sent for
/// anyone, and no contact or calendar is read.
class OccasionsModule extends NexStoredModule {
  const OccasionsModule();

  @override
  String get id => 'occasions';

  @override
  IconData get icon => Icons.cake_outlined;

  @override
  NexHue get hue => NexHue.rose;

  @override
  NexModuleStrings get strings => occasionsStrings;

  @override
  Widget screen(NexModuleStore store) => OccasionsScreen(store: store);
}

const occasionsStrings = NexModuleStrings(
  en: {
    'title': 'Birthdays & occasions',
    'tagline': 'Dates that matter, in the calendar you keep them in',
    'about':
        'Birthdays, anniversaries and other dates you do not want to miss. '
        'A Jalali date returns on the same Jalali day every year and a '
        'Gregorian one on its Gregorian day. A countdown, a greeting to '
        'copy and an optional reminder — nothing is sent for you.',
    'point1': 'Each date repeats in its own calendar',
    'point2': 'Countdown to the next one',
    'point3': 'A greeting ready to copy',
    'point4': 'Reminders only if you ask',

    'empty': 'No dates yet. Add a birthday or an anniversary.',
    'add': 'Add an occasion',
    'heroEyebrow': 'Coming up',
    'heroToday': '{n} today',
    'heroNext': 'Next in {n} days',
    'heroNone': 'Nothing coming up',
    'heroWeek': '{n} this week',
    'sectionToday': 'Today',
    'sectionWeek': 'In the next 7 days',
    'sectionMonth': 'In the next 30 days',
    'sectionLater': 'Later',
    'sectionFix': 'Needs a date',
    'sectionArchived': 'Archived',
    'showArchived': 'Archived ({n})',
    'hideArchived': 'Hide archived',
    'today': 'Today',
    'tomorrow': 'Tomorrow',
    'inDays': 'in {n} days',
    'turns': 'turns {n}',
    'yearN': 'year {n}',
    'untitled': 'Untitled',
    'fixDate': 'Choose a day and month for this one.',
    'muted': 'Muted',
    'kindBirthday': 'Birthday',
    'kindAnniversary': 'Anniversary',
    'kindMemorial': 'Remembrance',
    'kindOther': 'Other',

    'newOccasion': 'New occasion',
    'editOccasion': 'Edit occasion',
    'kindLabel': 'What is it',
    'titleLabel': 'Name or title',
    'titleHint': 'For example: Sara\'s birthday',
    'titleRequired': 'Give it a name first.',
    'calendarLabel': 'Repeats every year in',
    'jalali': 'Jalali',
    'gregorian': 'Gregorian',
    'dayLabel': 'Day',
    'monthLabel': 'Month',
    'yearLabel': 'Year',
    'yearUnknown': 'I do not know the year',
    'pickDate': 'Pick from the calendar',
    'dayInvalid': 'That day does not exist in this month.',
    'yearInvalid': 'Write the year as a number.',
    'yearFuture': 'That year has not come yet.',
    'yearDayInvalid': 'That day did not exist in that year.',
    'leapTitle': 'In years without this day',
    'leapLast': 'Use the last day of the month',
    'leapNext': 'Use the first day of the next month',
    'noteLabel': 'Note or gift ideas',
    'noteHint': 'Optional',
    'remindLabel': 'Remind me',
    'remindOnDay': 'On the day',
    'remindOneBefore': '1 day before',
    'remindThreeBefore': '3 days before',
    'remindWeekBefore': 'A week before',
    'remindAt': 'At {time}',
    'remindNote':
        'It rings for the next two times and renews whenever you open this '
        'module. Nothing is sent to anyone.',
    'remindFailed':
        'Saved, but the reminder could not be set. Check the notification '
        'permission.',
    'notifToday': '{name} is today.',
    'notifTomorrow': '{name} is tomorrow.',
    'notifDays': '{name} is in {n} days.',
    'notifNeutral': 'A date you keep is coming up. Open Nex.',
    'save': 'Save',

    'nextLabel': 'Next',
    'repeatsOn': 'Repeats every year on {date} in the {calendar} calendar.',
    'bothCalendars': 'Jalali: {a} · Gregorian: {b}',
    'reminderOff': 'No reminder.',
    'reminderOn': 'Reminder {when}, at {time}.',
    'reminderWhenToday': 'on the day',
    'reminderWhenDays': '{n} days before',
    'reminderMuted': 'Muted: no reminder.',
    'greetingTitle': 'Greeting',
    'copyGreeting': 'Copy greeting',
    'shareGreeting': 'Share',
    'greetingCopied': 'Greeting copied.',
    'greetBirthday': 'Happy birthday! Wishing you a wonderful year ahead.',
    'greetAnniversary': 'Happy anniversary! Here is to many more happy years.',
    'greetMemorial': 'Thinking of you today, and remembering together.',
    'greetOther': 'Thinking of you today.',
    'edit': 'Edit',
    'favorite': 'Mark as important',
    'unfavorite': 'Remove from important',
    'mute': 'Mute reminders',
    'unmute': 'Unmute',
    'archive': 'Archive',
    'unarchive': 'Unarchive',
    'delete': 'Delete',
    'deleted': 'Deleted',
    'undo': 'Undo',
    'saveError': 'Could not save. Try again.',
    'loadError': 'Could not load your dates.',
    'retry': 'Retry',
    'keepEditing': 'Keep editing',
    'discard': 'Discard',
    'discardTitle': 'Leave without saving?',
    'discardBody': 'What you wrote here has not been saved.',
    'more': 'More',
    'invalidTitle': 'This date is not complete',
  },
  fa: {
    'title': 'تولدها و مناسبت‌ها',
    'tagline': 'تاریخ‌های مهم، در تقویمی که نگهشان می‌دارید',
    'about':
        'تولد، سالگرد و تاریخ‌های دیگری که نمی‌خواهید از دستشان بدهید. '
        'تاریخ شمسی هر سال در همان روز شمسی برمی‌گردد و تاریخ میلادی در '
        'روز میلادی خودش. شمارش معکوس، یک پیام تبریک آمادهٔ کپی و یادآوریِ '
        'اختیاری — چیزی به‌جای شما فرستاده نمی‌شود.',
    'point1': 'هر تاریخ در تقویم خودش تکرار می‌شود',
    'point2': 'شمارش معکوس تا بعدی',
    'point3': 'پیام تبریک آمادهٔ کپی',
    'point4': 'یادآوری فقط اگر بخواهید',

    'empty': 'هنوز تاریخی ثبت نشده. یک تولد یا سالگرد اضافه کنید.',
    'add': 'افزودن مناسبت',
    'heroEyebrow': 'در پیش رو',
    'heroToday': '{n} مورد امروز',
    'heroNext': 'بعدی {n} روز دیگر',
    'heroNone': 'چیزی در پیش نیست',
    'heroWeek': '{n} مورد این هفته',
    'sectionToday': 'امروز',
    'sectionWeek': '۷ روز آینده',
    'sectionMonth': '۳۰ روز آینده',
    'sectionLater': 'بعدتر',
    'sectionFix': 'تاریخ ندارد',
    'sectionArchived': 'بایگانی',
    'showArchived': 'بایگانی ({n})',
    'hideArchived': 'پنهان‌کردن بایگانی',
    'today': 'امروز',
    'tomorrow': 'فردا',
    'inDays': '{n} روز دیگر',
    'turns': '{n} ساله می‌شود',
    'yearN': 'سال {n}',
    'untitled': 'بدون نام',
    'fixDate': 'برای این مورد روز و ماه را انتخاب کنید.',
    'muted': 'بی‌صدا',
    'kindBirthday': 'تولد',
    'kindAnniversary': 'سالگرد',
    'kindMemorial': 'یادبود',
    'kindOther': 'دیگر',

    'newOccasion': 'مناسبت تازه',
    'editOccasion': 'ویرایش مناسبت',
    'kindLabel': 'چه مناسبتی است',
    'titleLabel': 'نام یا عنوان',
    'titleHint': 'مثلاً: تولد سارا',
    'titleRequired': 'اول یک نام بدهید.',
    'calendarLabel': 'هر سال در تقویم',
    'jalali': 'شمسی',
    'gregorian': 'میلادی',
    'dayLabel': 'روز',
    'monthLabel': 'ماه',
    'yearLabel': 'سال',
    'yearUnknown': 'سالش را نمی‌دانم',
    'pickDate': 'انتخاب از تقویم',
    'dayInvalid': 'این روز در این ماه وجود ندارد.',
    'yearInvalid': 'سال را به شکل عدد بنویسید.',
    'yearFuture': 'آن سال هنوز نرسیده است.',
    'yearDayInvalid': 'این روز در آن سال وجود نداشت.',
    'leapTitle': 'در سال‌هایی که این روز نیست',
    'leapLast': 'آخرین روز ماه',
    'leapNext': 'اولین روز ماه بعد',
    'noteLabel': 'یادداشت یا ایدهٔ هدیه',
    'noteHint': 'اختیاری',
    'remindLabel': 'یادآوری',
    'remindOnDay': 'خود روز',
    'remindOneBefore': '۱ روز قبل',
    'remindThreeBefore': '۳ روز قبل',
    'remindWeekBefore': 'یک هفته قبل',
    'remindAt': 'ساعت {time}',
    'remindNote':
        'برای دو نوبت آینده زنگ می‌خورد و هر بار این ماژول را باز کنید '
        'تازه می‌شود. چیزی برای کسی فرستاده نمی‌شود.',
    'remindFailed':
        'ذخیره شد، اما یادآوری تنظیم نشد. مجوز اعلان را بررسی کنید.',
    'notifToday': '{name} امروز است.',
    'notifTomorrow': '{name} فردا است.',
    'notifDays': '{name} {n} روز دیگر است.',
    'notifNeutral': 'تاریخی که نگه داشته‌اید نزدیک است. نکس را باز کنید.',
    'save': 'ذخیره',

    'nextLabel': 'بعدی',
    'repeatsOn': 'هر سال در {date} تکرار می‌شود، در تقویم {calendar}.',
    'bothCalendars': 'شمسی: {a} · میلادی: {b}',
    'reminderOff': 'یادآوری ندارد.',
    'reminderOn': 'یادآوری {when}، ساعت {time}.',
    'reminderWhenToday': 'در خود روز',
    'reminderWhenDays': '{n} روز قبل',
    'reminderMuted': 'بی‌صدا: بدون یادآوری.',
    'greetingTitle': 'پیام تبریک',
    'copyGreeting': 'کپی پیام',
    'shareGreeting': 'ارسال',
    'greetingCopied': 'پیام کپی شد.',
    'greetBirthday': 'تولدت مبارک! سالی پر از شادی و سلامتی برایت آرزو می‌کنم.',
    'greetAnniversary': 'سالگردتان مبارک! آرزوی سال‌های بسیار شاد دیگر.',
    'greetMemorial': 'امروز به یاد شما هستم و با شما همراهم.',
    'greetOther': 'امروز به یادت هستم.',
    'edit': 'ویرایش',
    'favorite': 'مهم کردن',
    'unfavorite': 'برداشتن علامت مهم',
    'mute': 'بی‌صدا کردن یادآوری',
    'unmute': 'برگرداندن صدا',
    'archive': 'بایگانی',
    'unarchive': 'خروج از بایگانی',
    'delete': 'حذف',
    'deleted': 'حذف شد',
    'undo': 'بازگردانی',
    'saveError': 'ذخیره نشد. دوباره تلاش کنید.',
    'loadError': 'تاریخ‌ها خوانده نشد.',
    'retry': 'تلاش دوباره',
    'keepEditing': 'ادامهٔ ویرایش',
    'discard': 'دور انداختن',
    'discardTitle': 'بدون ذخیره بیرون می‌روید؟',
    'discardBody': 'آنچه این‌جا نوشتید ذخیره نشده است.',
    'more': 'بیشتر',
    'invalidTitle': 'این تاریخ کامل نیست',
  },
);
