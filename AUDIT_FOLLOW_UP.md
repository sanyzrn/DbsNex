# Audit follow-up

## وضعیت فعلی — ۲۰۲۶/۰۹/۲۶

محدودهٔ مورد تأیید: موارد **۱ تا ۳۵**؛ ادامهٔ ۱۷ به بعد در جدول زیر ثبت شده است. همهٔ تغییرات روی `codex/work` هستند؛
این نوبت زیر **Unreleased** ثبت شده و نسخه یا تگ جدیدی انتخاب نشده است.
تست‌های عملی گوشی، امولاتور و نصب روی نسخهٔ قبلی به درخواست مالک اجرا نشده‌اند.
بخش‌های انگلیسی بعد از این گزارش، سابقهٔ بررسی نسخهٔ 1.40.0 هستند.

| مورد | نتیجهٔ کار روی کد و بررسی خودکار | بررسی عملی با مالک |
| --- | --- | --- |
| ۱. حفظ اطلاعات هنگام آپدیت | نوشتن اتمی و ترتیبی نسخهٔ کمکی پروفایل؛ بازیابی کلید همگام‌سازی پس از اجرای مجدد؛ حفاظت‌های قبلی مسیر مدل/هویت نصب حفظ شد | نصب روی نسخهٔ منتشرشده و بررسی پروفایل، مدل، تنظیمات و قفل |
| ۲. پایداری اشتراک‌گذاری | صف تأییدشونده و جلوگیری از تکرار قبلی حفظ شد؛ هماهنگی دو Activity و ترتیب ورود اضافه شد؛ شناسهٔ ورودی بیرونی پذیرفته نمی‌شود | فشار ۱۵۰ اشتراک، اجرای سرد و گرم و هم‌زمانی |
| ۳. ماندگاری فایل اشتراکی | کپی زودهنگام در حافظهٔ داخلی، فایل موقت و تغییر نام پس از تکمیل، تلاش برای نگه‌داشتن مجوز و آزادکردن آن بعد از تأیید | قطع فرایند و انقضای مجوز؛ مرگ برنامه پیش از تکمیل کپی از ارائه‌دهندهٔ بدون مجوز پایدار همچنان نیازمند ارسال مجدد است |
| ۴. بازیابی بکاپ | نسخهٔ ایمنی، حفاظت از قدیمی‌ترین نسخه در زمان پاک‌سازی، انتقال درست مسیر عکس‌ها و کنترل CRC/فایل گمشده؛ تست بازگشت سالم پس از خطا | آرشیو قدیمی، یادآورها و بازیابی روی دستگاه دیگر |
| ۵. هماهنگی رسانه و دیتابیس | فایل‌های مرجع snapshot بررسی و با SHA-256 تثبیت می‌شوند؛ تغییر/حذف هم‌زمان باعث رد بکاپ ناقص می‌شود | ویرایش و حذف حین بکاپ واقعی |
| ۶. پیش‌نویس پس از بسته‌شدن ناگهانی | ثبت پایدار متنِ کادر ثبت سریع و بازیابی با شناسهٔ ثابت؛ تکرار بازیابی یادداشت تکراری نمی‌سازد | بستن اجباری هنگام تایپ؛ این قابلیت برای کادر ثبت سریع متن است، نه تمام ویرایشگرها |
| ۷. خرابی مخزن امن کلیدها | خطای Keystore مانع بازشدن کتابخانه نمی‌شود؛ کلید قدیمی فقط پس از تأیید ذخیرهٔ امن حذف می‌شود | انتقال دستگاه؛ کلید غیرقابل‌رمزگشایی ممکن است نیازمند ورود مجدد باشد |
| ۸. ورود فایل خصوصی | ورودی خارجی فقط از content provider پذیرفته می‌شود؛ مسیر file:// و provider خود اپ رد می‌شوند | ارائه‌دهندهٔ مخرب، لینک نمادین و مسیرهای خصوصی |
| ۹. خطای تغییر قفل | اصلاح احراز هویت نسخهٔ قبلی حفظ شد؛ تست‌های خودکار قفل در مجموعهٔ کلاینت | لغو/خطای احراز هویت و تغییر قفل در تنظیمات سیستم |
| ۱۰. حجم بکاپ‌ها | رسانهٔ یکسان در هر پوشهٔ بکاپ یک‌بار ذخیره می‌شود؛ اشتراک‌گذاری خروجی کامل می‌سازد؛ جمع‌آوری فایل بی‌مرجع با مهلت ۷ روز | بررسی فضای مصرفی روی گوشی |
| ۱۱. بررسی ۴۰۰ مگابایتی | ابزار مستقل میزبان برای snapshot، دو بکاپ، خروجی کامل، بازیابی، export/import؛ مشکل بافر کامل ZIP رفع شد | اعداد حافظه و زمان اندروید جداگانه سنجیده شوند |
| ۱۲. سازگاری ZIP | خواندن آرشیو و کنترل CRC با Python و Java موفق؛ دادهٔ فارسی داخل نمونه وجود دارد | انتقال فایل خروجی به برنامه‌های مورد استفادهٔ مالک |
| ۱۳. پاک‌سازی فایل موقت | فایل‌های خروجی و staging متعلق به اپ بعد از ۷ روز پاک می‌شوند؛ فایل تازه و فایل بی‌ارتباط حفظ می‌شود | اشتراک به برنامه‌ای که فایل را با تأخیر می‌خواند |
| ۱۴. انتخاب متن فارسی | تست چندخطی فارسی/انگلیسی، محدودهٔ انتخاب و composing و ثبات منوی متن اضافه شد؛ رفتار لمس بدون بازتولید بازنویسی نشد | دسته‌های انتخاب با کیبورد واقعی و RTL هنوز تأیید نشده‌اند |
| ۱۵. خطاهای ویرایش عکس | خروج امن از خطای چرخش/ذخیره، آزادسازی تصویر بومی، انتظار برای ابعاد واقعی، توقف تعامل حین ذخیره و رعایت هر دو حاشیهٔ سیستم | عکس بزرگ، ژست‌ها، برش و حاشیه‌های اندروید |
| ۱۶. حجم عکس ویرایش‌شده | JPEG اولیه در صورت کاهش حداقل ۲۰٪ حجم، با کیفیت ۹۵ و بدون تغییر ابعاد ذخیره می‌شود؛ PNG و شفافیت حفظ می‌شوند | مقایسهٔ چشمی کیفیت تصاویر |

