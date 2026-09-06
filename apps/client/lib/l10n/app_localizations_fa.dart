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
  String get captureHint => 'چی تو ذهنته؟';

  @override
  String get layoutTitle => 'چیدمان خانه';

  @override
  String get layoutSubtitle => 'چه چیزهایی بالای یادداشت‌ها دیده شوند.';

  @override
  String get layoutGreeting => 'خوش‌آمدگویی';

  @override
  String get layoutDaySummary => 'خلاصهٔ هوشمند روز';

  @override
  String get layoutSearchField => 'جعبهٔ جست‌وجو';

  @override
  String get layoutTagRow => 'نوار برچسب‌ها';

  @override
  String chatAboutGroup(String label, int count) {
    return 'دربارهٔ $label · $count یادداشت';
  }

  @override
  String get groupActions => 'عملیات گروه';

  @override
  String get groupAsk => 'دربارهٔ این‌ها بپرس';

  @override
  String get groupDelete => 'حذف این گروه';

  @override
  String groupDeleteBody(int count) {
    return '$count یادداشت به زباله‌دان می‌رود. از کتابخانه ← زباله‌دان می‌توانید برشان گردانید.';
  }

  @override
  String groupDeleted(int count) {
    return '$count یادداشت حذف شد';
  }

  @override
  String get assistantVoiceGroup => 'چطور حرف بزند';

  @override
  String get assistantReachGroup => 'چه چیزی را می‌بیند';

  @override
  String get assistantAboutYouGroup => 'دربارهٔ شما';

  @override
  String get assistantProfileIntro =>
      'کمی از خودتان به دستیار بگویید و بعد لحنی را انتخاب کنید که برایتان مناسب است. این اطلاعات فقط همراه سؤال‌های دستیار فرستاده می‌شوند.';

  @override
  String get assistantCallMe => 'شما را چه صدا کند؟';

  @override
  String get assistantCallMeHint => 'نامی که دوست دارید';

  @override
  String get assistantAboutMe => 'معرفی کوتاه';

  @override
  String get assistantAboutMeHint => 'دستیار چه چیزهایی دربارهٔ شما بداند؟';

  @override
  String get assistantResponseStyle => 'سبک پاسخ‌گویی';

  @override
  String get assistantStyleNatural => 'طبیعی';

  @override
  String get assistantStyleFriendly => 'دوستانه';

  @override
  String get assistantStyleFormal => 'رسمی';

  @override
  String get assistantStyleSerious => 'جدی';

  @override
  String get assistantStyleRomantic => 'عاشقانه';

  @override
  String get assistantStyleCustom => 'دلخواه';

  @override
  String get profileTitle => 'پروفایل';

  @override
  String get profileOpenHint => 'تصویر، نام، تاریخ تولد و بیو';

  @override
  String get profileChangePhoto => 'تغییر تصویر پروفایل';

  @override
  String get profileRemovePhoto => 'حذف تصویر';

  @override
  String get profilePhotoFailed => 'تصویر پروفایل ذخیره نشد.';

  @override
  String get profileBirthday => 'تاریخ تولد';

  @override
  String get profileBirthdayEmpty => 'ثبت نشده';

  @override
  String get profileBio => 'بیو';

  @override
  String get profileBioHint => 'چند کلمه دربارهٔ خودتان';

  @override
  String get securityTitle => 'امنیت';

  @override
  String get securityAppLock => 'قفل برنامه';

  @override
  String get securityOff => 'خاموش';

  @override
  String get securityDevicePasscode => 'رمز دستگاه';

  @override
  String get securityDevicePasscodeSubtitle =>
      'Nex را با رمز، پین یا الگوی گوشی یا رایانه باز کنید.';

  @override
  String get securityBiometric => 'اثر انگشت یا بیومتریک';

  @override
  String get securityBiometricSubtitle =>
      'به‌جای رمز جایگزین، اثر انگشت، چهره یا Windows Hello ثبت‌شده را بخواهد.';

  @override
  String get securityLocalOnly =>
      'احراز هویت را خود دستگاه انجام می‌دهد. Nex هیچ رمز یا دادهٔ بیومتریکی را دریافت یا ذخیره نمی‌کند.';

  @override
  String get securityScreenshotBlocked =>
      'تا وقتی قفل روشن است، Nex از صفحهٔ برنامه‌های اخیر هم پنهان می‌ماند و گرفتن اسکرین‌شات از آن مسدود می‌شود.';

  @override
  String get securityPasscodeUnavailable =>
      'ابتدا برای دستگاه رمز، پین یا الگو تنظیم کنید.';

  @override
  String get securityBiometricUnavailable =>
      'اثر انگشت یا بیومتریک ثبت‌شده‌ای پیدا نشد.';

  @override
  String get securityAuthenticateReason =>
      'برای محافظت از یادداشت‌ها Nex را باز کنید';

  @override
  String get securityLockedTitle => 'Nex قفل است';

  @override
  String get securityLockedSubtitle =>
      'برای بازکردن یادداشت‌ها با دستگاه احراز هویت کنید.';

  @override
  String get securityUnlock => 'بازکردن';

  @override
  String get pinLimitReached => 'می‌توانید حداکثر ۵ یادداشت را پین کنید';

  @override
  String get storageModels => 'مدل آفلاین';

  @override
  String get storageImages => 'تصاویر';

  @override
  String get storageAudio => 'ضبط‌ها';

  @override
  String get storageBackups => 'پشتیبان‌ها';

  @override
  String get storageNotes => 'یادداشت‌ها و نمایه';

  @override
  String get storageOther => 'فایل‌های دیگر';

  @override
  String get storageEmpty => 'هنوز چیزی ذخیره نشده.';

  @override
  String get remindRepeat => 'تکرار';

  @override
  String get remindRepeatOnce => 'یک‌بار';

  @override
  String get remindRepeatDaily => 'هر روز';

  @override
  String get remindRepeatWeekly => 'هر هفته';

  @override
  String remindRepeatingAt(String when, String repeat) {
    return '$when · $repeat';
  }

  @override
  String get nudgeNotScheduled =>
      'یادآور روزانه روشن شد، ولی این گوشی آلارمش را قبول نکرد.';

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
  String get filters => 'فیلترها';

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
  String get semanticMatches =>
      'هیچ‌کدام همان کلمه‌ها را ندارند، اما این‌ها همین موضوع را می‌گویند:';

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
  String get timelineGroupPinned => 'سنجاق‌شده';

  @override
  String get timelineGroupToday => 'امروز';

  @override
  String get timelineGroupYesterday => 'دیروز';

  @override
  String get timelineGroupWeek => 'هفتهٔ گذشته';

  @override
  String get timelineGroupMonth => 'ماه گذشته';

  @override
  String get timelineGroupOlder => 'قدیمی‌تر';

  @override
  String timelineGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count یادداشت',
      one: '۱ یادداشت',
    );
    return '$_temp0';
  }

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
  String get recentlyDeletedEmpty => 'چیزی به‌تازگی حذف نشده.';

  @override
  String get appearance => 'ظاهر';

  @override
  String get language => 'زبان';

  @override
  String get accessibility => 'دسترس‌پذیری';

  @override
  String get haptics => 'لرزش هنگام ثبت';

  @override
  String get intelligence => 'هوش مصنوعی';

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
  String get theme => 'پوسته';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';

  @override
  String get themeSystem => 'مثل سیستم';

  @override
  String get comfortMode => 'حالت آسایش';

  @override
  String get liquidGlass => 'شیشهٔ مایع';

  @override
  String get liquidGlassSubtitle =>
      'کنترل‌های نیمه‌شفاف تطبیقی با محوشدگی واقعی پس‌زمینه';

  @override
  String get backgroundStyle => 'پس‌زمینه';

  @override
  String get backgroundStyleSubtitle =>
      'پترن‌های مینیمال داخلی، تنظیم‌شده برای هر دو پوستهٔ روشن و تیره';

  @override
  String get backgroundPlain => 'ساده';

  @override
  String get backgroundAurora => 'شفق';

  @override
  String get backgroundRipple => 'موج';

  @override
  String get backgroundWeave => 'بافت';

  @override
  String get backgroundDots => 'نقطه‌چین';

  @override
  String get backgroundDusk => 'شامگاه';

  @override
  String get backgroundTopography => 'توپوگرافی';

  @override
  String get backgroundPrism => 'منشور';

  @override
  String get accentColorSetting => 'رنگ تاکید';

  @override
  String get accentColorSettingSubtitle =>
      'رنگ نشانگر، حلقهٔ فوکوس و حالت‌های فعال را در سراسر اپ تغییر می‌دهد';

  @override
  String get accentColorPickerTitle => 'رنگ تاکید';

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
  String get storage => 'فضای ذخیره‌سازی';

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
  String get syncFailed =>
      'همگام‌سازی ناموفق بود. چیزی روی این دستگاه عوض نشد.';

  @override
  String get backupFailed =>
      'پشتیبان نوشته نشد. یادداشت‌هایت دست‌نخورده‌اند.';

  @override
  String get exportFailed =>
      'خروجی نوشته نشد. یادداشت‌هایت دست‌نخورده‌اند.';

  @override
  String get restoredStaysLocal =>
      'یادداشت‌های بازیابی‌شده روی همین دستگاه می‌مانند — همگام‌سازی آن‌ها را بالا نمی‌فرستد.';

  @override
  String get recapRefreshFailed =>
      'خلاصه تازه نشد. آنچه پایین می‌بینی آخرین خلاصه‌ای است که نکس ساخته.';

  @override
  String get shareSaved => 'در نکس ذخیره شد.';

  @override
  String shareTooLarge(Object name, Object size, Object limit) {
    return 'نکس برای یادداشت است، نه فایل‌های سنگین. «$name» حجمش $size است و سقف ضمیمه $limit است.';
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
      'checklist': 'چک‌لیست',
      'link': 'لینک',
      'other': 'یادداشت',
    });
    return '$_temp0';
  }

  @override
  String get addAction => 'افزودن';

  @override
  String get all => 'همه';

  @override
  String get filterHasReminder => 'دارای یادآور';

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
  String get summarize => 'خلاصه‌سازی';

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
  String get tapToExpand => 'برای نمایش تمام‌صفحه روی تصویر بزنید';

  @override
  String similarity(String score) {
    return 'شباهت $score';
  }

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
  String get tryAgain => 'تلاش دوباره';

  @override
  String libraryOpenDetail(String error) {
    return 'مشکل: $error';
  }

  @override
  String get restoreBackupHint =>
      'اگر فایل پشتیبان دارید، بازگردانی آن در اینجا می‌تواند کتابخانه را بازیابی کند.';

  @override
  String restoreFailed(String error) {
    return 'بازگردانی ناموفق بود: $error';
  }

  @override
  String get updateAvailableBadge => 'به‌روزرسانی در دسترس است';

  @override
  String get closeLabel => 'بستن';

  @override
  String get timelineLoadFailed => 'مجموعه یادداشت‌ها بارگیری نشد.';

  @override
  String deletedWhen(String when) {
    return 'حذف‌شده $when';
  }

  @override
  String get filteredEmpty => 'یادداشت‌ها پشت پالایه‌ها پنهان شده‌اند.';

  @override
  String get clearFilters => 'پاک کردن پالایه‌ها';

  @override
  String get searchFilters => 'پالایه‌ها';

  @override
  String searchFiltersClear(int count) {
    return 'پاک کردن همه ($count)';
  }

  @override
  String get searchFilterTags => 'برچسب‌ها';

  @override
  String get searchFilterTypes => 'نوع‌ها';

  @override
  String get searchFilterDates => 'زمان افزودن';

  @override
  String get searchFilterAnyTime => 'همه زمان‌ها';

  @override
  String get searchFilterToday => 'امروز';

  @override
  String get searchFilterLast7Days => '۷ روز گذشته';

  @override
  String get searchFilterLast30Days => '۳۰ روز گذشته';

  @override
  String get searchFiltersHint =>
      'برای ترکیب انتخاب کنید. پالایه‌ها بی‌درنگ اعمال می‌شوند.';

  @override
  String searchFiltersActive(int count) {
    return '$count مورد فعال';
  }

  @override
  String get showFilters => 'نمایش پالایه‌ها';

  @override
  String get opening => 'Nex در حال باز شدن است';

  @override
  String get swipeActionsHint =>
      'هر طرف جداگانه تنظیم می‌شود. روی هر ردیف بزنید تا کارِ آن کشیدن را انتخاب کنید یا خاموشش کنید.';

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
  String get sendFeedbackSubtitle => 'نظرت درباره اپ رو بهمون بگو';

  @override
  String get feedbackHint => 'چی تو ذهنته؟';

  @override
  String get feedbackSend => 'ارسال';

  @override
  String get feedbackSent => 'بازخورد ارسال شد — ممنون از وقتی که گذاشتی';

  @override
  String get feedbackQueuedOffline =>
      'اینترنت وصل نیست — به محض وصل شدن ارسال می‌شود';

  @override
  String get feedbackFailed => 'ارسال نشد';

  @override
  String get feedbackUnavailable =>
      'قابلیت ارسال بازخورد هنوز در این نسخه فعال نیست';

  @override
  String get feedbackOpenIssueInstead => 'به‌جایش در گیت‌هاب ایشو باز کنید';

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
  String get changelogTitle => 'تاریخچهٔ تغییرات';

  @override
  String get changelogLatestHeading => 'جدیدترین تغییرات';

  @override
  String changelogVersionHeading(String version) {
    return 'نسخهٔ $version';
  }

  @override
  String get changelogEmpty => 'تاریخچهٔ تغییرات در دسترس نیست.';

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
  String get exportTitle => 'خروجی گرفتن';

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
  String get aiShow => 'ببینید Nex از این چه فهمیده';

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
  String get timeNow => 'الان';

  @override
  String timeMinutesAgo(int count) {
    return '$count دقیقه قبل';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count ساعت قبل';
  }

  @override
  String timeDaysAgo(int count) {
    return '$count روز قبل';
  }

  @override
  String timeWeeksAgo(int count) {
    return '$count هفته قبل';
  }

  @override
  String timeMonthsAgo(int count) {
    return '$count ماه قبل';
  }

  @override
  String timeYearsAgo(int count) {
    return '$count سال قبل';
  }

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
  String get retry => 'تلاش دوباره';

  @override
  String get cropPhotoTitle => 'برش عکس';

  @override
  String get cropConfirm => 'استفاده از عکس';

  @override
  String get cropRotate => 'چرخاندن';

  @override
  String get cropAnnotate => 'طراحی یا متن';

  @override
  String get cropCancel => 'دور ریختن عکس';

  @override
  String get annotateTitle => 'طراحی یا متن';

  @override
  String get annotateDraw => 'طراحی';

  @override
  String get annotateText => 'متن';

  @override
  String get annotateTextHint => 'چیزی بنویس…';

  @override
  String get annotateUndo => 'برگردان';

  @override
  String get annotateClear => 'پاک کردن همه';

  @override
  String get annotateDone => 'تمام';

  @override
  String get annotateTapToPlaceText => 'برای گذاشتن متن، روی عکس بزنید';

  @override
  String get tagColor => 'رنگ برچسب';

  @override
  String get customColor => 'دلخواه';

  @override
  String get brightness => 'روشنایی';

  @override
  String get noColor => 'بدون رنگ';

  @override
  String get defaultColor => 'پیش‌فرض';

  @override
  String get recentColors => 'استفاده‌شده‌های اخیر';

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
  String get aiProviderNoneSubtitleLocal =>
      'روی همین گوشی جواب می‌دهد، با مدلی که دانلود کرده‌ای.';

  @override
  String get aiProviderLocalNote =>
      'مدلی که روی گوشی‌تان هست متن می‌خواند و می‌نویسد، پس دستیار، خلاصهٔ روزانه و ترجمه را پوشش می‌دهد. صدا را نمی‌شنود و عکس را نمی‌خواند — آن‌ها هنوز به یک سرویس نیاز دارند.';

  @override
  String get aiProviderNoneSubtitle =>
      'روی همین دستگاه اجرا می‌شود. کلید لازم ندارد.';

  @override
  String get aiProviderSaved => 'سرویس ذخیره شد.';

  @override
  String get aiKeyStorage =>
      'کلید در حافظهٔ امن خود دستگاه نگه داشته می‌شود، نه در تنظیمات معمولی برنامه، و جز به همان سرویسی که انتخاب کرده‌اید جایی فرستاده نمی‌شود.';

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
  String get intelligenceConsentAccept => 'روشن کردن';

  @override
  String get intelligenceQuietNote =>
      'نتیجه‌ها بی‌سروصدا در پس‌زمینه آماده و کنار یادداشت نگه داشته می‌شوند. چیزی مزاحمتان نمی‌شود — خلاصه یا برچسب پیشنهادی فقط وقتی یادداشت را باز کنید و بخواهید دیده می‌شود.';

  @override
  String get chat => 'چت';

  @override
  String get chatSubtitle => 'از دستیار داخلی Nex بپرس';

  @override
  String get chatUnavailable => 'چت محلی هنوز روی این نسخه در دسترس نیست.';

  @override
  String get chatEmptyHint =>
      'هر چیزی بپرس — Nex همین‌جا روی گوشی، بدون نیاز به اینترنت جواب می‌دهد.';

  @override
  String get chatInputHint => 'پیام…';

  @override
  String get chatSendTooltip => 'ارسال';

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

  @override
  String get aiDaySummaryTitle => 'خلاصه هوشمند';

  @override
  String get aiDaySummarySemanticLabel => 'خلاصه امروز';

  @override
  String get aiDaySummaryEmpty => 'هنوز چیزی برای خلاصه کردن نیست.';

  @override
  String get aiDaySummaryRefresh => 'نوشتن خلاصه تازه';

  @override
  String get aiDaySummaryCollapse => 'بستن خلاصه';

  @override
  String get aiDaySummaryExpand => 'نمایش خلاصه';

  @override
  String get aiHeadlineRefresh => 'برای جمله‌ای تازه لمس کنید';

  @override
  String get aiOutputLanguage => 'زبان خروجی هوش مصنوعی';

  @override
  String get aiOutputLanguageSubtitle =>
      'زبانی که خلاصه‌ها و پیشنهادها با آن نوشته می‌شوند';

  @override
  String get aiOutputLanguageAuto => 'هم‌زبان با یادداشت‌هایم';

  @override
  String get aiOutputLanguageEnglish => 'انگلیسی';

  @override
  String get aiOutputLanguagePersian => 'فارسی';

  @override
  String get onboardingNext => 'بعدی';

  @override
  String get onboardingSkip => 'رد کردن';

  @override
  String get onboardingBack => 'قبلی';

  @override
  String get onboardingStart => 'شروع کنیم';

  @override
  String get onboardingWelcomeTitle => 'جایی برای زمین گذاشتن';

  @override
  String get onboardingWelcomeBody =>
      'هر چیزی در Nex بگذارید، می‌ماند. چیز دیگری از شما خواسته نمی‌شود — نه حسابی، نه صندوقی که باید خالیش کنید.';

  @override
  String get onboardingCaptureTitle => 'دکمهٔ ذخیره‌ای در کار نیست';

  @override
  String get onboardingCaptureBody =>
      'بنویسید، بگویید یا عکس بگیرید. یادداشت همان لحظه که می‌سازید مال شماست و بالای همان یک فهرست می‌نشیند — لازم نیست اول جایی برایش دسته‌بندی کنید.';

  @override
  String get onboardingIntelligenceTitle =>
      'می‌تواند آنچه ثبت می‌کنید را بخواند';

  @override
  String get onboardingIntelligenceBody =>
      'صدا متن می‌شود، متن داخل عکس‌ها درمی‌آید و برچسب‌ها خودشان پیشنهاد می‌شوند. تا وقتی در تنظیمات سرویسی اضافه نکنید خاموش است — بقیهٔ اپ بدون آن هم کار می‌کند.';

  @override
  String get onboardingSilenceTitle => 'هیچ‌وقت مزاحمتان نمی‌شود';

  @override
  String get onboardingSilenceBody =>
      'نه اعلانی، نه نشانی، نه یادآوری و نه زنجیرهٔ روزانه. یادداشت‌هایتان روی همین دستگاه می‌مانند، مگر خودتان همگام‌سازی را راه بیندازید.';

  @override
  String get onboardingSetupTitle => 'چند انتخاب کوتاه';

  @override
  String get onboardingSetupBody =>
      'همهٔ این‌ها بعداً در تنظیمات هستند و هیچ‌کدام همیشگی نیست.';

  @override
  String get onboardingNameRequired => 'Nex باید بداند شما را چه صدا کند.';

  @override
  String get checklist => 'چک‌لیست';

  @override
  String get link => 'لینک';

  @override
  String get checklistHint => 'هر خط یک مورد';

  @override
  String get linkHint => 'لینک را بچسبانید';

  @override
  String get linkNotValid => 'این شبیه لینک نیست.';

  @override
  String get openLink => 'باز کردن لینک';

  @override
  String checklistProgress(int done, int total) {
    return '$done از $total';
  }

  @override
  String get chatGreeting => 'امروز چه کمکی از من برمی‌آید؟';

  @override
  String get chatHint => 'چیزی بنویسید…';

  @override
  String get foreignImportTitle => 'درون‌ریزی یادداشت‌ها';

  @override
  String get foreignImportSubtitle =>
      'از گوگل کیپ، یا هر پوشه‌ای از فایل‌های ‏.md و ‏.txt';

  @override
  String get foreignImportWorking => 'دارم فایلت را می‌خوانم…';

  @override
  String foreignImportDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '‏$count یادداشت وارد شد.',
      one: 'یک یادداشت وارد شد.',
      zero: 'در آن فایل یادداشتی پیدا نشد.',
    );
    return '$_temp0';
  }

  @override
  String get foreignImportUnreadable =>
      'آن فایل خوانده نشد. همان ‏.zip دانلودشده، یا یک فایل ‏.json و ‏.md و ‏.txt را انتخاب کنید.';

  @override
  String get localModelPause => 'توقف موقت';

  @override
  String get localModelResume => 'ادامه';

  @override
  String get localModelStop => 'لغو';

  @override
  String localModelPaused(String done, String total) {
    return 'متوقف شده · $done از $total';
  }

  @override
  String localModelBytes(String done, String total) {
    return '$done از $total';
  }

  @override
  String get localModelLoading => 'در حال بالا آوردن مدل…';

  @override
  String get localModelStopTitle => 'دانلود لغو شود؟';

  @override
  String get localModelStopBody =>
      'هرچه تا حالا دانلود شده دور ریخته می‌شود و شروع دوباره از صفر خواهد بود. «توقف موقت» آن را نگه می‌دارد.';

  @override
  String get localModelManageInstalled => 'دانلود شده و روی گوشی آماده است';

  @override
  String get localModelManageMissing =>
      'هنوز دانلود نشده — دستیار برای کار آفلاین به آن نیاز دارد';

  @override
  String get localModelLoadFailed =>
      'مدل دانلود شده، ولی روی این گوشی بالا نیامد.';

  @override
  String get localModelLoadFailedDetail => 'چیزی که رانتایم گزارش کرد:';

  @override
  String get localModelTitle => 'مدل روی دستگاه';

  @override
  String get localModelSubtitle => 'چت بدون اینترنت، بعد از دانلود مدل';

  @override
  String get localModelExplained =>
      'Nex می‌تواند یک مدل زبانی را روی همین گوشی اجرا کند، طوری که چت بدون اینترنت کار کند و هیچ‌چیزی که می‌نویسید از دستگاه بیرون نرود. حجمش زیاد است و تا وقتی خودتان پاکش نکنید روی گوشی می‌ماند.';

  @override
  String localModelDownload(String size) {
    return 'دانلود · ‏$size گیگابایت';
  }

  @override
  String get localModelDownloading => 'در حال دانلود…';

  @override
  String localModelDownloadingPart(int index, int count) {
    return 'دانلود تکه‌ی ‏$index از ‏$count';
  }

  @override
  String get localModelJoining => 'در حال چسباندن تکه‌ها و بررسی‌شان…';

  @override
  String get localModelKeepOpen =>
      'می‌توانید از این صفحه بیرون بروید — دانلود ادامه پیدا می‌کند. بستن برنامه متوقفش می‌کند و دفعهٔ بعد از همان‌جا ادامه می‌دهد.';

  @override
  String get localModelReady => 'مدل آماده است. چت حالا آفلاین کار می‌کند.';

  @override
  String get localModelFailed =>
      'دانلود تمام نشد. دوباره بزنید — از همان‌جایی که ماند ادامه می‌دهد.';

  @override
  String localModelInstalled(String size) {
    return 'نصب‌شده · ‏$size گیگابایت روی این گوشی';
  }

  @override
  String get localModelDelete => 'حذف مدل';

  @override
  String get localModelDeleteTitle => 'مدل حذف شود؟';

  @override
  String get localModelDeleteBody =>
      'چت آفلاین تا وقتی دوباره دانلودش نکنید کار نمی‌کند. یادداشت‌هایتان دست‌نخورده می‌مانند.';

  @override
  String get localModelDeleted => 'مدل حذف شد.';

  @override
  String get localModelLicenseTitle => 'قبل از دانلود';

  @override
  String get localModelLicenseRead => 'متن کامل شرایط';

  @override
  String get localModelLicenseAccept => 'این شرایط را خوانده‌ام و می‌پذیرم';

  @override
  String get localModelBlockedPlatform =>
      'چت روی دستگاه فقط روی اندروید و آیفون کار می‌کند. این نسخه نمی‌تواند از آن استفاده کند.';

  @override
  String get localModelBlockedArchitecture =>
      'پردازنده‌ی این گوشی از آن‌هایی نیست که مدل رویش اجرا می‌شود. به یک دستگاه ARM شصت‌وچهار بیتی نیاز دارد.';

  @override
  String localModelBlockedStorage(String size) {
    return 'فضای کافی نیست. دانلود موقع نصب حدود ‏$size گیگابایت فضای خالی لازم دارد.';
  }

  @override
  String get localModelBlockedUnpublished =>
      'هنوز مدلی برای دانلود در این نسخه موجود نیست.';

  @override
  String get tourNext => 'بعدی';

  @override
  String get tourDone => 'فهمیدم';

  @override
  String get tourSkip => 'بی‌خیال';

  @override
  String get tourCaptureTitle => 'همه چیز از اینجا شروع می‌شود';

  @override
  String get tourCaptureBody =>
      'بزنید تا بنویسید، یا صدا و عکس و فایل بگذارید. نگهش دارید، به‌جایش با دستیار حرف می‌زنید.';

  @override
  String get tourSearchTitle => 'هر چیزی را پیدا کنید';

  @override
  String get tourSearchBody =>
      'با کلمه بگردید، یا با معنای یادداشت. ‏tag:work یا ‏type:link هم کار می‌کند.';

  @override
  String get tourLibraryTitle => 'برچسب‌ها و پاک‌شده‌ها';

  @override
  String get tourLibraryBody =>
      'برچسب‌هایتان اینجاست، و هر چیزی که پاک کرده‌اید هم — تا مدتی.';

  @override
  String get tourSettingsTitle => 'به سلیقهٔ خودتان';

  @override
  String get tourSettingsBody =>
      'اسم، پوسته، زبان، پشتیبان‌گیری، و سرویس هوشی که خلاصه‌ها را می‌نویسد.';

  @override
  String get tourCardsTitle => 'یک نکته‌ی آخر';

  @override
  String get tourCardsBody =>
      'یادداشت را از هر طرف که بکشید، کارهای سریعش می‌آید. هر طرف را در تنظیمات خودتان انتخاب می‌کنید.';

  @override
  String get translate => 'ترجمه';

  @override
  String get translateTo => 'به';

  @override
  String get translateWorking => 'در حال ترجمه…';

  @override
  String get translateFailed => 'ترجمه برنگشت.';

  @override
  String get translateSaveAsNote => 'ذخیره به‌عنوان یادداشت';

  @override
  String get translateSaved => 'به‌عنوان یادداشت تازه ذخیره شد.';

  @override
  String get chatSpeak => 'گفتن';

  @override
  String get chatTranscribing => 'دارم صدایت را می‌خوانم…';

  @override
  String get chatTranscribeFailed => 'از آن ضبط چیزی درنیامد.';

  @override
  String get chatSend => 'فرستادن';

  @override
  String get chatFailed =>
      'پاسخی نیامد. سرویس را در تنظیمات بررسی کنید یا دوباره تلاش کنید.';

  @override
  String get chatPromptSummarise => 'خلاصه کن این هفته چه ثبت کردم';

  @override
  String get chatPromptPlan => 'از یادداشت‌هایم یک فهرست کار بساز';

  @override
  String get chatPromptIdeas => 'بگو چه چیزی را دارم فراموش می‌کنم';

  @override
  String get assistantActionDone => 'به‌انجام رسید.';

  @override
  String get assistantActionFailed => 'انجام نشد.';

  @override
  String get assistantConfirmCreate =>
      'این را به‌عنوان یادداشت تازه ذخیره کنم؟';

  @override
  String get assistantConfirmEdit => 'متن این یادداشت را جایگزین کنم؟';

  @override
  String get assistantConfirmDelete =>
      'این یادداشت را به حذف‌شده‌های اخیر ببرم؟';

  @override
  String get assistantConfirmTags => 'برچسب‌های این یادداشت را تغییر بدهم؟';

  @override
  String get assistantApply => 'انجام بده';

  @override
  String chatAboutNote(String note) {
    return 'دربارهٔ: $note';
  }

  @override
  String get chatHistory => 'گفت‌وگوها';

  @override
  String get chatHistoryEmpty => 'هنوز گفت‌وگویی ذخیره نشده.';

  @override
  String get chatNewConversation => 'گفت‌وگوی تازه';

  @override
  String get chatClearHistory => 'حذف همه گفت‌وگوها';

  @override
  String get assistant => 'دستیار';

  @override
  String get assistantSubtitle => 'پروفایل شما، سبک پاسخ و آنچه می‌بیند';

  @override
  String get assistantCreativity => 'خلاقیت';

  @override
  String get assistantCreativityPrecise => 'دقیق';

  @override
  String get assistantCreativityBalanced => 'متعادل';

  @override
  String get assistantCreativityInventive => 'خلاقانه';

  @override
  String get assistantLength => 'طول پاسخ';

  @override
  String get assistantLengthBrief => 'کوتاه';

  @override
  String get assistantLengthStandard => 'معمولی';

  @override
  String get assistantLengthFull => 'کامل';

  @override
  String get assistantScope => 'فقط درباره یادداشت‌هایم';

  @override
  String get assistantScopeSubtitle =>
      'خاموش باشد به هر چیزی جواب می‌دهد، از جمله چیزهایی که در آن‌ها ضعیف است.';

  @override
  String get assistantInstruction => 'چطور جواب بدهد';

  @override
  String get assistantInstructionHint => 'کمی طنز در جواب‌ها باشد';

  @override
  String get assistantInstructionSubtitle =>
      'یادداشت خودتان به دستیار، که همراه هر سؤال فرستاده می‌شود. لحن را عوض می‌کند، نه اینکه چه کارهایی مجاز است.';

  @override
  String get assistantContext => 'یادداشت‌هایی که می‌بیند';

  @override
  String get assistantContextSlow =>
      'فرستادن ۱۰۰ یادداشت یا بیشتر هر سؤال را کندتر می‌کند — مدل قبل از جواب دادن همه‌شان را می‌خواند. روی مدل روی گوشی خیلی محسوس است.';

  @override
  String get assistantContextNone => 'هیچ‌کدام';

  @override
  String assistantContextCount(int count) {
    return '‏$count تای آخر';
  }

  @override
  String get askAboutNote => 'بپرس';

  @override
  String get saveSearch => 'ذخیره این جست‌وجو';

  @override
  String get savedSearches => 'ذخیره‌شده';

  @override
  String get assistantConfirmMerge => 'این یادداشت‌ها را یکی کنم؟';

  @override
  String get assistantConfirmChecklist => 'این را به چک‌لیست تبدیل کنم؟';

  @override
  String get assistantConfirmCheck => 'این آیتم را تیک بزنم؟';

  @override
  String get assistantConfirmSetting => 'این تنظیم را عوض کنم؟';

  @override
  String get remind => 'یادآوری';

  @override
  String get remindLater => 'یک ساعت دیگر';

  @override
  String get remindEvening => 'امشب';

  @override
  String get remindTomorrow => 'فردا صبح';

  @override
  String get remindNextWeek => 'هفته بعد';

  @override
  String get remindPick => 'انتخاب زمان…';

  @override
  String get remindClear => 'حذف یادآوری';

  @override
  String get nudgeTitle => 'یادآور روزانه';

  @override
  String get nudgeSubtitle =>
      'روزی یک نوتیفیکیشن، سر ساعتی که خودتان انتخاب می‌کنید';

  @override
  String get nudgeTime => 'ساعت';

  @override
  String get notifications => 'اعلان‌ها';

  @override
  String nudgeGreetingMorning(String name) {
    return 'صبح بخیر، $name';
  }

  @override
  String nudgeGreetingDay(String name) {
    return 'سلام، $name';
  }

  @override
  String get nudgeGreetingPlain => 'Nex';

  @override
  String get nudgeNothing =>
      'صفحه خالی است. هر وقت چیزی پیش آمد، Nex همین‌جاست.';

  @override
  String get localModelLicenseGloss =>
      'خلاصه‌اش: مدل مال گوگل است، شرایط خودش را دارد، و دانلودش یعنی پذیرفتن آن شرایط.';

  @override
  String get notificationTest => 'ارسال نوتیفیکیشن آزمایشی';

  @override
  String get notificationTestHint => 'یکی همین حالا، یکی ده ثانیه دیگر';

  @override
  String get notificationTestSent => 'فرستاده شد — یکی حالا، یکی ده ثانیه دیگر';

  @override
  String notificationTestFailed(String error) {
    return 'فرستاده نشد — $error';
  }

  @override
  String timeMinutesShort(int count) {
    return '$count دقیقه';
  }

  @override
  String timeHoursShort(int count) {
    return '$count ساعت';
  }

  @override
  String timeDaysShort(int count) {
    return '$count روز';
  }

  @override
  String get remindOverdue => 'گذشته';

  @override
  String remindWhenToday(String time) {
    return 'امروز ساعت $time';
  }

  @override
  String remindWhenTomorrow(String time) {
    return 'فردا ساعت $time';
  }

  @override
  String remindWhenOn(String date, String time) {
    return '$date ساعت $time';
  }

  @override
  String remindCurrent(String when) {
    return 'تنظیم‌شده برای $when';
  }

  @override
  String get remindChange => 'تغییر یادآور';

  @override
  String get swipeNoneHint => 'این لبه کاری نمی‌کند';

  @override
  String get swipeDeleteHint => 'یادداشت را به حذف‌شده‌های اخیر می‌برد';

  @override
  String get swipeAddTagHint => 'انتخاب برچسب برای یادداشت';

  @override
  String get swipePinHint => 'یادداشت را بالای تایم‌لاین نگه می‌دارد';

  @override
  String get swipeRemindHint => 'انتخاب اینکه کِی برگردد';

  @override
  String get swipeShareHint => 'یادداشت را به برنامهٔ دیگری بفرست';

  @override
  String get swipeAskHint => 'دستیار را روی همین یادداشت باز می‌کند';

  @override
  String get swipeLeadingEdge => 'کشیدن از چپ';

  @override
  String get swipeTrailingEdge => 'کشیدن از راست';

  @override
  String get filePreviewTooLarge =>
      'برای نمایش اینجا بزرگ است — با برنامهٔ دیگری بازش کنید.';

  @override
  String filePreviewUnreadable(String error) {
    return 'این فایل خوانده نشد — $error';
  }

  @override
  String tableTruncated(int count) {
    return 'فقط $count سطر اول نشان داده شده است.';
  }

  @override
  String get formatBold => 'پررنگ';

  @override
  String get formatItalic => 'کج';

  @override
  String get formatMono => 'مونو';

  @override
  String get formatStrikethrough => 'خط‌خورده';

  @override
  String get formatQuote => 'نقل‌قول';

  @override
  String get formatLink => 'پیوند';

  @override
  String get formatClear => 'ساده';

  @override
  String get documentTruncated => 'فقط ابتدای این سند نشان داده شده است — برای بقیه با برنامهٔ دیگری بازش کنید.';

  @override
  String get documentUnreadable => 'این سند اینجا نمایش داده نشد.';

  @override
  String get downloadStopped => 'دانلود قطع شد';

  @override
  String get resumeDownload => 'ادامه';

  @override
  String get updateDownloadingTitle => 'در حال دانلود به‌روزرسانی';

  @override
  String get updateReadyTitle => 'به‌روزرسانی آماده است';

  @override
  String get updateReadyBody => 'برای نصب ضربه بزنید';

  @override
  String get expandCard => 'نمایش کامل';

  @override
  String get collapseCard => 'نمایش دو خطی';

  @override
  String get guideTitle => 'نکس چطور کار می‌کند';

  @override
  String get guideSubtitle => 'هرچه اپ انجام می‌دهد، یک‌جا';

  @override
  String get guideUnavailable => 'راهنما باز نشد.';

  @override
  String get onboardingFilesTitle =>
      'هرچه بهش بدهی';

  @override
  String get onboardingFilesBody =>
      'یک سند، یک پی‌دی‌اف، یک آهنگ یا یک عکس را به نکس بفرست — خودِ آن چیز را نشانت می‌دهد، نه فقط اسم فایل را.';

  @override
  String get onboardingYoursTitle =>
      'مال خودت می‌ماند';

  @override
  String get onboardingYoursBody =>
      'نه حساب کاربری، نه سرور، و با اینترنتِ قطع هم کار می‌کند. اگر خواستی پشت اثر انگشتت قفلش کن، و هر وقت خواستی همه‌اش را بیرون بکش.';

  @override
  String get onboardingGuideTitle =>
      'نمی‌دانی چیزی کجاست؟';

  @override
  String get onboardingGuideBody =>
      'راهنما همه‌چیز را قدم‌به‌قدم می‌گوید، و همیشه در تنظیمات هست.';

  @override
  String get onboardingGuideOpen =>
      'راهنما را بخوان';

  @override
  String get addLink => 'افزودن پیوند';

  @override
  String get linkAddress => 'نشانی';

  @override
  String remindSetIn(String when) {
    return 'یادآور تنظیم شد — $when دیگر';
  }

  @override
  String remindInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count روز',
      one: '۱ روز',
    );
    return '$_temp0';
  }

  @override
  String remindInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ساعت',
      one: '۱ ساعت',
    );
    return '$_temp0';
  }

  @override
  String remindInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count دقیقه',
      one: '۱ دقیقه',
    );
    return '$_temp0';
  }

  @override
  String get remindNotScheduled =>
      'آن زمان روی یادداشت ذخیره شد، ولی این گوشی آلارمش را قبول نکرد.';

  @override
  String get remindSet => 'یادآوری تنظیم شد';

  @override
  String get remindDenied => 'برای ارسال اعلان، اجازه لازم است.';

  @override
  String get micDenied =>
      'برای ضبط صدا، اجازه دسترسی به میکروفون لازم است. می‌توانید آن را در تنظیمات برنامه در دستگاهتان بدهید.';

  @override
  String get searchFailed => 'این جست‌وجو انجام نشد.';

  @override
  String get summarizeFailed => 'برای این یادداشت خلاصه‌ای برنگشت.';
}
