import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'smoke_free_screen.dart';

/// Smoke-free — a private, compassionate quit companion. Progress, honest
/// estimates, and the patterns behind cravings; never a diagnosis, a
/// recovery timetable, or a promise about anyone's body.
class SmokeFreeModule extends NexStoredModule {
  const SmokeFreeModule();

  @override
  String get id => 'smoke_free';

  @override
  IconData get icon => Icons.smoke_free_outlined;

  @override
  NexHue get hue => NexHue.teal;

  @override
  NexModuleStrings get strings => smokeFreeStrings;

  @override
  Widget screen(NexModuleStore store) => SmokeFreeScreen(store: store);
}

const smokeFreeStrings = NexModuleStrings(
  en: {
    'restartAttempt': 'Start a new attempt',
    'restartBody':
        'Ends this attempt and starts a new one today with the same baseline and currency. All earlier attempts and cravings stay in your history.',
    'amountHint': 'e.g. {example} (dot or ٫ for decimals)',
    'returnOffsetLabel': 'Days ago',
    'currency': 'Currency',
    'saveError': 'Could not save. Your changes are still here; try again.',
    'loadError': 'Could not load records. Try again.',
    'retry': 'Try again',
    'futureDate': 'In {n} days',
    'dateUnknown': 'Date unknown',
    'attemptSameDay': 'Ended on the day it started',
    'startAttempt': 'Start this attempt',
    'estimateBoundary':
        'Days count calendar boundaries, not full 24-hour periods. Savings are rounded down to the smallest currency unit.',

    'title': 'Smoke-free',
    'tagline': 'The days you’ve kept, counted gently',
    'about':
        'Counts the days, the cigarettes not smoked and the money kept. '
        'A craving logged in one tap, and what sets cravings off.',
    'point1': 'One-tap craving log',
    'point2': 'Honest estimates',
    'point3': 'Patterns over time',
    'point4': 'Attempts kept, never erased',
    'setupTitle': 'Start smoke-free',
    'setupEditTitle': 'Edit your baseline',
    'startToday': 'Start today',
    'daysAgoLabel': 'Days since quitting',
    'daysAgoHint': '0 means today',
    'perDayLabel': 'Cigarettes a day before quitting',
    'priceLabel': 'Price of a pack',
    'perPackLabel': 'Cigarettes in a pack',
    'explainBaseline':
        'These three numbers only shape the estimates on the dashboard. '
        'You can correct them any time; the days you’ve kept are yours.',
    'smokeFreeFor': 'Smoke-free for {days} days',
    'smokeFreeToday': 'Smoke-free since today',
    'cigarettesAvoided': '≈ {n} cigarettes not smoked',
    'moneySaved': '≈ {money} kept',
    'estimateNote':
        'From {perDay} a day, {price} a pack of {perPack}. '
        'Estimates, not promises.',
    'supportDay0': 'The first hours are the hardest. Being here counts.',
    'supportDay1':
        'A new day in your attempt. Keep taking it one step at a time.',
    'supportDays': 'Each day is its own quiet win.',
    'supportWeek': 'A week of it. Keep going, gently.',
    'supportMonth': 'Weeks in. You know your patterns now.',
    'supportYear': 'Your effort over time matters. Keep going at your pace.',
    'logCraving': 'Log a craving',
    'cravingTitle': 'A craving',
    'intensity': 'How strong?',
    'intensityLow': 'Light',
    'intensityMedium': 'Strong',
    'intensityHigh': 'Overwhelming',
    'triggers': 'What set it off?',
    'coping': 'What did you do?',
    'noteLabel': 'Note (optional)',
    'noteHint': 'A word is enough',
    'cravingsHeading': 'Recent cravings',
    'noCravings': 'No cravings logged yet. Log one whenever you need to.',
    'patternHeading': 'The pattern',
    'patternTop': 'Most common: {name} ({n} times)',
    'patternNone': 'No pattern yet — too few cravings.',
    'todayWord': 'Today',
    'yesterdayWord': 'Yesterday',
    'daysAgoWord': '{n} days ago',
    'recordLapse': 'I smoked',
    'more': 'More',
    'trigger_stress': 'Stress',
    'trigger_boredom': 'Boredom',
    'trigger_coffee': 'Coffee or tea',
    'trigger_afterMeal': 'After a meal',
    'trigger_social': 'Being with smokers',
    'trigger_driving': 'Driving',
    'trigger_tired': 'Tiredness',
    'trigger_emotion': 'A feeling',
    'trigger_other': 'Something else',
    'coping_water': 'Drank water',
    'coping_deepBreath': 'Deep breaths',
    'coping_walk': 'Walked',
    'coping_gum': 'Chewed gum',
    'coping_waited': 'Waited it out',
    'coping_distraction': 'Kept busy',
    'lapseTitle': 'Record a lapse?',
    'lapseBody':
        'This ends the current attempt and keeps it in your history. '
        'You can start again today with the same baseline — nothing is erased.',
    'lapseJust': 'Just record it',
    'lapseRestart': 'Record and start fresh today',
    'newAttemptStarted': 'A new attempt started today',
    'lapseRecorded': 'Lapse recorded',
    'noActive': 'No attempt running.',
    'startButton': 'Start smoke-free',
    'historyHeading': 'Earlier attempts',
    'attemptLine': 'Lasted {days} days',
    'editBaseline': 'Edit baseline',
    'cravingDeleted': 'Craving deleted',
    'deleteCraving': 'Delete',
    'numberInvalid': 'Write that as a plain number',
    'daysInvalid': 'Days cannot be negative',
    'priceInvalid': 'The price cannot be negative',
  },
  fa: {
    'restartAttempt': 'شروع تلاش تازه',
    'restartBody':
        'تلاش فعلی پایان می‌یابد و تلاش تازه‌ای از امروز با همان مبنا و ارز شروع می‌شود. همهٔ تلاش‌ها و هوس‌های قبلی در تاریخچه می‌مانند.',
    'amountHint': 'مثلاً {example} (اعشار با نقطه یا ٫)',
    'returnOffsetLabel': 'چند روز پیش',
    'currency': 'ارز',
    'saveError': 'ذخیره نشد. تغییراتتان باقی است؛ دوباره تلاش کنید.',
    'loadError': 'اطلاعات بارگذاری نشد. دوباره تلاش کنید.',
    'retry': 'تلاش دوباره',
    'futureDate': '{n} روز دیگر',
    'dateUnknown': 'تاریخ نامشخص',
    'attemptSameDay': 'در روز شروع پایان یافت',
    'startAttempt': 'شروع این تلاش',
    'estimateBoundary':
        'روزها با تغییر تاریخ شمرده می‌شوند، نه دوره‌های کامل ۲۴ ساعته. برآورد پول به واحد خرد ارز رو به پایین گرد می‌شود.',

    'title': 'بدون سیگار',
    'tagline': 'روزهایی که نگه داشته‌اید، با مهربانی شمرده می‌شوند',
    'about':
        'روزها، سیگارهایی که نکشیدید و پولی که ماند را می‌شمارد. '
        'هوس را با یک لمس ثبت کنید و ببینید چه چیزی آن را راه می‌اندازد.',
    'point1': 'ثبت هوس با یک لمس',
    'point2': 'برآوردهای درست',
    'point3': 'الگوها در طول زمان',
    'point4': 'تلاش‌ها می‌مانند، پاک نمی‌شوند',
    'setupTitle': 'شروعِ بدون سیگار',
    'setupEditTitle': 'ویرایش مبنای برآورد',
    'startToday': 'از امروز شروع می‌کنم',
    'daysAgoLabel': 'چند روز پیش ترک کردم',
    'daysAgoHint': '۰ یعنی امروز',
    'perDayLabel': 'تعداد سیگار روزانه پیش از ترک',
    'priceLabel': 'قیمت یک بستهٔ سیگار',
    'perPackLabel': 'تعداد سیگار در هر بسته',
    'explainBaseline':
        'این سه عدد فقط برآوردهای صفحه را شکل می‌دهند. هر وقت خواستید '
        'درستشان کنید؛ روزهایی که نگه داشته‌اید از آنِ خودتان است.',
    'smokeFreeFor': '{days} روز بدون سیگار',
    'smokeFreeToday': 'از امروز بدون سیگار',
    'cigarettesAvoided': 'حدود {n} سیگار نکشیده شده',
    'moneySaved': 'حدود {money} صرفه‌جویی',
    'estimateNote':
        'بر پایهٔ {perDay} در روز، {price} برای هر بستهٔ  {perPack}تایی. '
        'برآورد است، نه وعده.',
    'supportDay0':
        'اولین ساعت‌ها سخت‌ترین‌هاست. همین که اینجایید خودش مهم است.',
    'supportDay1': 'یک روز تازه در مسیرتان. قدم‌به‌قدم ادامه بدهید.',
    'supportDays': 'هر روز، پیروزی آرام خودش است.',
    'supportWeek': 'یک هفته شد. آرام ادامه بدهید.',
    'supportMonth': 'چند هفته‌ای که پیش رفته. حالا الگوی خودتان را می‌شناسید.',
    'supportYear':
        'تلاشتان در این مدت ارزشمند است. با سرعت خودتان ادامه بدهید.',
    'logCraving': 'ثبت هوس',
    'cravingTitle': 'یک هوس',
    'intensity': 'چقدر محسوس بود؟',
    'intensityLow': 'سبک',
    'intensityMedium': 'قوی',
    'intensityHigh': 'غالب',
    'triggers': 'چه چیزی آن را راه انداخت؟',
    'coping': 'چه کردید؟',
    'noteLabel': 'یادداشت (اختیاری)',
    'noteHint': 'یک کلمه کافی است',
    'cravingsHeading': 'هوس‌های اخیر',
    'noCravings': 'هنوز هوسی ثبت نشده. هر وقت لازم بود، یکی ثبت کنید.',
    'patternHeading': 'الگو',
    'patternTop': 'بیشترین راه‌انداز: {name} ({n} بار)',
    'patternNone': 'هنوز الگویی نیست — هوس‌های ثبت‌شده کم است.',
    'todayWord': 'امروز',
    'yesterdayWord': 'دیروز',
    'daysAgoWord': '{n} روز پیش',
    'recordLapse': 'سیگار کشیدم',
    'more': 'بیشتر',
    'trigger_stress': 'استرس',
    'trigger_boredom': 'بی‌کاری',
    'trigger_coffee': 'قهوه یا چای',
    'trigger_afterMeal': 'بعد از غذا',
    'trigger_social': 'کنار سیگاری‌ها',
    'trigger_driving': 'رانندگی',
    'trigger_tired': 'خستگی',
    'trigger_emotion': 'یک حال‌وهوا',
    'trigger_other': 'چیز دیگر',
    'coping_water': 'آب خوردم',
    'coping_deepBreath': 'نفس عمیق',
    'coping_walk': 'قدم زدم',
    'coping_gum': 'آدامس',
    'coping_waited': 'صبر کردم تا گذشت',
    'coping_distraction': 'سرم را گرم کردم',
    'lapseTitle': 'یک لغزش ثبت شود؟',
    'lapseBody':
        'این کار تلاش فعلی را تمام می‌کند و در تاریخچه می‌ماند. '
        'می‌توانید از امروز با همان تنظیمات دوباره شروع کنید — چیزی پاک نمی‌شود.',
    'lapseJust': 'فقط ثبتش کن',
    'lapseRestart': 'ثبت و شروع تازه از امروز',
    'newAttemptStarted': 'تلاش تازه از امروز شروع شد',
    'lapseRecorded': 'لغزش ثبت شد',
    'noActive': 'تلاشی در جریان نیست.',
    'startButton': 'شروعِ بدون سیگار',
    'historyHeading': 'تلاش‌های پیشین',
    'attemptLine': '{days} روز دوام آورد',
    'editBaseline': 'ویرایش مبنای برآورد',
    'cravingDeleted': 'هوس حذف شد',
    'deleteCraving': 'حذف',
    'numberInvalid': 'آن را به شکل عدد ساده بنویسید',
    'daysInvalid': 'روز نمی‌تواند منفی باشد',
    'priceInvalid': 'قیمت نمی‌تواند منفی باشد',
  },
);