### نتیجهٔ بررسی مصنوعی ۴۰۰ MiB روی ویندوز

ابزار: `packages/data/tool/backup_benchmark.dart`؛ داده ساختگی است و کتابخانهٔ
نصب‌شدهٔ مالک باز نشده. اجرای AOT کامپایل‌شده: snapshot حدود **۴ ms**، بکاپ اول
**۵٫۴ s**، بکاپ دوم **۹٫۴ s**، آماده‌سازی خروجی کامل **۹٫۱ s**، بازیابی **۲٫۲ s**،
export **۲ s** و import **۲ s**؛ اوج RSS کل فرایند **۵۱٬۷۱۲٬۰۰۰ بایت**.
دو بکاپ محلی مجموعاً یک فایل رسانه‌ای **۴۰۰ MiB** و دو آرشیو کوچک دارند؛
آرشیو دوم حدود **۵ KiB** است. بکاپ دوم برای کنترل سلامت، منبع و نسخهٔ مشترک را
دوباره هش می‌کند؛ صرفه‌جویی مربوط به فضاست و الزاماً زمان کمتر نیست.

مقایسهٔ JIT روی همان میزبان: قبل از اصلاح ZIP، export حدود **۴۹ s** و اوج RSS
**۱٫۵۶ GB**؛ پس از اصلاح، export حدود **۲ s** و RSS حدود **۴۷۵ MB**.
اعداد AOT و JIT مستقیماً قابل‌مقایسه نیستند و هیچ‌کدام اندازه‌گیری گوشی نیستند.
فایل‌های بزرگ‌تر از ۸ MiB بدون فشرده‌سازی مجدد داخل ZIP قرار می‌گیرند؛ در نتیجه
برای فایل‌های ذاتاً فشرده‌پذیر، آرشیو ممکن است بزرگ‌تر باشد.

### محدودیت باقی‌ماندهٔ ساخت

