import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../widgets/feature_label.dart';
import 'minimal_theme.dart';

part 'theme_preset_ramps.dart';
part 'theme_preset_ramps_bold.dart';

/// The whole-app palettes — the Theme Atelier.
///
/// A preset used to be a seed colour and a page tint, with every other tone
/// derived by Material's tonal machinery. That is also why the gallery was
/// switched off with the Soft UI work: a red picked on Paper came out brown,
/// Graphite quietly ignored a picked colour, and the derived surfaces sat
/// beside the shipped Soft UI surfaces like pieces of another app.
///
/// This is the rebuild. Each palette is now a designed [NexSurfaceRamp] —
/// its own page, card and elevated step; its own ink, muted tone and two
/// boundary weights; its own accent steps (a deep one that holds 4.5:1 as
/// text, and a vibrant one the capture button wears at the 3:1 graphical
/// floor, the same split the shipped Soft Light theme makes between
/// `#006DCC` and `#0084F7`); its own selected-container wash; and, when
/// Liquid Glass is on, its own glass, tinted by its own page the way the
/// shipped appearances tint theirs. `theme_ramp_test.dart` holds every
/// palette to every floor the shipped surfaces are held to.
///
/// Each palette keeps the identity it always had — Still is still the flat,
/// glass-free one, Graphite is still grey by design — and a colour somebody
/// picks keeps its own hue on every palette, taking the accent roles only:
/// see [NexSurfaceRamp.withAccent].
typedef NexThemePreset = ({
  String id,
  String en,
  String fa,
  String enDescription,
  String faDescription,
  Color seed,
  IconData icon,
  // The palette's designed ramp, light and dark. Null keeps the classic
  // surfaces — Nex itself, which the base appearance already is.
  NexSurfaceRamp? light,
  NexSurfaceRamp? dark,
});

/// The faint motif a theme draws up from the bottom of the screen. Every
/// palette but Nex and Still has one; those two stay plain on purpose.
NexThemeTexture nexThemeTexture(String presetId) => switch (presetId) {
  'paper' => NexThemeTexture.fibre,
  'autumn' => NexThemeTexture.leaves,
  'blossom' => NexThemeTexture.petals,
  'saffron' => NexThemeTexture.threads,
  'graphite' => NexThemeTexture.grid,
  'turquoise' => NexThemeTexture.girih,
  'forest' => NexThemeTexture.contours,
  'ocean' => NexThemeTexture.waves,
  'midnight' => NexThemeTexture.stars,
  'bauhaus' => NexThemeTexture.bauhaus,
  'porcelain' => NexThemeTexture.seams,
  'circuit' => NexThemeTexture.circuit,
  'afterimage' => NexThemeTexture.halftone,
  'bloom' => NexThemeTexture.petals,
  'dusk' => NexThemeTexture.stars,
  'sunflower' => NexThemeTexture.halftone,
  'lavender' => NexThemeTexture.petals,
  'peach' => NexThemeTexture.fibre,
  'coral' => NexThemeTexture.waves,
  _ => NexThemeTexture.none,
};

