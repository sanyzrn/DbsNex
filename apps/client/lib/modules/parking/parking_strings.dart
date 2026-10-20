import 'package:nex_client/modules/module_api.dart';

/// Where I parked — the words it shows, in both languages, kept inside the
/// module as `NexModuleStrings` requires. Numbers passed as arguments come
/// out in Persian digits on the Persian side.
const parkingStrings = NexModuleStrings(
  en: {
    'dateHint': 'YYYY/MM/DD',
    'keepDraft': 'Keep draft & close',
    'undoFailed':
        'Could not undo. A later change may conflict; retry after checking the record.',
    'loadFailed': 'Could not load your records. Retry before editing.',
    'retry': 'Retry',
    'unknownDate': 'Date unavailable',
    'title': 'Where I parked',
    'tagline': 'One tap saves where the car is',
    'about':
        'Remember where you parked with your own words: the place, the floor, '
        'the pillar and a note. The location is typed by you — no GPS, no map, '
        'no photo — and nothing leaves this phone.',
    'point1': 'Typed by you, honestly',
    'point2': 'One open parking per car',
    'point3': 'History with Undo',
    'point4': 'Stays on this phone',

    // The main screen.
    'history': 'Past parking',
    'recentPlaces': 'Places you use',
    'searchHint': 'Search your parking',
    'searchHistory': 'Recent searches',
    'parkedHere': 'Parked here',
    'foundMyCar': 'Found my car',
    'elapsed': 'Parked for {duration}',
    'expiresIn': 'Ends in {duration}',
    'mayHaveExpired': 'May have ended {duration} ago',
    'defaultVehicle': 'The car',
    'floorShort': 'Floor {value}',
    'emptyMessage':
        'When you leave the car, tap “Parked here” and write where it is.',

    // The editor.
    'newParking': 'Parked here',
    'editParking': 'Edit parking',
    'vehicle': 'Vehicle',
    'vehicleHint': 'A name you know the car by (optional)',
    'place': 'Where is it?',
    'placeHint': 'Street, mall, area…',
    'placeRequired': 'Write where you parked.',
    'floor': 'Floor',
    'floorHint': '−2, 1…',
    'spot': 'Section, pillar or spot',
    'spotHint': 'B12, blue zone…',
    'landmark': 'A landmark around it',
    'landmarkHint': '“Next to the lifts”, “by the entrance”…',
    'coordinates': 'Coordinates (typed by you)',
    'coordinatesNote':
        'Only if you know them. Nothing on this phone finds your position.',
    'latitude': 'Latitude',
    'longitude': 'Longitude',
    'badExpiry': 'The date or the time is not written right',
    'badLatitude': 'Latitude is between −90 and 90',
    'badLongitude': 'Longitude is between −180 and 180',
    'expiry': 'Paid time (optional)',
    'expiryNote':
        'Written by you. While this screen is open it counts down. For an '
        'alert that reaches you after closing, set a reminder on the '
        'parking.',
    'expiryDate': 'Date',
    'expiryTime': 'Time (24h, HH:MM)',
    'today': 'Today',
    'clearTime': 'Clear',
    'save': 'Save parking',

    // The vehicle question.
    'stillParkedTitle': 'Still parked?',
    'stillParkedBody':
        '“{vehicle}” is still marked as parked. Close that earlier parking '
        'now, or keep it open?',
    'closeEarlier': 'Close it',
    'keepEarlier': 'Keep it open',

    // Leaving without saving.
    'discardTitle': 'Leave without saving?',
    'discardBody': 'What you have written so far will be lost.',
    'discard': 'Leave',
    'keepEditing': 'Keep writing',

    // Deleting.
    'deleteParking': 'Delete this parking?',
    'deleteBody':
        'This entry leaves the list. You can undo it for a few seconds.',
    'deletedOne': 'Parking deleted',
    'clearedHistory': 'History cleared',
    'clearHistory': 'Clear past parking',
    'clearHistoryTitle': 'Clear all past parking?',
    'clearHistoryBody':
        'Every closed parking goes. You can undo this for a few seconds.',

    // Failures.
    'saveFailed': 'Could not save. Nothing was lost — try again.',
    'deleteFailed': 'Could not delete. Try again.',

    // The details page.
    'detailsTitle': 'Parking',
    'vehicleLabel': 'Vehicle',
    'placeLabel': 'Place',
    'floorLabel': 'Floor',
    'spotLabel': 'Section / spot',
    'landmarkLabel': 'Landmark',
    'coordinatesLabel': 'Coordinates',
    'expiryLabel': 'Ends',
    'startedLabel': 'Started',
    'foundLabel': 'Found',
    'durationLabel': 'Duration',
    'noValue': '—',

    // Dates and durations.
    'minutes': '{count} min',
    'hours': '{count} h',
    'days': '{count} d',
    'hoursMinutes': '{h} h {m} min',
    'daysHours': '{d} d {h} h',
    'justNow': 'today',

    // A search with nothing to show.
    'noMatches': 'Nothing matches “{query}”.',

    // The opt-in device reminder for an open parking.
    'reminderNote':
        'A device alert, set by you — for the end of paid time or when you '
        'next need the car. It goes when the parking does.',
  },
  fa: {
    'dateHint': 'سال/ماه/روز',
    'keepDraft': 'نگهداری پیش‌نویس و بستن',
    'undoFailed':
        'بازگردانی انجام نشد؛ شاید اطلاعات بعداً تغییر کرده است. رکورد را بررسی کنید.',
    'loadFailed': 'خواندن اطلاعات انجام نشد. پیش از ویرایش دوباره تلاش کنید.',
    'retry': 'تلاش دوباره',
    'unknownDate': 'تاریخ نامشخص',
    'title': 'جای پارک',
    'tagline': 'با یک لمس جای ماشین یادت می‌ماند',
    'about':
        'جای پارک را با حرف‌های خودتان ذخیره کنید: آدرس، طبقه، ستون و یک '
        'یادداشت. مکان را خودتان می‌نویسید — نه موقعیت‌یابی، نه نقشه، نه عکس — '
        'و هیچ چیزی از این گوشی بیرون نمی‌رود.',
    'point1': 'ثبت دستی و درست',
    'point2': 'یک پارکِ باز برای هر ماشین',
    'point3': 'تاریخچه با امکان بازگردانی',
    'point4': 'همه‌چیز روی همین گوشی',

    // صفحهٔ اصلی.
    'history': 'پارک‌های گذشته',
    'recentPlaces': 'جاهایی که پارک می‌کنید',
    'searchHint': 'جست‌وجوی پارک‌ها',
    'searchHistory': 'جست‌وجوهای اخیر',
    'parkedHere': 'اینجا پارک کردم',
    'foundMyCar': 'ماشین را پیدا کردم',
    'elapsed': '{duration} پارک است',
    'expiresIn': '{duration} دیگر تمام می‌شود',
    'mayHaveExpired': 'ممکن است {duration} پیش تمام شده باشد',
    'defaultVehicle': 'ماشین',
    'floorShort': 'طبقهٔ {value}',
    'emptyMessage':
        'وقتی از ماشین پیاده شدید، «اینجا پارک کردم» را بزنید و بنویسید کجا است.',

    // ویرایشگر.
    'newParking': 'اینجا پارک کردم',
    'editParking': 'ویرایش پارک',
    'vehicle': 'خودرو',
    'vehicleHint': 'نامی که این ماشین را با آن می‌شناسید (اختیاری)',
    'place': 'کجا پارک است؟',
    'placeHint': 'خیابان، مراکز خرید، محله…',
    'placeRequired': 'بنویسید کجا پارک کردید.',
    'floor': 'طبقه',
    'floorHint': '−۲، ۱…',
    'spot': 'ردیف، ستون یا پلاک',
    'spotHint': 'ب۱۲، منطقهٔ آبی…',
    'landmark': 'نشانهٔ اطراف',
    'landmarkHint': '«کنار آسانسورها»، «روبه‌روی ورودی»…',
    'coordinates': 'مختصات (دستی)',
    'coordinatesNote':
        'فقط اگر می‌دانید. هیچ چیزی روی این گوشی موقعیت شما را پیدا نمی‌کند.',
    'latitude': 'عرض جغرافیایی',
    'longitude': 'طول جغرافیایی',
    'badExpiry': 'تاریخ یا ساعت درست نوشته نشده است',
    'badLatitude': 'عرض جغرافیایی بین −۹۰ و ۹۰ است',
    'badLongitude': 'طول جغرافیایی بین −۱۸۰ و ۱۸۰ است',
    'expiry': 'زمان پرداختی (اختیاری)',
    'expiryNote':
        'خودتان می‌نویسید. تا وقتی این صفحه باز است شمارش می‌کند. برای هشداری '
        'که پس از بستن هم می‌رسد، روی پارک یادآوری بگذارید.',
    'expiryDate': 'تاریخ',
    'expiryTime': 'ساعت (۲۴ ساعته، ساعت:دقیقه)',
    'today': 'امروز',
    'clearTime': 'پاک کردن',
    'save': 'ثبت پارک',

    // پرسش خودروی تکراری.
    'stillParkedTitle': 'هنوز پارک است؟',
    'stillParkedBody':
        '«{vehicle}» هنوز در حالت پارک است. آن پارک قبلی را الان ببندیم یا '
        'باز بماند؟',
    'closeEarlier': 'ببند',
    'keepEarlier': 'باز بماند',

    // خروج بدون ذخیره.
    'discardTitle': 'بدون ذخیره خارج شویم؟',
    'discardBody': 'چیزی که تا حالا نوشته‌اید از بین می‌رود.',
    'discard': 'خروج',
    'keepEditing': 'ادامه بدهم',

    // حذف.
    'deleteParking': 'این پارک حذف شود؟',
    'deleteBody': 'این مورد از فهرست می‌رود. چند ثانیه می‌توانید برگردانید.',
    'deletedOne': 'پارک حذف شد',
    'clearedHistory': 'تاریخچه پاک شد',
    'clearHistory': 'پاک‌کردن پارک‌های گذشته',
    'clearHistoryTitle': 'همهٔ پارک‌های گذشته پاک شود؟',
    'clearHistoryBody':
        'هر پارکِ بسته‌شده‌ای می‌رود. چند ثانیه می‌توانید برگردانید.',

    // خطاها.
    'saveFailed': 'ذخیره نشد. چیزی از دست نرفت — دوباره تلاش کنید.',
    'deleteFailed': 'حذف نشد. دوباره تلاش کنید.',

    // صفحهٔ جزئیات.
    'detailsTitle': 'پارک',
    'vehicleLabel': 'خودرو',
    'placeLabel': 'مکان',
    'floorLabel': 'طبقه',
    'spotLabel': 'ردیف / پلاک',
    'landmarkLabel': 'نشانه',
    'coordinatesLabel': 'مختصات',
    'expiryLabel': 'پایان',
    'startedLabel': 'شروع',
    'foundLabel': 'پیدا شد',
    'durationLabel': 'مدت',
    'noValue': '—',

    // تاریخ‌ها و مدت‌ها.
    'minutes': '{count} دقیقه',
    'hours': '{count} ساعت',
    'days': '{count} روز',
    'hoursMinutes': '{h} ساعت و {m} دقیقه',
    'daysHours': '{d} روز و {h} ساعت',
    'justNow': 'امروز',

    // جست‌وجویی که چیزی پیدا نکرد.
    'noMatches': 'چیزی با «{query}» مطابقت ندارد.',

    // یادآور گوشیِ اختیاریِ یک پارکِ باز.
    'reminderNote':
        'هشدار گوشی، خودتان تنظیمش می‌کنید — برای پایان زمان پرداختی یا وقتی '
        'دوباره ماشین را لازم دارید. با رفتن پارک، آن هم می‌رود.',
  },
);