بررسی نهایی کد فعلی: **۶۸۰ تست کلاینت موفق، ۲ مورد skip**؛ **۱۵۸ تست داده
موفق، ۱۳ مورد skip**. تحلیل ایستای هر دو بخش بدون ایراد است؛ `git diff --check`
نیز پاک است و دو فایل changelog یکسان‌اند. گزارش‌های میزبان در `%TEMP%`:
`nex-next-client-verified.log`، `nex-next-data-final.log`،
`nex-next-client-analyze-final.log`، `nex-next-data-analyze-final.log` و
`nex-next-benchmark-aot.log`. Skipها به معنی اجرای موفق آن سناریوها نیستند.

ساخت APK محلی این نوبت پیش از کامپایل کد متوقف شد: Gradle نتوانست
`com.android.application:9.3.2` را دریافت کند. تنظیمات ابزار ساخت تغییر نکرد.
CI سبز PR #249 متعلق به کد نسخهٔ قبلی است و تغییرات جدید Kotlin را تأیید نمی‌کند؛
پیش از انتشار این دسته، بیلد CI لازم است.

## ادامهٔ کار — موارد ۱۷ تا ۳۵

تغییرات این بخش نیز روی همان `codex/work` و زیر `Unreleased` هستند؛ مالک در ادامه، کامیت و پوش همهٔ تغییرات را درخواست کرد.
تگ و استقرار سرویس جزو این درخواست نیست. جدول ۱–۱۶ و اعداد بالای
آن، نتیجهٔ مرحلهٔ قبلی‌اند؛ نتیجهٔ بررسی نهایی این مرحله پایین همین جدول است.

