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
  String get searchHint => 'جست‌وجوی یادداشت‌ها…';

  @override
  String get searchStart => 'برای یافتن یک یادداشت شروع به تایپ کنید.';

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
  String filtersCount(int count) {
    return 'فیلترها ($count)';
  }

  @override
  String get date => 'تاریخ';

  @override
  String get clear => 'پاک کردن';

  @override
  String resultCount(int count) {
    return '$count نتیجه';
  }

  @override
  String nothingMatches(String query) {
    return 'چیزی با «$query» پیدا نشد.';
  }

  @override
  String get closestThing => 'نزدیک‌ترین چیزی که نوشته‌اید:';

  @override
  String get nothingClose => 'چیز نزدیکی هم پیدا نشد.';

  @override
  String get emptyPromise => 'هرچه اینجا بگذارید، نگه داشته می‌شود.';

  @override
  String get emptySupport => 'هیچ چیز دیگری از شما خواسته نمی‌شود.';

  @override
  String get emptyType => 'بنویسید';

  @override
  String get emptySpeak => 'بگویید';

  @override
  String get emptyPhotograph => 'عکس بگیرید';

  @override
  String get emptyNoSave => 'دکمهٔ ذخیره‌ای وجود ندارد.';

  @override
  String get delete => 'حذف';

  @override
  String get addTag => 'افزودن برچسب';

  @override
  String get noteDeleted => 'یادداشت حذف شد';

  @override
  String get undo => 'واگرد';

  @override
  String get cancel => 'لغو';

  @override
  String get restore => 'بازیابی';

  @override
  String get rename => 'تغییر نام';

  @override
  String get merge => 'ادغام';

  @override
  String get tags => 'برچسب‌ها';

  @override
  String get tagActions => 'عملیات برچسب';

  @override
  String noteCount(int count) {
    return '$count یادداشت';
  }

  @override
  String get renameTag => 'تغییر نام برچسب';

  @override
  String get deleteTag => 'برچسب حذف شود؟';

  @override
  String get deleteTagBody =>
      'این کار برچسب را از یادداشت‌ها برمی‌دارد و خود یادداشت‌ها را حذف نمی‌کند.';

  @override
  String get recentlyDeleted => 'اخیراً حذف‌شده';

  @override
  String get recentlyDeletedEmpty => 'چیزی اخیراً حذف نشده است.';

  @override
  String get appearance => 'ظاهر';

  @override
  String get language => 'زبان';

  @override
  String get accessibility => 'دسترس‌پذیری';

  @override
  String get reduceMotion => 'کاهش حرکت';

  @override
  String get haptics => 'بازخورد لمسی ثبت';

  @override
  String get quietAnniversary => 'نمایش خط سالگرد آرام';

  @override
  String get intelligence => 'هوشمندی';

  @override
  String get intelligenceLocal =>
      'مگر با فعال‌کردن هوش ابری، همه‌چیز روی همین دستگاه اجرا می‌شود.';

  @override
  String get about => 'دربارهٔ Nex';

  @override
  String get localFirstTitle => 'ذخیره‌شده روی دستگاه';

  @override
  String localFirstBody(String path) {
    return 'یادداشت‌های شما در این دستگاه و در $path نگه‌داری می‌شوند';
  }

  @override
  String get copyPath => 'کپی مسیر داده';

  @override
  String get silenceTitle => 'سکوت یک قابلیت است';

  @override
  String get silenceBody =>
      'Nex هرگز اعلان، نشان، یادآور یا پیام بازگشت ارسال نمی‌کند.';

  @override
  String get privacy => 'حریم خصوصی';

  @override
  String get privacyBody =>
      'ثبت و جست‌وجوی اصلی یادداشت‌های شما را جمع‌آوری یا منتقل نمی‌کند.';

  @override
  String get openSourceLicenses => 'مجوزهای متن‌باز';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';

  @override
  String get themeSystem => 'سیستم';

  @override
  String get comfortMode => 'حالت آسایش';

  @override
  String get comfortModeSubtitle =>
      'کنتراست کمتر و رنگ‌های گرم‌تر، مستقل از روشن یا تیره';

  @override
  String get languageSystem => 'سیستم';

  @override
  String get languageEnglish => 'انگلیسی';

  @override
  String get languagePersian => 'فارسی';

  @override
  String get quietAnniversarySubtitle =>
      'فقط داخل Nex؛ هرگز اعلان یا نشان نیست.';

  @override
  String get storage => 'فضای ذخیره‌سازی';

  @override
  String storageUsed(String size) {
    return '$size روی دستگاه استفاده شده';
  }

  @override
  String get stopRecording => 'توقف ضبط';

  @override
  String recordingElapsed(String elapsed) {
    return 'در حال ضبط، $elapsed';
  }

  @override
  String get discard => 'دور انداختن';

  @override
  String get captureFailed =>
      'ثبت ذخیره نشد. یادداشت‌های قبلی شما تغییری نکردند.';

  @override
  String oneYearAgo(int count) {
    return 'یک سال پیش · $count ثبت';
  }

  @override
  String get noteNotFound => 'یادداشت پیدا نشد';

  @override
  String get mediaUnavailable => 'این فایل رسانه در دسترس نیست.';

  @override
  String get copy => 'کپی';

  @override
  String get share => 'اشتراک‌گذاری';

  @override
  String get swipeActions => 'عملیات کشیدن';

  @override
  String get swapSwipeMapping => 'جابه‌جایی عملیات ابتدا و انتها';

  @override
  String get transcription => 'رونویسی صدا';

  @override
  String get ocr => 'تشخیص متن تصویر';

  @override
  String get tagSuggestions => 'پیشنهاد برچسب';

  @override
  String get semanticSearch => 'جست‌وجوی معنایی';

  @override
  String get summarization => 'خلاصه‌سازی';

  @override
  String get relatedNotes => 'یادداشت‌های مرتبط';

  @override
  String get cloudAi => 'هوش ابری (انتخابی)';

  @override
  String get cloudAiSubtitle =>
      'به‌طور پیش‌فرض خاموش است و ثبت اصلی بدون آن کار می‌کند.';

  @override
  String get sync => 'همگام‌سازی';

  @override
  String get syncNow => 'همگام‌سازی اکنون';

  @override
  String get syncComplete => 'همگام‌سازی انجام شد';

  @override
  String get export => 'خروجی';

  @override
  String exportedTo(String path) {
    return 'خروجی در $path ذخیره شد';
  }

  @override
  String get restoreBackup => 'بازیابی پشتیبان';

  @override
  String get restoreBody =>
      'پایگاه دادهٔ محلی با جدیدترین پشتیبان تأییدشده جایگزین شود؟';

  @override
  String backupCount(int count) {
    return '$count پشتیبان';
  }

  @override
  String get operationFailed =>
      'عملیات انجام نشد. یادداشت‌های قبلی شما تغییر نکردند.';

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
}
