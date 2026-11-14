import 'package:nex_client/modules/module_api.dart';

/// Every word this module shows, in both languages. The module kit's gate
/// checks that the two maps hold the same keys and that none is empty.
///
/// Persian is written as a Persian reader would say it, not translated word
/// for word: «واحد» for a unit of measure (what people say; «یکا» is the
/// Academy's word), «ذرع» for the cloth measure, and
/// numbers arriving as `{placeholders}` so `NexModuleStrings` can set them in
/// Persian digits.
const converterStrings = NexModuleStrings(
  en: {
    'title': 'Converter',
    'tagline': 'Dates, units and sizes — offline',
    'about':
        'Move a date between the solar, Gregorian and lunar calendars, a '
        'measure between metric and imperial units, or a size between the '
        'systems a shop uses — with the measurement behind every number. '
        'Everything is worked out on the phone. No currency: rates change '
        'every day and this module never goes online.',
    'point1': 'Three calendars at once',
    'point2': 'Metric, imperial and Iranian units',
    'point3': 'Clothing, shoe and ring sizes',
    'point4': 'Nothing sent anywhere',

    'tabDates': 'Dates',
    'tabUnits': 'Units',
    'tabSizes': 'Sizes',
    'more': 'More',

    // ------------------------------------------------------------- dates
    'calSolar': 'Solar Hijri',
    'calGregorian': 'Gregorian',
    'calLunar': 'Lunar Hijri',
    'calSolarShort': 'Solar',
    'calGregorianShort': 'Gregorian',
    'calLunarShort': 'Lunar',
    'dateInCalendar': 'Date in',
    'dateFieldLabel': 'Date (year/month/day)',
    'dateFieldHint': '1405/08/22',
    'dateInvalid': 'Write the date as year/month/day.',
    'dateOutOfRange':
        'That date is outside the years this module covers (1900 to 2100).',
    'today': 'Today',
    'pickDay': 'Pick from the calendar',
    'weekday1': 'Monday',
    'weekday2': 'Tuesday',
    'weekday3': 'Wednesday',
    'weekday4': 'Thursday',
    'weekday5': 'Friday',
    'weekday6': 'Saturday',
    'weekday7': 'Sunday',
    'lunarMonth1': 'Muharram',
    'lunarMonth2': 'Safar',
    'lunarMonth3': 'Rabi I',
    'lunarMonth4': 'Rabi II',
    'lunarMonth5': 'Jumada I',
    'lunarMonth6': 'Jumada II',
    'lunarMonth7': 'Rajab',
    'lunarMonth8': "Sha'ban",
    'lunarMonth9': 'Ramadan',
    'lunarMonth10': 'Shawwal',
    'lunarMonth11': "Dhu al-Qi'dah",
    'lunarMonth12': 'Dhu al-Hijjah',
    'lunarNote':
        'Lunar dates are calculated here, so they can differ by a day from '
        'the official announcement.',
    'allCalendars': 'All three calendars',
    'solarShort': 'Solar · {date}',
    'gregorianShort': 'Gregorian · {date}',
    'lunarShort': 'Lunar · {date}',
    'daysBetween': 'Days between',
    'daysBetweenTitle': 'Days between two dates',
    'daysBetweenFrom': 'From',
    'daysBetweenTo': 'To',
    'daysBetweenResult': '{n} days',
    'daysEarlier': '{n} days earlier',
    'daysSameDay': 'The same day.',
    'daysBetweenNote':
        'Whole days from the first date to the second — the day after '
        'tomorrow is two.',
    'addDays': 'Add or subtract days',
    'addDaysTitle': 'A date, plus or minus days',
    'addDaysStart': 'Start date',
    'addDaysCount': 'Days (+ or −)',
    'addDaysResult': 'Result',
    'addDaysNote': 'A positive number adds days, a negative one takes them.',
    'daysInvalid': 'Write how many days.',

    // ------------------------------------------------------------- units
    'catLength': 'Length',
    'catMass': 'Weight',
    'catVolume': 'Volume',
    'catTemperature': 'Temperature',
    'catArea': 'Area',
    'catSpeed': 'Speed',
    'fromLabel': 'From',
    'toLabel': 'To',
    'valueLabel': 'Value',
    'swapLabel': 'Swap',
    'unitInvalid': 'Write a number.',
    'underAbsoluteZero': 'That is below absolute zero.',
    'unitBaseLine': '1 {from} = {factor} {to}',

    'unit_mm': 'Millimetre',
    'unit_cm': 'Centimetre',
    'unit_m': 'Metre',
    'unit_km': 'Kilometre',
    'unit_inch': 'Inch',
    'unit_foot': 'Foot',
    'unit_yard': 'Yard',
    'unit_mile': 'Mile',
    'unit_nauticalMile': 'Nautical mile',
    'unit_zar': 'Zar (gaz)',
    'unit_gazShahi': 'Shah gaz',
    'unit_g': 'Gram',
    'unit_kg': 'Kilogram',
    'unit_tonne': 'Tonne',
    'unit_ounce': 'Ounce',
    'unit_pound': 'Pound',
    'unit_mesghal': 'Mesghal',
    'unit_sir': 'Sir',
    'unit_manTabriz': 'Tabriz man',
    'unit_kharvar': 'Kharvar',
    'unit_ml': 'Millilitre',
    'unit_l': 'Litre',
    'unit_usGallon': 'US gallon',
    'unit_ukGallon': 'UK gallon',
    'unit_usCup': 'US cup',
    'unit_usFluidOunce': 'US fluid ounce',
    'unit_celsius': 'Celsius',
    'unit_fahrenheit': 'Fahrenheit',
    'unit_kelvin': 'Kelvin',
    'unit_m2': 'Square metre',
    'unit_hectare': 'Hectare',
    'unit_acre': 'Acre',
    'unit_ft2': 'Square foot',
    'unit_ms': 'Metres per second',
    'unit_kmh': 'Kilometres per hour',
    'unit_mph': 'Miles per hour',
    'unit_knot': 'Knot',
    'approxSuffix': ' (approx.)',
    'unitNote_zar':
        'The zar is taken as 104 cm, the short zar of Tehran and Fars. Other '
        'cities used 95 to 112 cm for the same word.',
    'unitNote_gazShahi':
        'The shah gaz of Tabriz, 112 cm, was the cloth measure of that '
        'bazaar.',
    'unitNote_mesghal':
        'The mesghal is taken as 4.608 g — the gold-sellers\' mesghal of 24 '
        'nokhud. The religious mesghal is 3.456 g.',
    'unitNote_sir':
        'The sir is taken as 75 g. Older tables also give 73.7 g and 74.2 g.',
    'unitNote_manTabriz':
        'The Tabriz man is 3 kg, forty sir. Other cities used the same word '
        'for 1.3 to 12 kg.',
    'unitNote_kharvar':
        'The kharvar is taken as a hundred Tabriz man, 300 kg. In the '
        'villages it ranged from 100 to 212 kg.',

    // ------------------------------------------------------------- sizes
    'chartLabel': 'Chart',
    'chartWomenTops': "Women's tops",
    'chartWomenTrousers': "Women's trousers",
    'chartMenTops': "Men's tops",
    'chartMenTrousers': "Men's trousers",
    'chartWomenShoes': "Women's shoes",
    'chartMenShoes': "Men's shoes",
    'chartChildrenShoes': "Children's shoes",
    'chartRings': 'Rings',
    'sysEu': 'EU',
    'sysUk': 'UK',
    'sysUs': 'US',
    'sysIran': 'Iran',
    'sysFoot': 'Foot length',
    'sysIso': 'Circumference',
    'measureBust': 'Bust',
    'measureWaist': 'Waist',
    'measureHip': 'Hip',
    'measureChest': 'Chest',
    'measureFoot': 'Foot length',
    'measureCircumference': 'Inner circumference',
    'measureDiameter': 'Inner diameter',
    'sizeSystemLabel': 'Your size is in',
    'sizeLabel': 'Size',
    'sizeAllSystems': 'Every system',
    'sizeNote':
        'Size charts differ between brands. The measurement beside each size '
        'is the part you can trust.',
    'chartNoteClothingIran':
        'Iranian shops sell clothes by the European number.',
    'chartNoteMenUkUs':
        'British and American jacket numbers are the chest in inches.',
    'chartNoteTrouserInches':
        'British and American trouser numbers are the waist in inches.',
    'chartNoteShoes':
        'These are ISO sizes from the bare foot. Shop labels often run a '
        'size larger; the Iran column is the label in Iranian shops.',
    'chartNoteChildren':
        'Children\'s shoes: British and American numbering restarts at 1 '
        'after size 13, so read the foot length.',
    'chartNoteRings':
        'Rings: each British letter adds 1.25 mm of inner circumference; '
        'Iranian jewellers use the circumference less five.',
    'cmUnit': 'cm',
    'mmUnit': 'mm',

    // ------------------------------------------------------------ shared
    'copy': 'Copy',
    'copied': 'Copied.',
    'favorite': 'Star',
    'unfavorite': 'Remove star',
    'restore': 'Show again',
    'remove': 'Remove',
    'recentTitle': 'Recent',
    'favoritesTitle': 'Starred',
    'emptyRecent': 'Conversions you make are kept here.',
    'loadError': 'Could not load your conversions.',
    'retry': 'Retry',
    'deleted': 'Deleted',
    'undo': 'Undo',
    'close': 'Close',
  },
  fa: {
    'title': 'تبدیل‌گر',
    'tagline': 'تاریخ، واحد و سایز — بدون اینترنت',
    'about':
        'تاریخ را بین تقویم شمسی، میلادی و قمری جابه‌جا کنید، اندازه را '
        'بین واحدهای متری و انگلیسی، یا سایز را بین سیستم‌هایی که فروشگاه‌ها '
        'به کار می‌برند — با اندازه‌ای که پشت هر عدد است. همه‌چیز روی خود '
        'گوشی حساب می‌شود. ارز تبدیل نمی‌شود: نرخ‌ها هر روز عوض می‌شوند و '
        'این ابزار هیچ‌وقت به اینترنت وصل نمی‌شود.',
    'point1': 'سه تقویم با هم',
    'point2': 'واحدهای متری، انگلیسی و ایرانی',
    'point3': 'سایز لباس، کفش و انگشتر',
    'point4': 'چیزی به جایی فرستاده نمی‌شود',

    'tabDates': 'تاریخ',
    'tabUnits': 'واحدها',
    'tabSizes': 'سایزها',
    'more': 'بیشتر',

    // ------------------------------------------------------------- dates
    'calSolar': 'شمسی',
    'calGregorian': 'میلادی',
    'calLunar': 'قمری',
    'calSolarShort': 'شمسی',
    'calGregorianShort': 'میلادی',
    'calLunarShort': 'قمری',
    'dateInCalendar': 'تاریخ در تقویم',
    'dateFieldLabel': 'تاریخ (سال/ماه/روز)',
    'dateFieldHint': '۱۴۰۵/۰۸/۲۲',
    'dateInvalid': 'تاریخ را به شکل سال/ماه/روز بنویسید.',
    'dateOutOfRange': 'این تاریخ بیرون از سال‌هایی است که این ابزار پوشش می‌دهد (۱۹۰۰ تا ۲۱۰۰).',
    'today': 'امروز',
    'pickDay': 'انتخاب از تقویم',
    'weekday1': 'دوشنبه',
    'weekday2': 'سه‌شنبه',
    'weekday3': 'چهارشنبه',
    'weekday4': 'پنج‌شنبه',
    'weekday5': 'جمعه',
    'weekday6': 'شنبه',
    'weekday7': 'یکشنبه',
    'lunarMonth1': 'محرم',
    'lunarMonth2': 'صفر',
    'lunarMonth3': 'ربیع‌الاول',
    'lunarMonth4': 'ربیع‌الثانی',
    'lunarMonth5': 'جمادی‌الاول',
    'lunarMonth6': 'جمادی‌الثانی',
    'lunarMonth7': 'رجب',
    'lunarMonth8': 'شعبان',
    'lunarMonth9': 'رمضان',
    'lunarMonth10': 'شوال',
    'lunarMonth11': 'ذی‌القعده',
    'lunarMonth12': 'ذی‌الحجه',
    'lunarNote':
        'تاریخ قمری اینجا محاسبه می‌شود و ممکن است یک روز با اعلام رسمی '
        'تفاوت داشته باشد.',
    'allCalendars': 'هر سه تقویم',
    'solarShort': 'شمسی · {date}',
    'gregorianShort': 'میلادی · {date}',
    'lunarShort': 'قمری · {date}',
    'daysBetween': 'فاصلهٔ دو تاریخ',
    'daysBetweenTitle': 'فاصلهٔ دو تاریخ',
    'daysBetweenFrom': 'از تاریخ',
    'daysBetweenTo': 'تا تاریخ',
    'daysBetweenResult': '{n} روز',
    'daysEarlier': '{n} روز پیش‌تر',
    'daysSameDay': 'همان روز است.',
    'daysBetweenNote':
        'شمار روزهای کامل از تاریخ اول تا تاریخ دوم — پس‌فردا دو روز است.',
    'addDays': 'جمع و تفریق روز',
    'addDaysTitle': 'یک تاریخ، به‌اضافهٔ چند روز',
    'addDaysStart': 'تاریخ شروع',
    'addDaysCount': 'روز (مثبت یا منفی)',
    'addDaysResult': 'نتیجه',
    'addDaysNote': 'عدد مثبت روز اضافه می‌کند و عدد منفی کم.',
    'daysInvalid': 'بنویسید چند روز.',

    // ------------------------------------------------------------- units
    'catLength': 'طول',
    'catMass': 'وزن',
    'catVolume': 'حجم',
    'catTemperature': 'دما',
    'catArea': 'مساحت',
    'catSpeed': 'سرعت',
    'fromLabel': 'از',
    'toLabel': 'به',
    'valueLabel': 'مقدار',
    'swapLabel': 'جابه‌جایی',
    'unitInvalid': 'یک عدد بنویسید.',
    'underAbsoluteZero': 'این مقدار زیر صفر مطلق است.',
    'unitBaseLine': '۱ {from} = {factor} {to}',

    'unit_mm': 'میلی‌متر',
    'unit_cm': 'سانتی‌متر',
    'unit_m': 'متر',
    'unit_km': 'کیلومتر',
    'unit_inch': 'اینچ',
    'unit_foot': 'فوت',
    'unit_yard': 'یارد',
    'unit_mile': 'مایل',
    'unit_nauticalMile': 'مایل دریایی',
    'unit_zar': 'ذرع (گز)',
    'unit_gazShahi': 'گز شاهی',
    'unit_g': 'گرم',
    'unit_kg': 'کیلوگرم',
    'unit_tonne': 'تن',
    'unit_ounce': 'اونس',
    'unit_pound': 'پوند',
    'unit_mesghal': 'مثقال',
    'unit_sir': 'سیر',
    'unit_manTabriz': 'من تبریز',
    'unit_kharvar': 'خروار',
    'unit_ml': 'میلی‌لیتر',
    'unit_l': 'لیتر',
    'unit_usGallon': 'گالن آمریکایی',
    'unit_ukGallon': 'گالن انگلیسی',
    'unit_usCup': 'پیمانهٔ آمریکایی',
    'unit_usFluidOunce': 'اونس مایع آمریکایی',
    'unit_celsius': 'سلسیوس',
    'unit_fahrenheit': 'فارنهایت',
    'unit_kelvin': 'کلوین',
    'unit_m2': 'متر مربع',
    'unit_hectare': 'هکتار',
    'unit_acre': 'ایکر',
    'unit_ft2': 'فوت مربع',
    'unit_ms': 'متر بر ثانیه',
    'unit_kmh': 'کیلومتر بر ساعت',
    'unit_mph': 'مایل بر ساعت',
    'unit_knot': 'گره',
    'approxSuffix': ' (تقریبی)',
    'unitNote_zar':
        'ذرع ۱۰۴ سانتی‌متر گرفته شده — ذرع مقصر، که در تهران و فارس رایج '
        'بود. در شهرهای دیگر همین واژه از ۹۵ تا ۱۱۲ سانتی‌متر بود.',
    'unitNote_gazShahi':
        'گز شاهی تبریز، ۱۱۲ سانتی‌متر، واحد پارچه‌فروشی‌های آن بازار بود.',
    'unitNote_mesghal':
        'مثقال ۴٫۶۰۸ گرم گرفته شده — مثقال صیرفی بازار طلا، برابر ۲۴ نخود. '
        'مثقال شرعی ۳٫۴۵۶ گرم است.',
    'unitNote_sir': 'سیر ۷۵ گرم گرفته شده. در جدول‌های قدیمی‌تر ۷۳٫۷ و ۷۴٫۲ گرم هم آمده است.',
    'unitNote_manTabriz':
        'من تبریز ۳ کیلوگرم است، چهل سیر. در شهرهای دیگر همین واژه از ۱٫۳ تا '
        '۱۲ کیلوگرم را می‌رساند.',
    'unitNote_kharvar':
        'خروار صد من تبریز گرفته شده، یعنی ۳۰۰ کیلوگرم. در روستاها از ۱۰۰ تا '
        '۲۱۲ کیلوگرم هم بود.',

    // ------------------------------------------------------------- sizes
    'chartLabel': 'جدول',
    'chartWomenTops': 'بالاتنهٔ زنانه',
    'chartWomenTrousers': 'شلوار زنانه',
    'chartMenTops': 'بالاتنهٔ مردانه',
    'chartMenTrousers': 'شلوار مردانه',
    'chartWomenShoes': 'کفش زنانه',
    'chartMenShoes': 'کفش مردانه',
    'chartChildrenShoes': 'کفش بچگانه',
    'chartRings': 'انگشتر',
    'sysEu': 'اروپا',
    'sysUk': 'انگلیس',
    'sysUs': 'آمریکا',
    'sysIran': 'ایران',
    'sysFoot': 'طول پا',
    'sysIso': 'محیط',
    'measureBust': 'دور سینه',
    'measureWaist': 'دور کمر',
    'measureHip': 'دور باسن',
    'measureChest': 'دور سینه',
    'measureFoot': 'طول پا',
    'measureCircumference': 'محیط داخلی',
    'measureDiameter': 'قطر داخلی',
    'sizeSystemLabel': 'سایزتان در',
    'sizeLabel': 'سایز',
    'sizeAllSystems': 'همهٔ سیستم‌ها',
    'sizeNote':
        'جدول سایز هر برند با برند دیگر فرق می‌کند. اندازه‌ای که کنار هر '
        'سایز می‌بینید قابل اعتمادتر است.',
    'chartNoteClothingIran':
        'فروشگاه‌های ایران لباس را با شمارهٔ اروپایی می‌فروشند.',
    'chartNoteMenUkUs': 'شمارهٔ کت انگلیسی و آمریکایی، دور سینه به اینچ است.',
    'chartNoteTrouserInches':
        'شمارهٔ شلوار انگلیسی و آمریکایی، دور کمر به اینچ است.',
    'chartNoteShoes':
        'این‌ها سایز استاندارد بر پایهٔ طول پای برهنه است. برچسب فروشگاه‌ها '
        'معمولاً یک شماره بزرگ‌تر است؛ ستون ایران همان برچسب فروشگاه‌های ایران است.',
    'chartNoteChildren':
        'کفش بچگانه: شمارهٔ انگلیسی و آمریکایی بعد از ۱۳ دوباره از ۱ شروع '
        'می‌شود، پس طول پا را بخوانید.',
    'chartNoteRings':
        'انگشتر: هر حرف انگلیسی ۱٫۲۵ میلی‌متر به محیط داخلی اضافه می‌کند؛ '
        'زرگرهای ایران محیط داخلی منهای پنج را سایز می‌گویند.',
    'cmUnit': 'سانتی‌متر',
    'mmUnit': 'میلی‌متر',

    // ------------------------------------------------------------ shared
    'copy': 'کپی',
    'copied': 'کپی شد.',
    'favorite': 'ستاره',
    'unfavorite': 'برداشتن ستاره',
    'restore': 'نمایش دوباره',
    'remove': 'برداشتن',
    'recentTitle': 'اخیر',
    'favoritesTitle': 'ستاره‌دار',
    'emptyRecent': 'تبدیل‌هایی که انجام می‌دهید اینجا می‌ماند.',
    'loadError': 'تبدیل‌ها خوانده نشد.',
    'retry': 'تلاش دوباره',
    'deleted': 'حذف شد',
    'undo': 'بازگردانی',
    'close': 'بستن',
  },
);