| مورد | نتیجهٔ کد / بررسی خودکار | باقی‌مانده یا مرز بررسی |
| --- | --- | --- |
| ۱۷. مجوز دوربین و میکروفن | اقدام «تنظیمات» پس از رد مجوز؛ متن بنر کامل و دکمهٔ قابل لمس | رد دائمی/بازگشت از تنظیمات سیستم با مالک |
| ۱۸. خطای دستیار | تفکیک شبکه، timeout، احراز هویت، محدودیت درخواست و خرابی سرویس؛ تلاش مجدد بدون تکرار سؤال و بدون پاک‌شدن پیش‌نویس تازه؛ حذف دستگیرهٔ تکراری | رفتار ارائه‌دهندهٔ واقعی و مدل آفلاین با مالک |
| ۱۹. خروجی نامناسب AI | حذف پاکت reasoning و رد آغازهای شناخته‌شدهٔ prompt echo فارسی/انگلیسی؛ اعمال بر پاسخ جدید و کش قدیمی و ویجت؛ تازه‌سازی خوشامد با نگه‌داشتن | این قواعد تشخیص محدودند، نه تضمین صحت تمام متن‌های مدل |
| ۲۰. فیلترها | پشت‌زمینهٔ کاملاً مات؛ نمایش عنوان نوع محتوای فعال/یادآور؛ حفظ پاک‌کردن همهٔ فیلترها | اسکرول واقعی و پس‌زمینه‌های مختلف با مالک |
| ۲۱. صوت | مدت یکسان دقیقه:ثانیه روی کارت و پخش‌کننده؛ مدت‌های بیش از یک ساعت درست؛ حذف عنوان مدت تکراری و Copy بدون متن | شکل موج ذخیره‌شده هنوز وجود ندارد؛ پیش‌نمایش از عنوان/توضیح و مدت استفاده می‌کند |
| ۲۲. ویجت اندروید | اصلاح ارتفاع سربرگ/دکمه، ردیف قابل رشد و فضای انتهای فهرست؛ زبان و جهت مطابق اپ؛ رنگ accent و تضاد متن ویجت ثبت؛ نام یکسان خلاصه | فقط اعتبارسنجی XML انجام شد؛ کامپایل Kotlin و لانچر واقعی هنوز لازم است |
| ۲۳. سناریوهای عملی | طبق درخواست مالک اجرا نشد | نصب تازه، خالی، آفلاین، پرشدن دیسک و استفادهٔ طولانی با مالک |
| ۲۴. تقویم و ارقام | گزینهٔ تقویم شمسی؛ تاریخ دقیق جزئیات، تاریخ بکاپ و یادآورها؛ ارقام فارسی در تاریخ و مدت صوت؛ اصلاح محاسبهٔ روز یادآور هنگام تغییر ساعت فصلی | انتخاب‌گر تولد و تعهدات هنوز کنترل تقویم قبلی را دارند؛ زمان ذخیره‌شده تغییر نمی‌کند |
| ۲۵. زبان | برچسب‌های اولیهٔ دست‌نخورده در فارسی ترجمه می‌شوند؛ داده/نام‌های کاربر تغییر نمی‌کند؛ جستجوی برچسب با هر دو نام؛ عنوان Smart summary / خلاصه هوشمند یکسان | بازخوانی لحن همهٔ متن‌های تاریخی پروژه جزو این اصلاح محدود نبود |
| ۲۶. تم تیره | زمینهٔ معرفی دستیار با رنگ سطح و accent کم‌رنگ؛ حاشیهٔ مناسب زیر توضیح تنظیمات | مرور چشمی روی دستگاه با مالک |
| ۲۷. مرزبندی | لبهٔ ظریف کارت‌ها و مرز قوی‌تر در کنتراست بالا؛ مرز سطح غیرشیشه‌ای نیز کنتراست بالا را رعایت می‌کند | بررسی چشمی تمام پس‌زمینه‌ها با مالک |
| ۲۸. دسترس‌پذیری | هدف لمس ۴۸ در برچسب/بنر؛ برچسب‌های فارسی؛ Retry قابل دسترسی؛ نگه‌داشتن اقدام بنر هنگام فعال‌بودن پیمایش دسترس‌پذیر؛ اقدام صفحه‌کلید خوشامد | TalkBack واقعی و ترتیب پیمایش با مالک |
| ۲۹. فونت بزرگ و حرکت | ارتفاع متناسب جستجو/فیلتر، یادآور قابل اسکرول، چرخ بزرگ‌تر و رعایت کاهش حرکت؛ تست ۲ برابر روی سطح ۳۲۰×۵۶۸ | تنظیمات فونت و کنتراست خود سیستم با مالک |
| ۳۰. صفحهٔ کوچک | خوشامد فشرده‌تر و فضای بالای کمتر در ارتفاع زیر ۷۰۰؛ کنترل‌ها حداقل لمس را حفظ می‌کنند | مرور صفحهٔ اصلی روی گوشی کوچک با مالک |
| ۳۱. جزئیات کوچک | نماد برچسب بدون رنگ به‌جای حلقهٔ شبیه رادیو؛ آیکون چیدمان جدید؛ حذف گسترش بی‌معنی رسانهٔ بدون متن؛ توضیح حذف پس از ۳۰ روز از قبل موجود است | تغییر اضافی در چیدمان تأییدشدهٔ جزئیات اعمال نشد |
| ۳۲. سند طراحی | سند `docs/05-design.md` مطابق تصمیم مالک دربارهٔ حذف زمان از کارت و منوی جزئیات اصلاح شد | تصمیم قدیمی مالک برگردانده نشد |
| ۳۳. بازخورد تلگرام | محدودکنندهٔ ۱۰ درخواست/دقیقه به‌ازای IP با binding؛ رد درخواست هنگام نبود limiter؛ سقف واقعی ۸ KiB و timeout؛ تست‌ها بدون ارسال پیام واقعی | استقرار نیازمند حساب Cloudflare، توکن ربات، chat ID و URL ریلیز است؛ namespace باید برای حساب انتخاب شود |
| ۳۴. ویندوز | حداقل اندازهٔ پنجره متناسب DPI؛ منوی راست‌کلیک و Shift+F10 برای بازکردن، برچسب و حذف با Undo موجود | کامپایل C++ و پذیرش ویندوز با مالک؛ انتشار ویندوز آغاز نشده |
| ۳۵. حریم خصوصی و وابستگی‌ها | لاگ ریلیز نوع خطا/stack را نگه می‌دارد؛ URL و کلیدهای رایج در فایل تشخیص پاک‌سازی می‌شوند؛ خطای صف ویجت پس از قفل رفع و با خواندن معلق واقعی تست شد؛ npm audit سرور و worker صفر هشدار | بررسی Pub از OSV با HTTP 403 متوقف شد؛ ترافیک واقعی SDK/ارائه‌دهنده و بسته‌های بومی هنوز تأیید نشده‌اند |

### مدارک بررسی این مرحله