const nexThemePresets = <NexThemePreset>[
  (
    id: 'classic',
    en: 'Nex',
    fa: 'نکس',
    enDescription: 'Clean and familiar',
    faDescription: 'ساده و آشنا',
    seed: Color(0xFF287EC0),
    icon: Icons.auto_awesome,
    light: null,
    dark: null,
  ),
  (
    id: 'still',
    en: 'Still',
    fa: 'سکون',
    enDescription: 'Warm neutrals, soft sage, no decorative edges',
    faDescription: 'خنثیِ گرم و سبز ملایم، بدون حاشیه و سایه',
    seed: Color(0xFF486553),
    icon: Icons.spa_outlined,
    light: _stillLight,
    dark: _stillDark,
  ),
  (
    id: 'paper',
    en: 'Paper notebook',
    fa: 'دفتر کاغذی',
    enDescription: 'Cream stock, sepia ink and quiet surfaces',
    faDescription: 'کرم گرم، جوهر و سطح‌های آرام',
    seed: Color(0xFF7A571C),
    icon: Icons.menu_book_outlined,
    light: _paperLight,
    dark: _paperDark,
  ),
  (
    id: 'autumn',
    en: 'Autumn',
    fa: 'پاییز',
    enDescription: 'Terracotta, amber and warm dusk',
    faDescription: 'سفالی، کهربایی و غروب گرم',
    seed: Color(0xFFA04621),
    icon: Icons.eco_outlined,
    light: _autumnLight,
    dark: _autumnDark,
  ),
  (
    id: 'blossom',
    en: 'Rose atelier',
    fa: 'شکوفهٔ رز',
    enDescription: 'Soft rose and lilac with a feminine touch',
    faDescription: 'رز لطیف و یاسی با حال‌وهوای دخترانه',
    seed: Color(0xFFA93A5E),
    icon: Icons.local_florist_outlined,
    light: _blossomLight,
    dark: _blossomDark,
  ),
  (
    id: 'forest',
    en: 'Forest retreat',
    fa: 'خلوت جنگل',
    enDescription: 'Sage green and deep woodland',
    faDescription: 'سبز مریم‌گلی و عمق جنگل',
    seed: Color(0xFF3C6F54),
    icon: Icons.forest_outlined,
    light: _forestLight,
    dark: _forestDark,
  ),
  (
    id: 'turquoise',
    en: 'Isfahan turquoise',
    fa: 'فیروزهٔ اصفهان',
    enDescription: 'Tilework turquoise with a touch of lapis',
    faDescription: 'فیروزه‌ای کاشی با ته‌رنگ لاجورد',
    seed: Color(0xFF0B6E77),
    icon: Icons.mosque_outlined,
    light: _turquoiseLight,
    dark: _turquoiseDark,
  ),
  (
    id: 'saffron',
    en: 'Saffron',
    fa: 'زعفران',
    enDescription: 'Golden saffron on warm ivory',
    faDescription: 'زعفرانی طلایی روی عاج گرم',
    seed: Color(0xFF8F5400),
    icon: Icons.spa_outlined,
    light: _saffronLight,
    dark: _saffronDark,
  ),
  (
    id: 'midnight',
    en: 'Midnight',
    fa: 'نیمه‌شب',
    enDescription: 'Deep indigo with a violet glow',
    faDescription: 'نیلی عمیق با درخششی بنفش',
    seed: Color(0xFF634CD7),
    icon: Icons.nights_stay_outlined,
    light: _midnightLight,
    dark: _midnightDark,
  ),
  (
    id: 'ocean',
    en: 'Deep sea',
    fa: 'اعماق دریا',
    enDescription: 'Cool blues and sea glass',
    faDescription: 'آبی‌های خنک و شیشهٔ دریایی',
    seed: Color(0xFF1565A8),
    icon: Icons.waves,
    light: _oceanLight,
    dark: _oceanDark,
  ),
  (
    id: 'graphite',
    en: 'Graphite',
    fa: 'گرافیت',
    enDescription: 'Pure greys and nothing else',
    faDescription: 'خاکستری خالص، بی هیچ رنگ دیگری',
    seed: Color(0xFF55585D),
    icon: Icons.contrast,
    light: _graphiteLight,
    dark: _graphiteDark,
  ),
  (
    id: 'bauhaus',
    en: 'Bauhaus',
    fa: 'باوهاوس',
    enDescription: 'Ink, vermilion and bold geometry',
    faDescription: 'جوهر، سرخ شنگرف و هندسهٔ جسور',
    seed: Color(0xFFB83322),
    icon: Icons.category_outlined,
    light: _bauhausLight,
    dark: _bauhausDark,
  ),
  (
    id: 'porcelain',
    en: 'Kintsugi',
    fa: 'کینتسوگی',
    enDescription: 'Cool porcelain stitched with gold',
    faDescription: 'چینی خنک با رگه‌های طلایی',
    seed: Color(0xFF7C5F1C),
    icon: Icons.diamond_outlined,
    light: _porcelainLight,
    dark: _porcelainDark,
  ),
  (
    id: 'circuit',
    en: 'Circuit',
    fa: 'مدار الکترونیک',
    enDescription: 'Precise cyan routes on a midnight board',
    faDescription: 'مسیرهای فیروزه‌ای روی برد نیمه‌شب',
    seed: Color(0xFF067076),
    icon: Icons.memory_outlined,
    light: _circuitLight,
    dark: _circuitDark,
  ),
  (
    id: 'afterimage',
    en: 'Afterimage',
    fa: 'پس‌تصویر',
    enDescription: 'Electric lime and an optical rhythm',
    faDescription: 'لیمویی الکتریکی و ریتم خطای دید',
    seed: Color(0xFF536D00),
    icon: Icons.blur_circular_outlined,
    light: _afterimageLight,
    dark: _afterimageDark,
  ),
  (
    id: 'lavender',
    en: 'Lavender',
    fa: 'اسطوخودوس',
    enDescription: 'Lilac pastels with a bright violet',
    faDescription: 'یاسی‌های پاستلی با بنفشی روشن',
    seed: Color(0xFF6E34C2),
    icon: Icons.bubble_chart_outlined,
    light: _lavenderLight,
    dark: _lavenderDark,
  ),
  (
    id: 'peach',
    en: 'Peach & charcoal',
    fa: 'هلو و زغال',
    enDescription: 'Soft peach with confident charcoal',
    faDescription: 'هلوییِ نرم کنار زغالیِ محکم',
    seed: Color(0xFFA4400F),
    icon: Icons.wb_twilight,
    light: _peachLight,
    dark: _peachDark,
  ),
  (
    id: 'bloom',
    en: 'Bloom',
    fa: 'شکوفا',
    enDescription: 'Maroon and mustard, warm and bold',
    faDescription: 'زرشکی و خردلی، گرم و جسور',
    seed: Color(0xFF7A1E16),
    icon: Icons.filter_vintage_outlined,
    light: _bloomLight,
    dark: _bloomDark,
  ),
  (
    id: 'dusk',
    en: 'Dusk',
    fa: 'شامگاه',
    enDescription: 'Plum violet with a peach glow',
    faDescription: 'بنفش آلویی با درخشش هلویی',
    seed: Color(0xFF52438F),
    icon: Icons.nightlight_outlined,
    light: _duskLight,
    dark: _duskDark,
  ),
  (
    id: 'coral',
    en: 'Coral',
    fa: 'مرجان',
    enDescription: 'Coral red on cool mist and charcoal',
    faDescription: 'مرجانی روی مه خنک و زغالی',
    seed: Color(0xFFB1323A),
    icon: Icons.water_drop_outlined,
    light: _coralLight,
    dark: _coralDark,
  ),
  (
    id: 'sunflower',
    en: 'Sunflower',
    fa: 'آفتابگردان',
    enDescription: 'Sunny yellow and deep black',
    faDescription: 'زرد آفتابی و مشکی عمیق',
    seed: Color(0xFF6B4F00),
    icon: Icons.wb_sunny_outlined,
    light: _sunflowerLight,
    dark: _sunflowerDark,
  ),
];

