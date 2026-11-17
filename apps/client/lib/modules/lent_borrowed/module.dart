import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loans_screen.dart';

/// Lent & borrowed — who owes whom, for money or things, and what has
/// come back. The direction of a debt is never mixed up, and the
/// repayment history is never wiped by an edit.
class LentBorrowedModule extends NexStoredModule {
  const LentBorrowedModule();

  @override
  String get id => 'lent_borrowed';

  @override
  IconData get icon => Icons.swap_horiz_outlined;

  @override
  NexHue get hue => NexHue.slate;

  @override
  NexModuleStrings get strings => lentStrings;

  @override
  Widget screen(NexModuleStore store) => LoansScreen(store: store);
}

const lentStrings = NexModuleStrings(
  en: {
    'amountHint': 'e.g. {example}',
    'amountWordsHint': 'The amount in words appears here.',
    'currency': 'Currency',
    'unitLabel': 'Say amounts in',
    'unitToman': 'Toman',
    'unitRial': 'Rial',
    'unitNote':
        'A toman is ten rials. Amounts are stored in rials, so this only '
        'changes how they are said.',
    'saveError': 'Could not save. Your changes are still here; try again.',
    'loadError': 'Could not load records. Try again.',
    'retry': 'Try again',
    'futureDate': 'In {n} days',
    'dateUnknown': 'Date unknown',
    'dateHint': 'YYYY/MM/DD',
    'dateFieldLabel': 'Date',
    'dateInvalid':
        'Write the date as year/month/day, or pick it from the calendar',
    'dueBeforeIssue': 'Due date cannot be before the issue date',
    'returnFutureDate': 'A return cannot be dated in the future',
    'returnBeforeIssue': 'A return cannot be dated before the loan date',
    'unitLocked': 'Remove returns before changing the currency or record type',

    'title': 'Lent & borrowed',
    'tagline': 'Who owes whom, and what came back',
    'about':
        'Money or things you lent or borrowed, partial returns, and what '
        'is still outstanding — without ever mixing up the direction.',
    'point1': 'Lent and borrowed, separate',
    'point2': 'Partial returns',
    'point3': 'Due soon and overdue, up front',
    'point4': 'Nothing leaves this device',
    'tabLent': 'Lent',
    'tabBorrowed': 'Borrowed',
    'newRecord': 'New record',
    'iLent': 'I lent',
    'iBorrowed': 'I borrowed',
    'personLabel': 'Who?',
    'personHint': 'A name you’ll recognize',
    'money': 'Money',
    'item': 'Item',
    'amountLabel': 'Amount',
    'whatLabel': 'What is it?',
    'whatHint': 'e.g. The blue backpack',
    'quantityLabel': 'How many?',
    'issueLabel': 'When?',
    'todayWord': 'Today',
    'dueLabel': 'Due back?',
    'noDue': 'No due date',
    'dueDays': 'In {n} days',
    'noteLabel': 'Note (optional)',
    'lentTo': 'To {person}',
    'borrowedFrom': 'From {person}',
    'issuedOn': 'Issued {date}',
    'outstanding': '{amount} still out',
    'settledWord': 'Settled',
    'ofTotal': '{done} of {total} returned',
    'dueIn': 'Due in {n} days',
    'dueIn1': 'Due tomorrow',
    'dueTodayWord': 'Due today',
    'overdueBy': '{n} days overdue',
    'overdueBy1': '1 day overdue',
    'noDueWord': 'No due date',
    'noLoansLent': 'Record something you lent to track its return.',
    'noLoansBorrowed': 'You haven’t borrowed anything yet.',
    'outstandingHeading': 'Outstanding',
    'settledHeading': 'Settled',
    'recordReturn': 'Record a return',
    'returnAmount': 'How much came back?',
    'returnQuantity': 'How many came back?',
    'returnDate': 'When?',
    'returnToday': 'Today',
    'yesterdayWord': 'Yesterday',
    'returnDaysAgo': '{n} days ago',
    'markSettled': 'Mark fully returned',
    'owedToMe': 'Owed to me',
    'iOwe': 'I owe',
    'nothingOut': 'Nothing outstanding',
    'moreDetails': 'Dates and a note',
    'moreDetailsHint':
        'When it was lent, when it is due, a few words. All optional.',
    'itemsOut': '{n} items still out',
    'itemsOut1': '1 item still out',
    'itemTitle': '{n} × {what}',
    'rowItemOut': '{n} × {what} still out',
    'rowItemBack': '{n} × {what} came back',
    'overdueCount': '{n} overdue',
    'searchHint': 'Search a person, item or note',
    'filter_all': 'All',
    'filter_dueSoon': 'Due soon',
    'filter_overdue': 'Overdue',
    'filter_settled': 'Settled',
    'noMatches': 'Nothing matches that',
    'people': 'People',
    'peopleEmpty': 'People appear here once you record something.',
    'theyOweYou': 'Owes you {amount}',
    'youOweThem': 'You owe {amount}',
    'allSettled': 'All settled',
    'peopleNothingOut': 'Nothing is outstanding with this person.',
    'messageTitle': 'Reminder message',
    'messageHint':
        'Pick a tone and copy it. Nex never sends anything; the share button '
        'opens your phone’s own sheet.',
    'tone_friendly': 'Friendly',
    'tone_neutral': 'Neutral',
    'tone_formal': 'Formal',
    'messageDue': ', due {date}',
    'message_friendly':
        'Hi {person}! A small thing about {amount}{due} — whenever it suits '
        'you, tell me what timing works and I’ll plan around it. Thank you!',
    'message_neutral':
        'Hi {person}, I hope you’re well. A gentle reminder about '
        '{amount}{due}. No rush — let me know what timing works for you.',
    'message_formal':
        'Dear {person}, I’m sorry to bring this up. May I ask what timing '
        'would be possible for {amount}{due}? Thank you.',
    'messageItem': 'the {what}',
    'messageCopy': 'Copy the message',
    'messageShare': 'Share',
    'messageCopied': 'Message copied',
    'reminderTitle': 'Reminder',
    'reminderHint': 'A one-time alert on the due date you choose.',
    'reminderShowDetail': 'Show who and how much on the lock screen',
    'reminderPrivateNote':
        'Off by default: the notification names neither the person nor the '
        'amount.',
    'reminderBodyPrivate': 'A reminder you set for a loan is due. Open Nex.',
    'reminderBodyDetail': 'The loan with {person} is due back: {amount}.',
    'returnHistory': 'Return history',
    'noReturns': 'Nothing has come back yet.',
    'returnedOn': 'Returned {amount}',
    'deleteReturn': 'Delete this return',
    'returnDeleted': 'Return removed',
    'loanDeleted': 'Record deleted',
    'deleteLoan': 'Delete record',
    'overpay': 'That is more than is still outstanding',
    'zeroAmount': 'The amount has to be more than zero',
    'belowReturned': 'The new total is less than what has already come back',
    'personRequired': 'Write who this was with first',
    'whatRequired': 'Write what it was first',
    'numberInvalid': 'Write that as a plain number',
    'untitledPerson': 'Someone',
    'more': 'More',
    'editRecord': 'Edit record',
  },
  fa: {
    'amountHint': 'مثلاً {example}',
    'amountWordsHint': 'مبلغ به حروف اینجا نوشته می‌شود.',
    'currency': 'ارز',
    'unitLabel': 'مبلغ‌ها با',
    'unitToman': 'تومان',
    'unitRial': 'ریال',
    'unitNote':
        'هر تومان ده ریال است. مبلغ‌ها همیشه به ریال ذخیره می‌شوند و این '
        'انتخاب فقط شیوهٔ گفتن آن‌ها را عوض می‌کند.',
    'saveError': 'ذخیره نشد. تغییراتتان باقی است؛ دوباره تلاش کنید.',
    'loadError': 'اطلاعات بارگذاری نشد. دوباره تلاش کنید.',
    'retry': 'تلاش دوباره',
    'futureDate': '{n} روز دیگر',
    'dateUnknown': 'تاریخ نامشخص',
    'dateHint': 'سال/ماه/روز',
    'dateFieldLabel': 'تاریخ',
    'dateInvalid':
        'تاریخ را کامل به شکل سال/ماه/روز بنویسید یا از تقویم انتخاب کنید',
    'dueBeforeIssue': 'موعد نمی‌تواند پیش از تاریخ قرض باشد',
    'returnFutureDate': 'تاریخ برگشت نمی‌تواند در آینده باشد',
    'returnBeforeIssue': 'تاریخ برگشت نمی‌تواند پیش از تاریخ قرض باشد',
    'unitLocked': 'برای تغییر ارز یا نوع ثبت، ابتدا برگشت‌ها را اصلاح کنید',

    'title': 'قرض و طلب',
    'tagline': 'چه کسی به چه کسی بدهکار است و چه چیزی برگشته',
    'about':
        'پول یا وسیله‌ای که قرض دادید یا گرفتید، برگشت‌های جزئی، و آنچه هنوز '
        'باقی مانده — بدون هیچ‌وقت اشتباه گرفتن جهت بدهی.',
    'point1': 'قرض‌داده و قرض‌گرفته، جدا',
    'point2': 'برگشتِ جزئی',
    'point3': 'نزدیک موعد و دیرکرد، همان اول',
    'point4': 'هیچ چیزی از این دستگاه بیرون نمی‌رود',
    'tabLent': 'قرض‌داده',
    'tabBorrowed': 'قرض‌گرفته',
    'newRecord': 'ثبت تازه',
    'iLent': 'قرض دادم',
    'iBorrowed': 'قرض گرفتم',
    'personLabel': 'چه کسی؟',
    'personHint': 'نامی که بعداً هم بشناسید',
    'money': 'پول',
    'item': 'وسیله',
    'amountLabel': 'مبلغ',
    'whatLabel': 'چه چیزی؟',
    'whatHint': 'مثلاً: کوله‌پشتی آبی',
    'quantityLabel': 'چند عدد؟',
    'issueLabel': 'کی؟',
    'todayWord': 'امروز',
    'dueLabel': 'کِی برگردد؟',
    'noDue': 'بدون موعد',
    'dueDays': '{n} روز دیگر',
    'noteLabel': 'یادداشت (اختیاری)',
    'lentTo': 'به {person}',
    'borrowedFrom': 'از {person}',
    'issuedOn': 'تاریخ قرض: {date}',
    'outstanding': '{amount} هنوز مانده',
    'settledWord': 'تسویه شده',
    'ofTotal': '{done} از {total} برگشته',
    'dueIn': '{n} روز دیگر موعدش است',
    'dueIn1': 'فردا موعدش است',
    'dueTodayWord': 'امروز موعدش است',
    'overdueBy': '{n} روز از موعد گذشته',
    'overdueBy1': 'یک روز از موعد گذشته',
    'noDueWord': 'بدون موعد',
    'noLoansLent': 'چیزی را که قرض داده‌اید ثبت کنید تا برگشتش را پیگیری کنید.',
    'noLoansBorrowed': 'هنوز چیزی قرض نگرفته‌اید.',
    'outstandingHeading': 'باقی‌مانده',
    'settledHeading': 'تسویه‌شده‌ها',
    'recordReturn': 'ثبت برگشت',
    'returnAmount': 'چقدر برگشت؟',
    'returnQuantity': 'چند تا برگشت؟',
    'returnDate': 'کی؟',
    'returnToday': 'امروز',
    'yesterdayWord': 'دیروز',
    'returnDaysAgo': '{n} روز پیش',
    'markSettled': 'ثبت تسویه کامل',
    'owedToMe': 'طلب من',
    'iOwe': 'بدهی من',
    'nothingOut': 'چیزی مانده نیست',
    'moreDetails': 'تاریخ‌ها و یادداشت',
    'moreDetailsHint': 'کی داده شد، سررسید کی است، چند کلمه. همه اختیاری است.',
    'itemsOut': '{n} وسیله هنوز بیرون است',
    'itemsOut1': 'یک وسیله هنوز بیرون است',
    'itemTitle': '{n} عدد {what}',
    'rowItemOut': '{n} عدد {what} هنوز مانده',
    'rowItemBack': '{n} عدد {what} برگشت',
    'overdueCount': '{n} مورد گذشته از موعد',
    'searchHint': 'جست‌وجوی شخص، وسیله یا یادداشت',
    'filter_all': 'همه',
    'filter_dueSoon': 'نزدیک موعد',
    'filter_overdue': 'گذشته از موعد',
    'filter_settled': 'تسویه‌شده',
    'noMatches': 'چیزی پیدا نشد',
    'people': 'اشخاص',
    'peopleEmpty': 'با ثبت اولین مورد، اشخاص اینجا می‌آیند.',
    'theyOweYou': 'به شما {amount} بدهکار است',
    'youOweThem': 'شما {amount} بدهکارید',
    'allSettled': 'همه تسویه شده',
    'peopleNothingOut': 'با این شخص چیزی مانده نیست.',
    'messageTitle': 'پیام یادآوری',
    'messageHint':
        'لحن را انتخاب کنید و پیام را کپی کنید. نکس خودش چیزی نمی‌فرستد؛ '
        'دکمهٔ اشتراک صفحهٔ خود گوشی را باز می‌کند.',
    'tone_friendly': 'دوستانه',
    'tone_neutral': 'معمولی',
    'tone_formal': 'رسمی',
    'messageDue': '، موعد {date}',
    'message_friendly':
        'سلام {person} جان! یک یادآوری کوچک دربارهٔ {amount}{due}؛ هر وقت '
        'راحت بودی بگو چه زمانی برات مناسبه که من هم برنامه‌ام را بچینم. ممنون!',
    'message_neutral':
        'سلام {person}، امیدوارم خوب باشی. یک یادآوری آرام دربارهٔ '
        '{amount}{due}. عجله‌ای نیست؛ فقط بگو چه زمانی برات مناسبه.',
    'message_formal':
        '{person} عزیز، سلام. شرمنده‌ام که این موضوع را پیش می‌کشم؛ ممکن است '
        'بفرمایید برای {amount}{due} چه زمانی مقدور است؟ سپاسگزارم.',
    'messageItem': '{what}',
    'messageCopy': 'کپی پیام',
    'messageShare': 'اشتراک‌گذاری',
    'messageCopied': 'پیام کپی شد',
    'reminderTitle': 'یادآوری',
    'reminderHint': 'یک یادآوری یک‌باره در روز موعدی که انتخاب می‌کنید.',
    'reminderShowDetail': 'نمایش نام و مبلغ روی صفحهٔ قفل',
    'reminderPrivateNote':
        'به‌طور پیش‌فرض خاموش است: اعلان نه نام را می‌گوید نه مبلغ را.',
    'reminderBodyPrivate':
        'موعد یادآوری‌ای که تنظیم کرده بودید رسیده است؛ نکس را باز کنید.',
    'reminderBodyDetail': 'قرض با {person} سررسید شد: {amount}.',
    'returnHistory': 'تاریخچهٔ برگشت‌ها',
    'noReturns': 'هنوز چیزی برنگشته است.',
    'returnedOn': '{amount} برگشت',
    'deleteReturn': 'حذف این برگشت',
    'returnDeleted': 'برگشت حذف شد',
    'loanDeleted': 'ثبت حذف شد',
    'deleteLoan': 'حذف ثبت',
    'overpay': 'این بیشتر از باقی‌مانده است',
    'zeroAmount': 'مبلغ باید بیشتر از صفر باشد',
    'belowReturned': 'مبلغ تازه کمتر از چیزی است که برگشته',
    'personRequired': 'اول بنویسید این با چه کسی بود',
    'whatRequired': 'اول بنویسید چه چیزی بود',
    'numberInvalid': 'آن را به شکل عدد ساده بنویسید',
    'untitledPerson': 'یک نفر',
    'more': 'بیشتر',
    'editRecord': 'ویرایش ثبت',
  },
);