- بررسی نهایی با Flutter **3.35.5** و وابستگی‌های کش‌شده: **۶۹۱ تست کلاینت موفق، ۲ skip**؛ **۱۵۷ تست UI موفق**. Skip به معنی قبولی آن سناریو نیست.
- آزمون بنر فارسی با فونت ۲ برابر، یادآور شمسی در عرض ۳۲۰، Retry با پیش‌نویس تازه، راست‌کلیک/Shift+F10، مرز نوروز و حفظ نام برچسب کاربر.
- آزمون رقابت ویجت: خواندن کتابخانه عمداً معلق می‌شود، قفل باید فوراً فایل را خالی کند و تکمیل خواندن قبلی نباید متن خصوصی را برگرداند.
- هر **۵ layout** ویجت از کنترل‌های قابل استفاده در RemoteViews تشکیل شده‌اند؛ این بررسی جای کامپایل و اجرای اندروید نیست.
- Worker: **۱۱ تست موفق**، TypeScript بدون خطا؛ Telegram کاملاً mock شده است.
  بسته‌بندی `wrangler deploy --dry-run` با ابزار کش‌شدهٔ **4.118.0** موفق بود و binding محدودکننده را شناخت؛ چیزی deploy نشد. این ابزار از نسخهٔ lockfile قدیمی‌تر است، پس نصب دقیق وابستگی‌های CI هنوز مرجع بیلد ریلیز است.
- `npm audit` برای backend و feedback-worker در ۲۰۲۶/۰۹/۲۶: **صفر هشدار شناخته‌شده**؛ نتیجهٔ Pub به‌دلیل HTTP 403 نامشخص است. هیچ ارتقای حدسی وابستگی انجام نشد.
- گزارش‌ها در `%TEMP%`: `nex-ux-client-final.log`، `nex-ux-ui-final.log`،
  `nex-ux-analyze-final.log`، `nex-ux-ui-analyze.log`، `nex-ux-widget-privacy.log`،
  `nex-ux-worker-test-final.log`، `nex-ux-worker-types-final.log`،
  `nex-ux-backend-audit.json`، `nex-ux-worker-audit.json` و `nex-ux-pub-advisories.json`.

### جمع‌بندی موارد واقعاً باز پس از این مرحله

- بیلد بومی Android/Windows و CI همین تغییرات؛ اعداد تست بالا جای کامپایل Kotlin/C++ نیستند.
- تست‌های عملی موارد ۱–۳۵ با مالک، از جمله انتخاب متن چندخطی فارسی که با ژست واقعی هنوز بازتولید/تأیید نشده است.
- تکمیل مورد ۳۵: استعلام آسیب‌پذیری وابستگی‌های Flutter/Pub و بسته‌های بومی؛ بررسی ترافیک واقعی SDKها.
- تکمیل مورد ۳۳: استقرار بازخورد تلگرام و تنظیم متغیر URL ریلیز.
- تکمیل‌های رابط: شکل موج صوت، تقویم شمسی برای انتخاب‌گر تولد/تعهدات، بازخوانی فراگیر لحن/اعداد فارسی و راهنمای درون‌برنامه‌ای مطابق قابلیت‌های تازه.
- از محدودیت‌های قدیمی: پیش‌نویس پایدار پس از بسته‌شدن اجباری فقط در ثبت سریع متن است؛ سایر ویرایشگرها فقط محافظ خروج دارند. نشانهٔ واضح‌تر پیمایش نسبت‌های کراپ نیز در اصلاح فعلی اضافه نشده است.
- بکاپ کتابخانه عمداً تنظیمات، کلیدها و مدل دانلودشده را شامل نمی‌شود؛ پوشش آن‌ها توسعهٔ جداگانه است، نه ادعای قابلیت فعلی.
- ایده‌های بخش «ایده» و برنامهٔ 2.0 در `docs/NEX_V2_ROADMAP.md` پیشنهادهای آینده‌اند؛ این مرحله تعهد اجرای آن‌ها نبود.
- انتخاب نسخهٔ بعدی، انتقال Unreleased، ادغام و تگ پس از عبور از گیت‌های انتشار.

### پیش از انتشار

۱. بیلد CI برای تغییرات Kotlin و C++؛ مانع Gradle مرحلهٔ قبلی همچنان رفع‌شده اعلام نمی‌شود.
۲. تست‌های عملی انتخاب‌شدهٔ مالک، به‌ویژه آپدیت روی نسخهٔ منتشرشده، قفل/ویجت و رسانه.
۳. انتخاب نسخهٔ بعدی و انتقال Unreleased؛ نسخه و تگ فقط از `DbsNex-releases` بررسی شوند.
۴. فقط در صورت فعال‌کردن بازخورد، تنظیم و استقرار سرویس مطابق README همان پوشه.