/// The seed a palette brings with it — its deep, text-safe accent step — or
/// null for the classic look and for anything unknown, which keeps the
/// shipped accent rather than inventing one.
Color? nexThemePresetSeed(String id) {
  for (final p in nexThemePresets) {
    if (p.id == id) return p.light?.accent;
  }
  return null;
}

String nexThemePresetLabel(BuildContext context, String id) {
  final p = nexThemePresets.firstWhere(
    (p) => p.id == id,
    orElse: () => nexThemePresets.first,
  );
  return nexLabel(context, p.en, p.fa);
}

/// The palette's one-line description, in the interface's language.
String nexThemePresetDescription(BuildContext context, String id) {
  final p = nexThemePresets.firstWhere(
    (p) => p.id == id,
    orElse: () => nexThemePresets.first,
  );
  return nexLabel(context, p.enDescription, p.faDescription);
}

ThemeData nexApplyThemePreset(ThemeData base, String id, Color? accent) {
  if (id == 'classic') return base;
  final p = nexThemePresets.firstWhere(
    (p) => p.id == id,
    orElse: () => nexThemePresets.first,
  );
  final ramp = base.brightness == Brightness.light ? p.light : p.dark;
  // Classic has no ramp, and an unknown id must never invent a look.
  if (ramp == null) return base;
  // An accent somebody picked, as opposed to the palette's own. The palette
  // keeps its neutrals — they are its identity — and the accent roles follow
  // the pick at their own contrast floors: see [NexSurfaceRamp.withAccent].
  final picked = accent != null && accent.toARGB32() != p.seed.toARGB32();
  final themed = nexSoftThemeFromRamp(
    ramp: picked ? ramp.withAccent(accent) : ramp,
    // The palette rides the material the base already chose: glass on only
    // when it was switched on, and the scaffold see-through only while
    // something is behind it. Still is the one palette whose identity is
    // that nothing decorative is drawn, glass included.
    liquidGlass: id == 'still'
        ? false
        : (base.extension<NexVisualStyle>()?.liquidGlass ?? false),
    transparentScaffold: base.scaffoldBackgroundColor.a == 0,
    fontFamily: base.textTheme.bodyLarge?.fontFamily ?? nexLatinFont,
  );
  // Still keeps its own discipline on top of the ramp: borderless inputs,
  // no glass optics, no elevation anywhere.
  return id == 'still' ? nexStillTheme(themed) : themed;
}
