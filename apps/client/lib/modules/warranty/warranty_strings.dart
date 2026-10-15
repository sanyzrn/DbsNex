import 'package:nex_client/modules/module_api.dart';

/// Warranties — the words it shows, in both languages, kept inside the
/// module as `NexModuleStrings` requires. Numbers passed as arguments come
/// out in Persian digits on the Persian side.
const warrantyStrings = NexModuleStrings(
  en: {
    'coverageRequired':
        'Enter a valid Gregorian end date or 1–{months} months ending by {year}.',
    'dateHint': 'YYYY/MM/DD',
    'unknownLog': 'Unknown record type',
    'monthCount': '{count} months',
    'keepDraft': 'Keep draft & close',
    'undoFailed':
        'Could not undo. A later change may conflict; retry after checking the record.',
    'loadFailed': 'Could not load your records. Retry before editing.',
    'retry': 'Retry',
    'unknownDate': 'Date unavailable',
    'title': 'Warranties',
    'tagline': 'What you bought, and how long it is covered',
    'about':
        'The products you buy, with their coverage period and the receipt '
        'typed in as text. It does not photograph, verify or remind — and '
        'it never promises what a merchant will accept.',
    'point1': 'Coverage you wrote yourself',
    'point2': 'Active, expiring, expired — on view',
    'point3': 'Claims kept as dated notes',
    'point4': 'Nothing leaves this phone',

    // The list.
    'emptyMessage': 'Add your first purchase and its coverage.',
    'add': 'Add a purchase',
    'active': 'Covered',
    'expiring': 'Ending soon',
    'expired': 'Expired',
    'archived': 'Archived',
    'showArchived': 'Show archived',
    'hideArchived': 'Hide archived',
    'unarchive': 'Back on the list',
    'searchHint': 'Search by product or brand',
    'sortSoonest': 'Sort by soonest end',
    'sortNewest': 'Back to newest',
    'daysLeft': '{count} days left',
    'oneDayLeft': '1 day left',
    'endsToday': 'Ends today',
    'expiredDaysAgo': 'Ended {count} days ago',
    'noResults': 'Nothing matches.',

    // The editor.
    'editPurchase': 'Edit purchase',
    'product': 'Product',
    'productHint': 'A kettle, a phone…',
    'productRequired': 'Write what the product is.',
    'category': 'Category',
    'brand': 'Brand',
    'model': 'Model',
    'serial': 'Serial / invoice ID',
    'serialHint': 'From the box or the receipt',
    'merchant': 'Merchant',
    'purchaseDate': 'Purchase date (Gregorian)',
    'purchaseRequired': 'Use a valid Gregorian purchase date.',
    'today': 'Today',
    'coverage': 'Coverage',
    'coverageNote':
        'The shop or maker’s own terms, written by you. Nothing is '
        'guessed from a country-wide default.',
    'durationMonths': 'Duration (months)',
    'durationHint': 'A whole number, 1 or more',
    'endsOn': 'Ends {date}',
    'orEndDate': 'or Gregorian end date',
    'endBeforePurchase': 'The end date is before the purchase.',
    'chooseOne': 'Write a duration or an end date — not both.',
    'coverageType': 'Coverage type',
    'coverageTypeHint': 'Official, shop, extended…',
    'receiptRef': 'Receipt reference',
    'receiptNote':
        'Typed as text — photos and files cannot be attached in this '
        'version.',
    'amount': 'Paid amount',
    'amountHint': 'Whole rials; tomans can have one decimal digit',
    'amountBad': 'Write a whole number, 0 or more',
    'rials': 'rials',
    'tomans': 'tomans',
    'inRials': 'in rials',
    'inTomans': 'in tomans',
    'note': 'Note',
    'noteHint': 'Anything worth remembering',
    'save': 'Save purchase',

    // Details.
    'detailsTitle': 'Warranty',
    'purchasedLabel': 'Purchased',
    'endsLabel': 'Coverage ends',
    'durationLabel': 'Duration',
    'amountLabel': 'Paid',
    'merchantLabel': 'Merchant',
    'serialLabel': 'Serial / invoice',
    'receiptLabel': 'Receipt',
    'typeLabel': 'Coverage',
    'noteLabel': 'Note',
    'noValue': '—',
    'claimsTitle': 'Claims and service',
    'noClaims': 'No claims or service noted yet.',
    'addClaim': 'Add a claim note',
    'addService': 'Add a service note',
    'claimPlaceholder': 'What happened, and what was agreed',
    'claimed': 'Claim',
    'serviced': 'Service',
    'onDate': '{date}',
    'claimRequired': 'Write what the note should say.',

    // Questions and failures.
    'deleteWarranty': 'Delete {name}?',
    'deleteWarrantyBody':
        'The purchase and its claim notes go. You can undo this for a few '
        'seconds.',
    'warrantyDeleted': 'Purchase deleted',
    'warrantyArchived': 'Purchase archived',
    'claimDeleted': 'Claim note deleted',
    'archiveBody':
        'It leaves the list, with its notes kept. You can bring it back '
        'any time.',
    'discardTitle': 'Leave without saving?',
    'discardBody': 'What you have written so far will be lost.',
    'discard': 'Leave',
    'keepWriting': 'Keep writing',
    'saveFailed': 'Could not save. Nothing was lost — try again.',
    'deleteFailed': 'Could not delete. Try again.',

    // Dates.
    'ymd': '{y}/{m}/{d}',
  },
  fa: {
    'coverageRequired':
        'پایان میلادی معتبر یا مدت ۱ تا {months} ماه، حداکثر تا سال {year} وارد کنید.',
    'dateHint': 'سال/ماه/روز',
    'unknownLog': 'نوع گزارش نامشخص',
    'monthCount': '{count} ماه',
    'keepDraft': 'نگهداری پیش‌نویس و بستن',
    'undoFailed':
        'بازگردانی انجام نشد؛ شاید اطلاعات بعداً تغییر کرده است. رکورد را بررسی کنید.',
    'loadFailed': 'خواندن اطلاعات انجام نشد. پیش از ویرایش دوباره تلاش کنید.',
    'retry': 'تلاش دوباره',
    'unknownDate': 'تاریخ نامشخص',
    'title': 'ضمانت‌نامه‌ها',
    'tagline': 'چه خریدید، و تا کِی پوشش دارد',
    'about':
        'چیزهایی که می‌خرید، با مدت گارانتی‌شان و رسیدی که به‌صورت متن '
        'تایپ می‌شود. عکس نمی‌گیرد، تأیید نمی‌کند و یادآوری نمی‌کند — و هرگز '
        'قول نمی‌دهد فروشنده چه چیزی را می‌پذیرد.',
    'point1': 'پوششی که خودتان نوشته‌اید',
    'point2': 'دارای گارانتی، در حال پایان، تمام‌شده — همان لحظهٔ نمایش',
    'point3': 'ادعاها به‌صورت یادداشتِ تاریخ‌دار',
    'point4': 'هیچ چیزی از این گوشی بیرون نمی‌رود',

    // فهرست.
    'emptyMessage': 'اولین خرید و گارانتی‌اش را اضافه کنید.',
    'add': 'افزودن خرید',
    'active': 'دارای گارانتی',
    'expiring': 'نزدیک به پایان',
    'expired': 'تمام‌شده',
    'archived': 'آرشیو',
    'showArchived': 'نمایش آرشیو',
    'hideArchived': 'پنهان‌کردن آرشیو',
    'unarchive': 'بازگشت به فهرست',
    'searchHint': 'جست‌وجو با نام کالا یا برند',
    'sortSoonest': 'مرتب‌سازی از نزدیک‌ترین پایان',
    'sortNewest': 'بازگشت به تازه‌ترین',
    'daysLeft': '{count} روز مانده',
    'oneDayLeft': 'یک روز مانده',
    'endsToday': 'امروز تمام می‌شود',
    'expiredDaysAgo': '{count} روز پیش تمام شد',
    'noResults': 'چیزی پیدا نشد.',

    // ویرایشگر.
    'editPurchase': 'ویرایش خرید',
    'product': 'کالا',
    'productHint': 'کتری، گوشی…',
    'productRequired': 'بنویسید کالا چیست.',
    'category': 'دسته',
    'brand': 'برند',
    'model': 'مدل',
    'serial': 'شماره سریال / فاکتور',
    'serialHint': 'از جعبه یا از رسید',
    'merchant': 'فروشنده',
    'purchaseDate': 'تاریخ خرید (میلادی)',
    'purchaseRequired': 'تاریخ خرید میلادی معتبر بنویسید.',
    'today': 'امروز',
    'coverage': 'گارانتی',
    'coverageNote':
        'شرایط خودِ فروشنده یا سازنده، که خودتان می‌نویسید. هیچ حدس '
        'کشوری‌ای به‌کار نمی‌رود.',
    'durationMonths': 'مدت (ماه)',
    'durationHint': 'یک عدد کامل، یک یا بیشتر',
    'endsOn': 'تا {date}',
    'orEndDate': 'یا تاریخ پایان (میلادی)',
    'endBeforePurchase': 'تاریخ پایان قبل از خرید است.',
    'chooseOne': 'یا مدت را بنویسید یا تاریخ پایان — نه هر دو.',
    'coverageType': 'نوع گارانتی',
    'coverageTypeHint': 'رسمی، فروشگاهی، تمدید…',
    'receiptRef': 'مرجع رسید',
    'receiptNote': 'به‌صورت متن — در این نسخه عکس و فایل پیوست نمی‌شود.',
    'amount': 'مبلغ پرداختی',
    'amountHint': 'ریال کامل؛ تومان تا یک رقم اعشار',
    'amountBad': 'یک عدد کامل بنویسید، صفر یا بیشتر',
    'rials': 'ریال',
    'tomans': 'تومان',
    'inRials': 'به ریال',
    'inTomans': 'به تومان',
    'note': 'یادداشت',
    'noteHint': 'هر چه ارزش یادآوری دارد',
    'save': 'ثبت خرید',

    // جزئیات.
    'detailsTitle': 'گارانتی',
    'purchasedLabel': 'خرید',
    'endsLabel': 'پایان گارانتی',
    'durationLabel': 'مدت',
    'amountLabel': 'مبلغ',
    'merchantLabel': 'فروشنده',
    'serialLabel': 'سریال / فاکتور',
    'receiptLabel': 'رسید',
    'typeLabel': 'گارانتی',
    'noteLabel': 'یادداشت',
    'noValue': '—',
    'claimsTitle': 'ادعا و خدمات',
    'noClaims': 'هنوز ادعا یا خدمتی یادداشت نشده.',
    'addClaim': 'یادداشتِ ادعا',
    'addService': 'یادداشتِ خدمات',
    'claimPlaceholder': 'چه شد، و چه توافقی شد',
    'claimed': 'ادعا',
    'serviced': 'خدمات',
    'onDate': '{date}',
    'claimRequired': 'بنویسید یادداشت چه بگوید.',

    // پرسش‌ها و خطاها.
    'deleteWarranty': '«{name}» حذف شود؟',
    'deleteWarrantyBody':
        'خرید و یادداشت‌های ادعایش می‌رود. چند ثانیه می‌توانید برگردانید.',
    'warrantyDeleted': 'خرید حذف شد',
    'warrantyArchived': 'خرید آرشیو شد',
    'claimDeleted': 'یادداشت حذف شد',
    'archiveBody':
        'از فهرست می‌رود، با همان یادداشت‌ها. هر وقت بخواهید برمی‌گردد.',
    'discardTitle': 'بدون ذخیره خارج شویم؟',
    'discardBody': 'چیزی که تا حالا نوشته‌اید از بین می‌رود.',
    'discard': 'خروج',
    'keepWriting': 'ادامه بدهم',
    'saveFailed': 'ذخیره نشد. چیزی از دست نرفت — دوباره تلاش کنید.',
    'deleteFailed': 'حذف نشد. دوباره تلاش کنید.',

    // تاریخ‌ها.
    'ymd': '{y}/{m}/{d}',
  },
);