---

## سابقهٔ نوبت قبلی — 1.40.0

Updated: 2026-09-25. Latest verified release: **v1.30.0** in
`sanyzrn/DbsNex-releases`. Work stays on **codex/work**; do not create branches,
tag, or publish a release. Current changes are prepared under **v1.40.0**;
the owner requested commit/push and will create the tag after verification.

## Scope agreed with the owner

Finish important fixes only. Token budget is limited. Leave additional design,
feature and feedback-service work for a later session. Do not restart a full
audit or deploy the Telegram worker without a new request.

Sources: `Summary_AUDIT.md`, `Summary_AUDIT - ui.md` on the owner's Desktop,
and `NEX_UX_AUDIT.md`. The older `NEX_RELEASE_AUDIT.md` describes an earlier
release and must not be treated as a list of newly reproduced regressions.

## Implemented in the current working tree

- D1–3, D7–8: acknowledged share queue, transactionally deduplicated captures,
  success only after saving, short attachment filenames, SQLite busy timeout,
  serialized text-draft flush including close during the initial insert.
- D4–6 (partial), D9–11, D21: portable full-library backup share/import;
  streamed media in transfer ZIPs; UTF-8 byte lengths; consistent SQLite
  snapshot followed by compression outside the DB worker; safety backup before
  restore; failed restore requests a service restart; unsafe ZIP paths rejected.
- D12–15: unavailable device-auth explanation/settings link while keeping the
  app locked; discard confirmation; explicit update download; corrected backup,
  reminder and cloud-context descriptions.
- D16: external share copy refuses this app's private files and own provider.
- D18–20 (partial): explicit model reasoning envelopes filtered, known greeting
  prompt echoes rejected, Markdown release notes, translated media fallback
  labels and left-to-right file metadata.
- D23–24 (partial): CI path coverage and AI import boundary strengthened;
  release/source-repository comments and current handoff updated.
- UX already implemented: crop/annotation app swipe-back disabled, crop
  viewport constrained/inset, editor draft guard, stable Send position,
  explicit clipboard paste, filter reset/All state, contain photo previews,
  visible off-state switches, several 48dp targets and accessibility labels.

These are code changes, not a claim that all audit findings or device scenarios
are closed. Keep existing changes; do not redo this list from scratch.

## Required before release — highest priority

1. **Android build and device acceptance.** Local build stopped before code
   compilation because AGP `com.android.application:9.3.2` could not resolve
   from the configured repositories. Dart tests do not compile Kotlin. Obtain
   a successful native build/CI result; do not downgrade build tools blindly.
2. **Real share stress/recovery.** Repeat the 150-share test on Android with
   unique markers, warm/cold launches, simultaneous edits, locked DB and failed
   copy. Verify no loss/duplicates and no false Saved. Test activity recreation,
   process termination and expired content-URI permission: queued metadata does
   not itself preserve the source file's read permission. Verify queue ordering.
3. **Private-file import protection.** Reproduce D16 using file URI, symlink,
   own FileProvider and external storage variants on Android. Current copy
   guard covers app dataDir and own provider; verify all private roots.
4. **Restore/upgrade acceptance.** Test valid/corrupt/legacy backups, reminders,
   recurring items, assistant memory and media on a second sandbox. Test
   restoring the oldest recovery copy at the retention limit. Install over the
   released app with the same identity/signature; verify profile, preferences,
   offline model and lock state. Never uninstall/wipe the owner's emulator.
5. **Native photo gestures.** Verify edge-to-edge Android gestures, large photos,
   crop handles, ratios, rotation, annotation and cancellation in Persian/English.

## Remaining data and reliability work

- **D6 storage amplification:** every backup still copies all media. Design
  deduplication/incremental storage separately with retention and restore tests.
  Measure DB snapshot time and peak memory again on the 400MB audit fixture;
  compression no longer owns the DB worker, but snapshot creation still does.
- Check concurrent media deletion/edit during backup compression; the SQLite
  snapshot alone does not freeze the media directory.
- Add cross-tool ZIP interoperability coverage for Persian metadata; transfer
  export is not equivalent to the full-library backup. Settings, credentials
  and downloaded models remain outside that library archive.
