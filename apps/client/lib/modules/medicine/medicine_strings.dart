import 'package:nex_client/modules/module_api.dart';

/// Medicine cabinet — the words it shows, in both languages, kept inside
/// the module as `NexModuleStrings` requires. Numbers passed as arguments
/// come out in Persian digits on the Persian side.
const medicineStrings = NexModuleStrings(
  en: {
    'dateHint': 'YYYY/MM/DD',
    'timeLimit': 'Up to {count} times. Remove one or clear this entry.',
    'unknownLog': 'Unknown record type',
    'keepDraft': 'Keep draft & close',
    'undoFailed':
        'Could not undo. A later change may conflict; retry after checking the record.',
    'takenLimited': 'Taken · recorded stock was insufficient',
    'loadFailed': 'Could not load your records. Retry before editing.',
    'retry': 'Retry',
    'title': 'Medicine cabinet',
    'tagline': 'Your medicines, in your own words',
    'about':
        'A list of the medicines you take, with doses you log yourself. It '
        'does not remind, does not check and does not advise — your '
        'clinician or pharmacist is the source for medical instructions.',
    'point1': 'A list you write yourself',
    'point2': 'Taken and skipped, logged by you',
    'point3': 'Expiry and refill, while it is open',
    'point4': 'Nothing medical is decided',

    // The list.
    'heroEyebrow': 'Your cabinet',
    'heroCount': '{count} medicines',
    'heroOne': '1 medicine',
    'heroCaption': 'Stock and expiry, in your own numbers.',
    'emptyMessage': 'Add your first medicine — a name is enough to begin.',
    'addMedicine': 'Add a medicine',
    'archived': 'Archived',
    'showArchived': 'Show archived',
    'hideArchived': 'Hide archived',
    'unarchive': 'Back on the list',
    'quantityLeft': '{count} {unit} left',
    'quantityNone': 'None left',
    'expired': 'Expired',
    'expiringSoon': 'Expiring soon',
    'refillSoon': 'Time to refill',

    // The editor.
    'editMedicine': 'Edit medicine',
    'name': 'Name',
    'nameHint': 'As it is written on the box',
    'nameRequired': 'Write the medicine’s name.',
    'duplicateName': 'A medicine with this name is already on the list.',
    'keepBoth': 'Keep both',
    'strength': 'Strength',
    'strengthHint': 'Free text — as on the box',
    'packageUnit': 'Package / unit',
    'packageHint': 'Tablet, drop, box…',
    'instructions': 'Your own instructions',
    'instructionsHint': 'In your words; this app does not advise',
    'times': 'Routine times',
    'timesNote':
        'For reference only — the times you wrote. Nothing is scheduled, '
        'and not logging a dose does not mean a dose was missed.',
    'timesHint': 'hh:mm, Enter for each',
    'badTime': 'Not a time',
    'days': 'Days',
    'daysHint': 'Every day, every other day…',
    'purpose': 'Private note',
    'purposeHint': 'What it is for, if you want to write it',
    'quantity': 'Quantity',
    'quantityNote':
        'In the units you chose. Leave empty to keep stock yourself.',
    'quantityHint': 'A whole number',
    'badNumber': 'Write a whole number, 0 or more',
    'doseUnits': 'Units per dose',
    'doseUnitsNote':
        'How many units one logged dose uses. Leave empty and stock never '
        'falls on its own.',
    'doseUnitsHint': 'A whole number, 1 or more',
    'expiry': 'Expiry date',
    'expiryNote': 'Optional. Shown while the app is open; no alert is set.',
    'badDate': 'Not a date',
    'refill': 'Refill threshold',
    'refillNote': 'When to be reminded to buy more, while the app is open.',
    'save': 'Save medicine',

    // The details.
    'detailsTitle': 'Medicine',
    'taken': 'Taken',
    'skipped': 'Skipped',
    'loggedAt': '{date} {time}',
    'doseHistory': 'Dose history',
    'noDoses': 'No doses logged yet.',
    'expiryLabel': 'Expires',
    'instructionsLabel': 'Instructions',
    'timesLabel': 'Times you wrote',
    'purposeLabel': 'Note',

    // Questions and failures.
    'deleteMedicine': 'Delete {name}?',
    'deleteMedicineBody':
        'The medicine and its dose history go. You can undo this for a few '
        'seconds.',
    'archiveMedicine': 'Archive {name}?',
    'archiveBody':
        'It leaves the list, with its history kept. You can bring it back '
        'any time.',
    'medicineDeleted': 'Medicine deleted',
    'medicineArchived': 'Medicine archived',
    'doseDeleted': 'Dose log deleted',
    'discardTitle': 'Leave without saving?',
    'discardBody': 'What you have written so far will be lost.',
    'discard': 'Leave',
    'keepWriting': 'Keep writing',
    'saveFailed': 'Could not save. Nothing was lost — try again.',
    'moreDetails': 'Times, stock and expiry',
    'moreDetailsHint': 'All optional — you can add them later.',
    'safetyNote':
        'This app does not check doses, interactions or timing. Your '
        'clinician or pharmacist is the source for medical instructions.',
  },
  fa: {
    'dateHint': 'سال/ماه/روز',
    'timeLimit': 'تا {count} ساعت؛ یکی را بردارید یا این ورودی را پاک کنید.',
    'unknownLog': 'نوع گزارش نامشخص',
    'keepDraft': 'نگهداری پیش‌نویس و بستن',
    'undoFailed':
        'بازگردانی انجام نشد؛ شاید اطلاعات بعداً تغییر کرده است. رکورد را بررسی کنید.',
    'takenLimited': 'مصرف ثبت شد · موجودی ثبت‌شده کافی نبود',
    'loadFailed': 'خواندن اطلاعات انجام نشد. پیش از ویرایش دوباره تلاش کنید.',
    'retry': 'تلاش دوباره',
    'title': 'جعبه دارو',
    'tagline': 'داروهایتان، با حرف‌های خودتان',
    'about':
        'فهرستی از داروهایی که مصرف می‌کنید، با نوبت‌هایی که خودتان ثبت '
        'می‌کنید. یادآوری نمی‌کند، بررسی نمی‌کند و توصیه‌ای نمی‌دهد — منبعِ '
        'دستورهای پزشکی، پزشک یا داروساز شماست.',
    'point1': 'فهرستی که خودتان می‌نویسید',
    'point2': 'مصرف‌شده و جاافتاده، با ثبت شما',
    'point3': 'انقضا و خرید مجدد، وقتی برنامه باز است',
    'point4': 'هیچ تصمیم پزشکی گرفته نمی‌شود',

    // فهرست.
    'heroEyebrow': 'جعبهٔ شما',
    'heroCount': '{count} دارو',
    'heroOne': '۱ دارو',
    'heroCaption': 'موجودی و انقضا، با اعداد خودتان.',
    'emptyMessage':
        'اولین دارو را اضافه کنید — همین که نامش را بنویسید کافی است.',
    'addMedicine': 'افزودن دارو',
    'archived': 'آرشیو',
    'showArchived': 'نمایش آرشیو',
    'hideArchived': 'پنهان‌کردن آرشیو',
    'unarchive': 'بازگشت به فهرست',
    'quantityLeft': '{count} {unit} مانده',
    'quantityNone': 'هیچ نمانده',
    'expired': 'منقضی شده',
    'expiringSoon': 'نزدیک به انقضا',
    'refillSoon': 'وقت خرید مجدد',

    // ویرایشگر.
    'editMedicine': 'ویرایش دارو',
    'name': 'نام',
    'nameHint': 'همان‌طور که روی جعبه است',
    'nameRequired': 'نام دارو را بنویسید.',
    'duplicateName': 'دارویی با این نام در فهرست هست.',
    'keepBoth': 'هر دو بمانند',
    'strength': 'غلظت',
    'strengthHint': 'متن آزاد — مثل روی جعبه',
    'packageUnit': 'بسته / واحد',
    'packageHint': 'قرص، قطره، جعبه…',
    'instructions': 'دستور خودتان',
    'instructionsHint': 'به حرف خودتان؛ این برنامه توصیه نمی‌کند',
    'times': 'ساعت‌های روتین',
    'timesNote':
        'فقط برای یادآوری — ساعتی که خودتان نوشته‌اید. چیزی زمان‌بندی نمی‌شود '
        'و ثبت‌نکردنِ یک نوبت یعنی جا افتاده، نه اینکه مصرف نشده.',
    'timesHint': 'ساعت:دقیقه، برای هر کدام Enter',
    'badTime': 'ساعت درست نیست',
    'days': 'روزها',
    'daysHint': 'هر روز، یک روز در میان…',
    'purpose': 'یادداشت خصوصی',
    'purposeHint': 'اگر می‌خواهید بنویسید برای چیست',
    'quantity': 'مقدار',
    'quantityNote':
        'به همان واحدی که انتخاب کرده‌اید. خالی بگذارید تا موجودی را خودتان '
        'بنویسید.',
    'quantityHint': 'یک عدد کامل',
    'badNumber': 'یک عدد کامل بنویسید، صفر یا بیشتر',
    'doseUnits': 'واحد در هر نوبت',
    'doseUnitsNote':
        'هر نوبتِ ثبت‌شده چند واحد برمی‌دارد. خالی بگذارید تا موجودی هرگز '
        'خودکار کم نشود.',
    'doseUnitsHint': 'یک عدد کامل، یک یا بیشتر',
    'expiry': 'تاریخ انقضا',
    'expiryNote':
        'اختیاری. تا وقتی برنامه باز است نشان داده می‌شود؛ هشداری ثبت نمی‌شود.',
    'badDate': 'تاریخ درست نیست',
    'refill': 'آستانه خرید مجدد',
    'refillNote': 'کی یادآوری خرید باشد، فقط وقتی برنامه باز است.',
    'save': 'ثبت دارو',

    // جزئیات.
    'detailsTitle': 'دارو',
    'taken': 'مصرف کردم',
    'skipped': 'جا افتاد',
    'loggedAt': '{date} ساعت {time}',
    'doseHistory': 'تاریخچه نوبت‌ها',
    'noDoses': 'هنوز نوبتی ثبت نشده.',
    'expiryLabel': 'انقضا',
    'instructionsLabel': 'دستور',
    'timesLabel': 'ساعت‌هایی که نوشتید',
    'purposeLabel': 'یادداشت',

    // پرسش‌ها و خطاها.
    'deleteMedicine': '«{name}» حذف شود؟',
    'deleteMedicineBody':
        'دارو و تاریخچه نوبت‌هایش می‌رود. چند ثانیه می‌توانید برگردانید.',
    'archiveMedicine': '«{name}» آرشیو شود؟',
    'archiveBody':
        'از فهرست می‌رود، با همان تاریخچه. هر وقت بخواهید برمی‌گردد.',
    'medicineDeleted': 'دارو حذف شد',
    'medicineArchived': 'دارو آرشیو شد',
    'doseDeleted': 'ثبتِ نوبت حذف شد',
    'discardTitle': 'بدون ذخیره خارج شویم؟',
    'discardBody': 'چیزی که تا حالا نوشته‌اید از بین می‌رود.',
    'discard': 'خروج',
    'keepWriting': 'ادامه بدهم',
    'saveFailed': 'ذخیره نشد. چیزی از دست نرفت — دوباره تلاش کنید.',
    'moreDetails': 'ساعت‌ها، موجودی و انقضا',
    'moreDetailsHint': 'همه اختیاری است؛ بعداً هم می‌شود افزود.',
    'safetyNote':
        'این برنامه دوز، تداخل یا زمان را بررسی نمی‌کند. منبعِ دستورهای '
        'پزشکی، پزشک یا داروساز شماست.',
  },
);
