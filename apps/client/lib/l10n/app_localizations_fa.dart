// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get appTitle => 'Nex';

  @override
  String get capture => 'ثبت';

  @override
  String get captureHint => 'بنویسید…';

  @override
  String get search => 'جست‌وجو';

  @override
  String get searchHint => 'جست‌وجو در یادداشت‌ها…';

  @override
  String get searchStart => 'برای پیدا کردن یادداشت، تایپ کنید.';

  @override
  String get settings => 'تنظیمات';

  @override
  String get voice => 'صدا';

  @override
  String get camera => 'دوربین';

  @override
  String get gallery => 'گالری';

  @override
  String get photo => 'عکس';

  @override
  String get file => 'فایل';

  @override
  String get text => 'متن';

  @override
  String get photoEditorTitle => 'ویرایش عکس';

  @override
  String get photoEditorAspect => 'نسبت تصویر';

  @override
  String get photoEditorFree => 'آزاد';

  @override
  String get photoEditorOriginal => 'اصلی';

  @override
  String get photoEditorSquare => 'مربع';

  @override
  String get photoEditorRotate => 'چرخش';

  @override
  String get photoEditorFlip => 'قرینه';

  @override
  String get photoEditorFlipVertical => 'قرینه عمودی';

  @override
  String get photoEditorReset => 'بازنشانی';

  @override
  String get filters => 'فیلترها';

  @override
  String filtersCount(int count) {
    return 'فیلترها ($count)';
  }

  @override
  String get date => 'تاریخ';

  @override
  String get clear => 'پاک کردن';

  @override
  String resultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نتیجه',
      one: 'یک نتیجه',
      zero: 'نتیجه‌ای پیدا نشد',
    );
    return '$_temp0';
  }

  @override
  String nothingMatches(String query) {
    return 'چیزی با «$query» پیدا نشد.';
  }

  @override
  String get closestThing => 'نزدیک‌ترین چیزی که نوشته‌اید:';

  @override
  String get nothingClose => 'چیزی نزدیک به آن هم پیدا نشد.';

  @override
  String get emptyPromise => 'هر چیزی که اینجا بگذارید، می‌ماند.';

  @override
  String get emptySupport => 'چیز دیگری از شما خواسته نمی‌شود.';

  @override
  String get emptyType => 'بنویسید';

  @override
  String get emptySpeak => 'بگویید';

  @override
  String get emptyPhotograph => 'عکس بگیرید';

  @override
  String get emptyNoSave => 'دکمهٔ ذخیره‌ای در کار نیست.';

  @override
  String get emptyAi =>
      'آنچه ثبت می‌کنید را هم می‌خواند؛ صدا را متن می‌کند، از عکس‌ها متن درمی‌آورد و برچسب پیشنهاد می‌دهد. با فعال‌کردن یک سرویس در تنظیمات، خلاصه‌سازی و جست‌وجو هم اضافه می‌شود.';

  @override
  String get delete => 'حذف';

  @override
  String get addTag => 'افزودن برچسب';

  @override
  String get noteDeleted => 'یادداشت حذف شد';

  @override
  String get undo => 'برگرداندن';

  @override
  String get cancel => 'بی‌خیال';

  @override
  String get restore => 'بازیابی';

  @override
  String get rename => 'تغییر نام';

  @override
  String get merge => 'ادغام';

  @override
  String get tags => 'برچسب‌ها';

  @override
  String get tagActions => 'کارهای برچسب';

  @override
  String noteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count یادداشت',
      one: 'یک یادداشت',
      zero: 'بدون یادداشت',
    );
    return '$_temp0';
  }

  @override
  String get renameTag => 'تغییر نام برچسب';

  @override
  String get deleteTag => 'برچسب حذف شود؟';

  @override
  String get deleteTagBody =>
      'برچسب فقط از روی یادداشت‌ها برداشته می‌شود؛ خود یادداشت‌ها حذف نمی‌شوند.';

  @override
  String get recentlyDeleted => 'حذف‌شده‌های اخیر';

  @override
  String get recentlyDeletedEmpty => 'چیزی به‌تازگی حذف نشده.';

  @override
  String get appearance => 'ظاهر';

  @override
  String get language => 'زبان';

  @override
  String get accessibility => 'دسترس‌پذیری';

  @override
  String get reduceMotion => 'کم‌کردن انیمیشن‌ها';

  @override
  String get haptics => 'لرزش هنگام ثبت';

  @override
  String get intelligence => 'هوش مصنوعی';

  @override
  String get intelligenceLocal =>
      'تا وقتی هوش ابری خاموش است، همه‌چیز روی همین دستگاه پردازش می‌شود.';

  @override
  String get about => 'دربارهٔ Nex';

  @override
  String get localFirstTitle => 'ذخیره روی همین دستگاه';

  @override
  String localFirstBody(String path) {
    return 'یادداشت‌های شما روی همین دستگاه، در $path نگهداری می‌شوند';
  }

  @override
  String get copyPath => 'کپی مسیر داده‌ها';

  @override
  String get silenceTitle => 'سکوت، خودش یک ویژگی است';

  @override
  String get silenceBody =>
      'Nex هیچ‌وقت اعلان، نشان، یادآور یا پیام «برگرد» نمی‌فرستد.';

  @override
  String get privacy => 'حریم خصوصی';

  @override
  String get privacyBody =>
      'ثبت و جست‌وجوی یادداشت‌ها نه چیزی جمع‌آوری می‌کند و نه چیزی به بیرون می‌فرستد.';

  @override
  String get shareDiagnostics => 'اشتراک‌گذاری گزارش خطا';

  @override
  String get shareDiagnosticsBody =>
      'ثبت محلی چند خطای آخر، برای وقتی چیزی خراب شد. چیزی به هیچ‌جا فرستاده نمی‌شود مگر خودتان اینجا اشتراک بگذارید.';

  @override
  String get noDiagnosticsYet => 'چیزی برای اشتراک‌گذاری نیست';

  @override
  String get openSourceLicenses => 'پروانه‌های متن‌باز';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';

  @override
  String get themeSystem => 'مثل سیستم';

  @override
  String get comfortMode => 'حالت آسایش';

  @override
  String get comfortModeSubtitle =>
      'کنتراست کمتر و رنگ‌های گرم‌تر؛ جدا از روشن یا تیره بودن پوسته';

  @override
  String get uiScale => 'اندازه‌ی متن و رابط';

  @override
  String get uiScaleSmall => 'کوچک';

  @override
  String get uiScaleDefault => 'پیش‌فرض';

  @override
  String get uiScaleLarge => 'بزرگ';

  @override
  String get uiScaleLarger => 'بزرگ‌تر';

  @override
  String get enterSubmitsCapture => 'اینتر یادداشت را ثبت کند';

  @override
  String get enterSubmitsCaptureSubtitle =>
      'در حالت خاموش، اینتر خط جدید شروع می‌کند. Shift+Enter در هر دو حالت همیشه خط جدید می‌سازد.';

  @override
  String get languageSystem => 'مثل سیستم';

  @override
  String get languageEnglish => 'انگلیسی';

  @override
  String get languagePersian => 'فارسی';

  @override
  String get storage => 'فضای ذخیره‌سازی';

  @override
  String storageUsed(String size) {
    return '$size روی این دستگاه اشغال شده';
  }

  @override
  String get stopRecording => 'پایان ضبط';

  @override
  String recordingElapsed(String elapsed) {
    return 'در حال ضبط · $elapsed';
  }

  @override
  String get discard => 'دور ریختن';

  @override
  String get captureFailed =>
      'ثبت ذخیره نشد. یادداشت‌های قبلی شما دست‌نخورده ماندند.';

  @override
  String get noteNotFound => 'یادداشت پیدا نشد';

  @override
  String get mediaUnavailable => 'این فایل رسانه‌ای در دسترس نیست.';

  @override
  String get copy => 'کپی';

  @override
  String get share => 'هم‌رسانی';

  @override
  String get swipeActions => 'کشیدن انگشت';

  @override
  String get transcription => 'تبدیل گفتار به متن';

  @override
  String get ocr => 'تشخیص متن در تصویر';

  @override
  String get tagSuggestions => 'پیشنهاد برچسب';

  @override
  String get semanticSearch => 'جست‌وجوی معنایی';

  @override
  String get summarization => 'خلاصه‌سازی';

  @override
  String get relatedNotes => 'یادداشت‌های مرتبط';

  @override
  String get cloudAi => 'هوش ابری (اختیاری)';

  @override
  String get cloudAiSubtitle =>
      'پیش‌فرض خاموش است؛ ثبت و جست‌وجو بدون آن هم کار می‌کنند.';

  @override
  String get sync => 'همگام‌سازی';

  @override
  String get syncNow => 'همگام‌سازی همین حالا';

  @override
  String get syncComplete => 'همگام‌سازی انجام شد';

  @override
  String get export => 'خروجی گرفتن';

  @override
  String exportedTo(String path) {
    return 'خروجی در $path ذخیره شد';
  }

  @override
  String get restoreBackup => 'بازیابی از پشتیبان';

  @override
  String get restoreBody =>
      'پایگاه دادهٔ روی دستگاه با تازه‌ترین پشتیبانِ سالم جایگزین شود؟';

  @override
  String get deleteBackup => 'حذف پشتیبان';

  @override
  String get deleteBackupBody =>
      'این فایل پشتیبان روی دستگاه حذف می‌شود و برگشت‌پذیر نیست.';

  @override
  String backupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count پشتیبان',
      one: 'یک پشتیبان',
      zero: 'بدون پشتیبان',
    );
    return '$_temp0';
  }

  @override
  String get operationFailed =>
      'این کار انجام نشد. یادداشت‌های قبلی شما دست‌نخورده ماندند.';

  @override
  String noteType(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'text': 'متن',
      'voice': 'صدا',
      'photo': 'عکس',
      'file': 'فایل',
      'other': 'یادداشت',
    });
    return '$_temp0';
  }

  @override
  String get addAction => 'افزودن';

  @override
  String get all => 'همه';

  @override
  String get swipeLeading => 'کشیدن از لبهٔ آغاز';

  @override
  String get swipeTrailing => 'کشیدن از لبهٔ پایان';

  @override
  String get noTagsYet => 'هنوز برچسبی نساخته‌اید';

  @override
  String get madeBy => 'ساختهٔ';

  @override
  String get website => 'وب‌سایت';

  @override
  String get edit => 'ویرایش';

  @override
  String get save => 'ذخیره';

  @override
  String get editNote => 'ویرایش یادداشت';

  @override
  String get caption => 'شرح';

  @override
  String get captionHint => 'توضیح دلخواه…';

  @override
  String get addCaption => 'افزودن شرح';

  @override
  String get editCaption => 'ویرایش شرح';

  @override
  String get noCaption => 'بدون شرح';

  @override
  String get tagName => 'نام برچسب';

  @override
  String get tag => 'برچسب';

  @override
  String get pin => 'پین کردن';

  @override
  String get unpin => 'برداشتن پین';

  @override
  String get summary => 'خلاصه';

  @override
  String get summarize => 'خلاصه کن';

  @override
  String get suggestedTags => 'برچسب‌های پیشنهادی';

  @override
  String get dismiss => 'نادیده بگیر';

  @override
  String get transcript => 'متن گفتار';

  @override
  String get voiceSearchHint => 'فقط با برچسب یا تاریخ پیدا می‌شود';

  @override
  String voiceDuration(int seconds) {
    return 'صدا · $seconds ثانیه';
  }

  @override
  String get widgetsSection => 'ویجت‌های صفحه اصلی';

  @override
  String get widgetsHowTo => 'روش افزودن';

  @override
  String get widgetsSubtitle =>
      'ثبت سریع، صدا، دوربین و یادداشت‌های اخیر — از داخل لانچر اضافه می‌شوند';

  @override
  String get widgetsHowToBody =>
      'روی جای خالی صفحه اصلی انگشت بگذارید و نگه دارید، Widgets را انتخاب کنید و Nex را پیدا کنید. چهار ویجت در دسترس است: ثبت سریع، یادداشت صوتی، دوربین و یادداشت‌های اخیر.\n\nویجت‌ها فقط همان خلاصه‌ای را می‌خوانند که برنامه روی همین دستگاه برایشان نگه می‌دارد؛ چیزی جایی فرستاده نمی‌شود.';

  @override
  String get tapToExpand => 'برای نمایش تمام‌صفحه روی تصویر بزنید';

  @override
  String similarity(String score) {
    return 'شباهت $score';
  }

  @override
  String get moreOptions => 'گزینه‌های بیشتر';

  @override
  String get copied => 'کپی شد';

  @override
  String get nothingToCopy => 'این یادداشت متنی برای کپی ندارد';

  @override
  String get details => 'جزئیات';

  @override
  String get created => 'ساخته شده';

  @override
  String get updated => 'آخرین تغییر';

  @override
  String get size => 'حجم';

  @override
  String get createTag => 'برچسب تازه';

  @override
  String get libraryTitle => 'کتابخانه';

  @override
  String get dataAndBackup => 'داده و پشتیبان';

  @override
  String get libraryOpenFailed =>
      'Nex نتوانست کتابخانهٔ روی دستگاه شما را باز کند. فایل‌های شما دست‌نخورده ماندند.';

  @override
  String get tryAgain => 'دوباره تلاش کن';

  @override
  String get opening => 'Nex در حال باز شدن است';

  @override
  String get paste => 'جای‌گذاری';

  @override
  String get pasteClipboard => 'درج متنی که کپی کرده‌اید';

  @override
  String get swipeActionsHint =>
      'هر طرف جداگانه تنظیم می‌شود. روی هر کارت بزنید تا کارِ آن کشیدن را انتخاب کنید یا خاموشش کنید.';

  @override
  String get revealInFolder => 'نمایش مسیر فایل';

  @override
  String get trash => 'سطل زباله';

  @override
  String get trashRetention =>
      'موارد اینجا بعد از ۳۰ روز برای همیشه پاک می‌شوند.';

  @override
  String get deleteForever => 'حذف همیشگی';

  @override
  String get deleteForeverBody =>
      'این یادداشت برای همیشه از بین می‌رود و برگشتی ندارد.';

  @override
  String get emptyTrash => 'خالی کردن سطل';

  @override
  String get open => 'باز کردن';

  @override
  String get cannotOpen =>
      'روی این دستگاه برنامه‌ای برای باز کردن این فایل نیست.';

  @override
  String get sourceCode => 'کد منبع';

  @override
  String get sendFeedback => 'ارسال بازخورد';

  @override
  String get sendFeedbackSubtitle => 'github.com/sanyzrn/DbsNex/issues';

  @override
  String get capabilities => 'Nex چه می‌کند';

  @override
  String get capabilityCapture => 'ثبت متن، صدا، عکس و فایل، بدون دکمهٔ ذخیره';

  @override
  String get capabilitySearch =>
      'جست‌وجوی متن، برچسب، تاریخ و نوع، همه روی همین دستگاه';

  @override
  String get capabilityOffline =>
      'همهٔ کارهای اصلی بدون هیچ اینترنتی کار می‌کنند';

  @override
  String get capabilityExport =>
      'خروجی کامل به شکل JSON، Markdown و فایل‌های اصلی';

  @override
  String get version => 'نسخه';

  @override
  String emptyTrashBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count یادداشت برای همیشه از بین می‌روند و برگشتی ندارند.',
      one: 'یک یادداشت برای همیشه از بین می‌رود و برگشتی ندارد.',
    );
    return '$_temp0';
  }

  @override
  String get checkForUpdate => 'بررسی بروزرسانی';

  @override
  String get checkingForUpdate => 'در حال گشتن دنبال نسخهٔ تازه‌تر…';

  @override
  String get upToDate => 'شما آخرین نسخه را دارید.';

  @override
  String get downloadAndInstall => 'دانلود و نصب';

  @override
  String get downloading => 'در حال دانلود…';

  @override
  String get readyToInstall => 'دانلود شد. آمادهٔ نصب است.';

  @override
  String get install => 'نصب';

  @override
  String get updateInstallNotice =>
      'اندروید برای نصب از شما تأیید می‌گیرد. یادداشت‌های شما دست‌نخورده می‌مانند.';

  @override
  String get updateDownloadFailed =>
      'دانلود کامل نشد. اتصال را بررسی کنید و دوباره تلاش کنید.';

  @override
  String get updateNoSpace => 'فضای خالی برای دانلود به‌روزرسانی کافی نیست.';

  @override
  String get updateCheckFailed =>
      'دسترسی به سرور بروزرسانی ممکن نشد. اتصال را بررسی کنید و دوباره تلاش کنید.';

  @override
  String get installBlocked =>
      'نصب‌کننده باز نشد. در تنظیمات گوشی به Nex اجازهٔ نصب برنامهٔ ناشناس بدهید و دوباره امتحان کنید.';

  @override
  String installedVersion(String version) {
    return 'نسخهٔ نصب‌شده $version';
  }

  @override
  String updateAvailable(String version) {
    return 'نسخهٔ $version منتشر شده';
  }

  @override
  String get autoUpdateCheck => 'بررسی خودکار';

  @override
  String get autoUpdateCheckHint =>
      'روزی یک بار، بی‌سروصدا. نسخهٔ جدید فقط با یک نقطه اینجا خبر داده می‌شود — هیچ‌وقت اعلان نمی‌آید.';

  @override
  String get updateReady => 'دانلود شد و آمادهٔ نصب است';

  @override
  String get yourName => 'نام شما';

  @override
  String get yourNameHint => 'فقط برای سلام گفتن، و فقط روی همین دستگاه.';

  @override
  String get yourNamePlaceholder => 'خالی بگذارید تا سلامی در کار نباشد';

  @override
  String greetingMorning(String name) {
    return 'صبح بخیر، $name';
  }

  @override
  String greetingAfternoon(String name) {
    return 'ظهر بخیر، $name';
  }

  @override
  String greetingEvening(String name) {
    return 'عصر بخیر، $name';
  }

  @override
  String greetingNight(String name) {
    return 'هنوز بیداری، $name؟';
  }

  @override
  String get updateDownloadedToast => 'به‌روزرسانی دانلود شد — آمادهٔ نصب';

  @override
  String greetingMorningB(String name) {
    return 'صفحهٔ نو، $name';
  }

  @override
  String greetingMorningC(String name) {
    return 'روز از نو، $name';
  }

  @override
  String greetingAfternoonB(String name) {
    return 'نصف راه رفته، $name';
  }

  @override
  String greetingAfternoonC(String name) {
    return 'چی داری برام، $name؟';
  }

  @override
  String greetingEveningB(String name) {
    return 'آرام‌آرام، $name';
  }

  @override
  String greetingEveningC(String name) {
    return 'ساعت‌های ساکت، $name';
  }

  @override
  String greetingNightB(String name) {
    return 'سلام جغد شب، $name';
  }

  @override
  String greetingNightC(String name) {
    return 'دنیا خوابه، $name';
  }

  @override
  String get exportTitle => 'بردنش با خودتان';

  @override
  String get exportExplained =>
      'همهٔ یادداشت‌ها را در یک فایل zip می‌نویسد: دادهٔ کامل به شکل JSON، یک فایل Markdown خوانا برای هر یادداشت، و همهٔ عکس‌ها، صداها و پیوست‌ها. چیزی جا نمی‌ماند و چیزی هم جایی آپلود نمی‌شود؛ فایل به خودتان داده می‌شود.';

  @override
  String get exportAndShare => 'خروجی گرفتن و هم‌رسانی';

  @override
  String get importTitle => 'وارد کردن';

  @override
  String get importExplained =>
      'یک خروجی Nex را دوباره به همین کتابخانه می‌خواند. یادداشت‌هایی که از قبل اینجا هستند دست‌نخورده می‌مانند، پس وارد کردن دوبارهٔ یک فایل هیچ تغییری نمی‌دهد.';

  @override
  String get chooseFile => 'انتخاب فایل';

  @override
  String importDone(int added, int skipped) {
    String _temp0 = intl.Intl.pluralLogic(
      added,
      locale: localeName,
      other: '$added یادداشت اضافه شد',
      one: 'یک یادداشت اضافه شد',
      zero: 'چیز تازه‌ای نبود',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skipped,
      locale: localeName,
      other: '$skipped تا از قبل بودند',
      one: 'یکی از قبل بود',
      zero: '',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get importFailed =>
      'این فایل به‌عنوان خروجی Nex خوانده نشد. یادداشت‌های شما تغییری نکردند.';

  @override
  String get localBackupsTitle => 'پشتیبان‌های روی این دستگاه';

  @override
  String get localBackupsExplained =>
      'Nex روزی یک بار از پایگاه دادهٔ خودش یک نسخه در پوشهٔ خودش می‌گیرد — متن، برچسب‌ها و تاریخ‌ها، نه عکس‌ها، صداها یا پیوست‌هایی که آن یادداشت‌ها به آن‌ها اشاره می‌کنند. این محافظت در برابر بازیابی اشتباه یا فایل خراب، روی همین دستگاه است؛ برای نسخه‌ای که مدیا را هم داشته باشد، یا برای انتقال به دستگاه دیگر، باید خروجی بگیرید.';

  @override
  String get backupNow => 'همین حالا پشتیبان بگیر';

  @override
  String get backupDone => 'پشتیبان گرفته شد';

  @override
  String get syncNotConfigured =>
      'هیچ سروری تنظیم نشده. همگام‌سازی اختیاری است — Nex بدون آن کاملاً آفلاین کار می‌کند.';

  @override
  String get syncServer => 'سرور همگام‌سازی';

  @override
  String get syncServerHint => 'https://…';

  @override
  String get syncToken => 'توکن دستگاه';

  @override
  String get aiShow => 'ببین Nex از این چه فهمیده';

  @override
  String aiReady(String what) {
    return '$what آماده است';
  }

  @override
  String get aiSection => 'چیزی که Nex خوانده';

  @override
  String get aiNothingYet =>
      'هنوز چیزی نیست. Nex بعد از ثبت، یادداشت را در پس‌زمینه می‌خواند.';

  @override
  String get hide => 'پنهان کردن';

  @override
  String get catchUpTitle => 'یادداشت‌هایی که از قبل دارید';

  @override
  String get catchUpBody =>
      'Nex هر یادداشت را درست بعد از ثبت، در پس‌زمینه می‌خواند؛ یعنی هرچه پیش از روشن کردن این بخش ثبت شده هیچ‌وقت خوانده نشده. این گزینه آن عقب‌ماندگی را دسته‌دسته جبران می‌کند.';

  @override
  String get catchUpAction => 'جبران عقب‌ماندگی';

  @override
  String catchUpDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count یادداشت خوانده شد',
      one: 'یک یادداشت خوانده شد',
      zero: 'چیزی برای خواندن نمانده',
    );
    return '$_temp0';
  }

  @override
  String noteOfType(String type) {
    return 'یادداشت $type';
  }

  @override
  String tagListLabel(String tags) {
    return 'برچسب‌ها: $tags';
  }

  @override
  String get accentColorLabel => 'رنگ برچسب';

  @override
  String get captureFailedPermission =>
      'به Nex اجازهٔ استفاده از دوربین یا عکس‌ها داده نشده. می‌توانید از تنظیمات دستگاه اجازه بدهید.';

  @override
  String get captureFailedStorage =>
      'روی این دستگاه جایی برای این فایل نمانده. یادداشت‌های قبلی شما تغییری نکردند.';

  @override
  String get captureFailedUnreadable =>
      'این فایل خوانده نشد. اگر در پوشهٔ ابری است، یک بار بازش کنید تا نسخه‌اش روی دستگاه بیاید.';

  @override
  String get retry => 'دوباره تلاش کن';

  @override
  String get cropConfirm => 'استفاده از عکس';

  @override
  String get cropCancel => 'دور ریختن عکس';

  @override
  String get tagColor => 'رنگ برچسب';

  @override
  String get customColor => 'دلخواه';

  @override
  String get saturation => 'غلظت';

  @override
  String get brightness => 'روشنایی';

  @override
  String get noColor => 'بدون رنگ';

  @override
  String get color => 'رنگ';

  @override
  String get aiProvider => 'سرویس هوش مصنوعی';

  @override
  String get aiProviderIntro =>
      'انتخاب کنید درخواست‌های هوش مصنوعی کجا فرستاده شوند. بدون سرویس، همه‌چیز فقط روی همین دستگاه اجرا می‌شود که برای پیشنهاد برچسب کافی است ولی برای خلاصه‌سازی نه.';

  @override
  String get apiKey => 'کلید API';

  @override
  String get baseUrl => 'آدرس سرویس';

  @override
  String get model => 'مدل';

  @override
  String get testConnection => 'تست اتصال';

  @override
  String get aiProviderNoneSubtitle =>
      'روی همین دستگاه اجرا می‌شود. کلید لازم ندارد.';

  @override
  String get aiProviderSaved => 'سرویس ذخیره شد.';

  @override
  String get aiKeyStorage =>
      'کلید روی همین دستگاه و در تنظیمات خصوصی برنامه ذخیره می‌شود. رمزگذاری‌شده نیست، و جز به همان سرویسی که انتخاب کرده‌اید جایی فرستاده نمی‌شود.';

  @override
  String get aiCapabilityNote =>
      'پیشنهاد برچسب و خلاصه‌سازی با همهٔ سرویس‌ها کار می‌کنند. جست‌وجوی معنایی به سرویس سازگار با OpenAI نیاز دارد. تبدیل گفتار به متن و تشخیص متن تصویر فعلاً روی خود دستگاه می‌مانند.';

  @override
  String connectionOk(String model) {
    return 'وصل شد. مدل $model جواب داد.';
  }

  @override
  String get swipeNone => 'هیچ کاری';

  @override
  String get intelligenceOff => 'خاموش';

  @override
  String get intelligenceMasterSubtitle =>
      'به یک سرویس اجازه بدهید یادداشت‌ها را بخواند تا رونویسی، خلاصه و پیشنهاد برچسب بدهد.';

  @override
  String get intelligenceOffBody =>
      'همه‌چیز روی همین دستگاه می‌ماند. چیزی جایی فرستاده نمی‌شود و هیچ یادداشتی از برنامه بیرون نمی‌رود.';

  @override
  String get intelligenceConsentTitle => 'هوش مصنوعی روشن شود؟';

  @override
  String get intelligenceConsentBody =>
      'Nex کامل آفلاین کار می‌کند. روشن کردن این گزینه تنها استثناست: یادداشت‌هایی که به قابلیت‌های فعال‌شده مربوط می‌شوند، برای سرویسی که انتخاب می‌کنید فرستاده می‌شوند تا بتواند پاسخ بدهد.\n\nتا وقتی سرویس و کلیدش را وارد نکنید هیچ چیزی فرستاده نمی‌شود. هر وقت خواستید می‌توانید دوباره خاموشش کنید و چیزی از آنچه ذخیره شده از بین نمی‌رود.';

  @override
  String get intelligenceConsentAccept => 'روشن کن';

  @override
  String get intelligenceQuietNote =>
      'نتیجه‌ها بی‌سروصدا در پس‌زمینه آماده و کنار یادداشت نگه داشته می‌شوند. چیزی مزاحمتان نمی‌شود — خلاصه یا برچسب پیشنهادی فقط وقتی یادداشت را باز کنید و بخواهید دیده می‌شود.';

  @override
  String get automatic => 'خودکار انجام می‌شود';

  @override
  String get notSupportedByProvider => 'سرویسی که انتخاب کرده‌اید این را ندارد';

  @override
  String get transcriptionSubtitle => 'تبدیل یادداشت صوتی به متنِ قابل جست‌وجو';

  @override
  String get ocrSubtitle => 'خواندن نوشته‌های داخل عکس';

  @override
  String get summarizationSubtitle => 'فشرده کردن یادداشت بلند در یک خط';

  @override
  String get tagSuggestionsSubtitle =>
      'پیشنهاد برچسب — هیچ‌وقت خودش اعمال نمی‌کند';

  @override
  String get semanticSearchSubtitle =>
      'پیدا کردن یادداشت بر اساس معنا، نه فقط کلمه';

  @override
  String get relatedNotesSubtitle =>
      'نمایش یادداشت‌های دیگری که به همین موضوع مربوط‌اند';

  @override
  String get intelligenceOpen => 'رونویسی، خلاصه، برچسب';
}