- Define crash-safe persistent drafts beyond normal sheet disposal; failed
  imports/copies can leave staged orphan media. Avoid deleting a file after an
  uncertain database commit until ownership is known.
- **D22:** bounded cleanup for old exported ZIPs, interrupted exports and staging
  files, without removing a file another app is still reading.
- Device-transfer secure-storage/bootstrap behavior and Persian multiline
  selection remain unverified. Reproduce before implementing speculative fixes.

## Deferred UX/localization work

- Permanently denied camera/microphone permission: show Open Settings, not a
  retry loop; confirm longer permission text fits small screens.
- Pinned filters: verify fully opaque backing with Liquid Glass; expose active
  type/state clearly. Improve tag touch targets and card-edge contrast.
- Dark accent-container/banner treatment remains deferred (initial color change
  was rolled back because it broke onboarding label contrast).
- Persian calendar choice, consistent digits/date formatting and terminology;
  localize starter defaults without renaming the user's existing tags.
- Offline assistant: accurate error reason, Retry, remove duplicate sheet handle;
  add focused reasoning/prompt-echo regression tests and review provider variants.
- Voice detail: duration/waveform presentation and empty Copy action.
- Small-screen header density, assistant-settings spacing, crop ratio overflow
  affordance and asymmetric system gesture insets.
- Screen-reader, large-font, high-contrast and RTL acceptance. Native home widget
  targets changed to 48dp but need a clipping check on actual launchers.
- Windows minimum size/context menus and runtime acceptance remain deferred.
- Photo decode/rotate/annotation error cleanup and memory profiling remain open.
- Preserve the owner's intentional hidden card timestamps and detail-action
  layout; design-document disagreements do not authorize reverting them.

## Feedback — explicitly deferred

D17: Telegram relay code already exists in `apps/feedback-worker`; its 9 mocked
tests passed. It is **not deployed** and no real message was sent. Android release
builds can now take repository variable `NEX_FEEDBACK_API_URL`. Future setup
needs Cloudflare deployment plus Worker secrets `TELEGRAM_BOT_TOKEN` and
`TELEGRAM_CHAT_ID`, then the public Worker URL as the release variable. Review
rate limiting/timeouts before enabling. Never commit or print bot credentials.

## Verification record

- Pinned Flutter: `C:\src\flutter-3.35.5\bin\flutter.bat`; use `--no-pub` with
  the existing resolved dependencies. PATH Flutter is a different version.
- Data suite: **151 passed, 13 skipped**. Data and UI analyzers: no issues.
- Client analyzer: no issues on the final working tree, including the
  recovery-copy preservation edit.
- Client full run: **668 passed, 2 skipped, 3 failed** initially. Failures were
  changelog asset completion, an unmocked OS-auth call, and dark onboarding
  contrast. The latter two were corrected; see the final verification below.
- Capture regressions include 150 simultaneous mocked deliveries, duplicate
  delivery, failure reporting and closing before a delayed first insert.
- Backup regressions include unsafe Windows paths, snapshot consistency and
  corrupt-restore preservation. These do not replace Android acceptance above.
- Local logs: `%TEMP%\nex-audit-final-client.log`,
  `nex-audit-final-data.log`, `nex-audit-final-recheck.log`.
- Final focused rerun of changelog, lock privacy, onboarding and backup screens:
  **23 passed**. The previously failing cases pass after the fixes. The whole
  client suite has not been repeated after that focused rerun.
- The owner subsequently requested committing/pushing all changes as 1.40.0
  on `codex/work`. No new branch, tag or Telegram deployment is authorized.

## Next session

### 1.40.0 release preparation update

- All 671 client tests passed locally (2 skipped); all 157 UI tests passed
  after correcting a duplicate screen-reader announcement for media cards.
- PR #249: the Android build, client suite, pure Dart packages, backend,
  sync/conformance, feedback worker and AI deletion proof passed on GitHub.
  Its initial UI job caught the duplicate announcement; the fix is pushed
  for another CI run. Confirm the latest PR head is green before tagging.
- Native build resolution is therefore no longer a release blocker on CI.
  The device acceptance scenarios above remain unverified and deferred.

Read this file and `git status` first. Finish only the release gates above when
authorized; update this ledger with evidence. Do not call the app release-ready
while the native build/device checks remain outstanding.
