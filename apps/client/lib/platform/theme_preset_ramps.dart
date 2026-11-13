part of 'theme_presets.dart';

// The fourteen ramps, light and dark, generated from the atelier palettes
// and verified against every floor `theme_ramp_test.dart` holds — every
// ink on every ground, the 3:1 boundary, the 1.06 elevation step, the
// label pairs, and each page's own glass on the worst backdrops. The
// palettes and their verifier live in `tools/theme_atelier/`.
// still: warm bone and quiet sage — the flat, restful one

const _stillLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFFAFAF6),
  card: Color(0xFFF0F1EA),
  elevated: Color(0xFFE4E6DC),
  ink: Color(0xFF252B27),
  muted: Color(0xFF565F58),
  line: Color(0xFFD6DBD0),
  outline: Color(0xFF6F7A70),
  accent: Color(0xFF486553),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF486553),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFDFE8DE),
  containerInk: Color(0xFF233E2D),
  fab: Color(0xFF557A63),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFF70997F),
);

const _stillDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF161A17),
  card: Color(0xFF1F2521),
  elevated: Color(0xFF2A312C),
  ink: Color(0xFFE6E9E2),
  muted: Color(0xFFB8C2B8),
  line: Color(0xFF383F39),
  outline: Color(0xFF9AA89B),
  accent: Color(0xFFB1C9B7),
  onAccent: Color(0xFF1C3427),
  fill: Color(0xFFB1C9B7),
  fillInk: Color(0xFF1C3427),
  container: Color(0xFF344C3C),
  containerInk: Color(0xFFD8E8DA),
  fab: Color(0xFFB1C9B7),
  fabInk: Color(0xFF1C3427),
  accentOnInverse: Color(0xFF486553),
);

// paper: analog journaling — cream stock, sepia ink, brass accents

const _paperLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFFBF7EE),
  card: Color(0xFFF3EDDE),
  elevated: Color(0xFFE9E1CD),
  ink: Color(0xFF2E2416),
  muted: Color(0xFF6B5D48),
  line: Color(0xFFE4DBC6),
  outline: Color(0xFF857457),
  accent: Color(0xFF7A571C),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF7A571C),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFF0E4C8),
  containerInk: Color(0xFF5C4310),
  fab: Color(0xFF8F6524),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFFB8832A),
);

const _paperDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF1A1510),
  card: Color(0xFF241D15),
  elevated: Color(0xFF2F271C),
  ink: Color(0xFFEFE4D0),
  muted: Color(0xFFB3A288),
  line: Color(0xFF3B3125),
  outline: Color(0xFF8D7D63),
  accent: Color(0xFFE3B365),
  onAccent: Color(0xFF241A08),
  fill: Color(0xFFE3B365),
  fillInk: Color(0xFF241A08),
  container: Color(0xFF3B2F1D),
  containerInk: Color(0xFFF0D9AC),
  fab: Color(0xFFE3B365),
  fabInk: Color(0xFF241A08),
  accentOnInverse: Color(0xFF7A571C),
);

// autumn: terracotta and ember on peach cream / umber-plum dusk

const _autumnLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFFCF5EF),
  card: Color(0xFFF5E9E0),
  elevated: Color(0xFFEBD9CC),
  ink: Color(0xFF2F201A),
  muted: Color(0xFF6E564A),
  line: Color(0xFFEBDACC),
  outline: Color(0xFF8A6A58),
  accent: Color(0xFFA04621),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFFA04621),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFF3DCCB),
  containerInk: Color(0xFF7A3414),
  fab: Color(0xFFC25E1E),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFFD86C40),
);

const _autumnDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF1D1512),
  card: Color(0xFF271D18),
  elevated: Color(0xFF33261F),
  ink: Color(0xFFF2E4DA),
  muted: Color(0xFFBBA698),
  line: Color(0xFF403027),
  outline: Color(0xFF9A8272),
  accent: Color(0xFFF0854D),
  onAccent: Color(0xFF1F0F05),
  fill: Color(0xFFF0854D),
  fillInk: Color(0xFF1F0F05),
  container: Color(0xFF43281A),
  containerInk: Color(0xFFF5C9A8),
  fab: Color(0xFFF0854D),
  fabInk: Color(0xFF1F0F05),
  accentOnInverse: Color(0xFFA04621),
);

// blossom: rose atelier — petal white / aubergine and orchid

const _blossomLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFFDF7F9),
  card: Color(0xFFF6EBF0),
  elevated: Color(0xFFECDEE6),
  ink: Color(0xFF2B202B),
  muted: Color(0xFF6C5A6B),
  line: Color(0xFFEFDFE6),
  outline: Color(0xFF86667F),
  accent: Color(0xFFA93A5E),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFFA93A5E),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFF5DCE5),
  containerInk: Color(0xFF8C2E52),
  fab: Color(0xFFC25277),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFFCD6D8C),
);

const _blossomDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF1D151B),
  card: Color(0xFF281E26),
  elevated: Color(0xFF342831),
  ink: Color(0xFFF1E6EC),
  muted: Color(0xFFBDAEC0),
  line: Color(0xFF3F303D),
  outline: Color(0xFF9C85A0),
  accent: Color(0xFFF191B6),
  onAccent: Color(0xFF2A0E1C),
  fill: Color(0xFFF191B6),
  fillInk: Color(0xFF2A0E1C),
  container: Color(0xFF46283A),
  containerInk: Color(0xFFF7C9DA),
  fab: Color(0xFFF191B6),
  fabInk: Color(0xFF2A0E1C),
  accentOnInverse: Color(0xFFA93A5E),
);

// forest: pine and mist / deep woodland with mint-pine light

const _forestLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFF6F9F4),
  card: Color(0xFFEBF0E7),
  elevated: Color(0xFFDFE7DA),
  ink: Color(0xFF202820),
  muted: Color(0xFF556055),
  line: Color(0xFFDFE6D9),
  outline: Color(0xFF75816F),
  accent: Color(0xFF3C6F54),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF3C6F54),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFDCEAD9),
  containerInk: Color(0xFF2C5238),
  fab: Color(0xFF468465),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFF539A75),
);

const _forestDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF121714),
  card: Color(0xFF1A211C),
  elevated: Color(0xFF242C25),
  ink: Color(0xFFE2E8DF),
  muted: Color(0xFFA8B5A7),
  line: Color(0xFF2C352D),
  outline: Color(0xFF8FA292),
  accent: Color(0xFF9CD0AC),
  onAccent: Color(0xFF0D1A10),
  fill: Color(0xFF9CD0AC),
  fillInk: Color(0xFF0D1A10),
  container: Color(0xFF24402C),
  containerInk: Color(0xFFC6E8CE),
  fab: Color(0xFF9CD0AC),
  fabInk: Color(0xFF0D1A10),
  accentOnInverse: Color(0xFF3C6F54),
);

// turquoise: Isfahan tilework — ice white, tile teal / deep tile night

const _turquoiseLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFF4FAFA),
  card: Color(0xFFE7F3F3),
  elevated: Color(0xFFDAEBEB),
  ink: Color(0xFF122A29),
  muted: Color(0xFF4E6968),
  line: Color(0xFFDEEAEC),
  outline: Color(0xFF6A8886),
  accent: Color(0xFF0B6E77),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF0B6E77),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFD2EAEA),
  containerInk: Color(0xFF0A5A62),
  fab: Color(0xFF0E7C86),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFF109DAA),
);

const _turquoiseDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF0B1E21),
  card: Color(0xFF122A2E),
  elevated: Color(0xFF1A373C),
  ink: Color(0xFFDEEFEF),
  muted: Color(0xFF9BB8BA),
  line: Color(0xFF204045),
  outline: Color(0xFF7FA3A6),
  accent: Color(0xFF4FC8D4),
  onAccent: Color(0xFF03181B),
  fill: Color(0xFF4FC8D4),
  fillInk: Color(0xFF03181B),
  container: Color(0xFF123E46),
  containerInk: Color(0xFFB8ECEF),
  fab: Color(0xFF4FC8D4),
  fabInk: Color(0xFF03181B),
  accentOnInverse: Color(0xFF0B6E77),
);

// saffron: golden saffron on warm ivory / tobacco night with marigold

const _saffronLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFFDF8EC),
  card: Color(0xFFF6EFD9),
  elevated: Color(0xFFEDE3C6),
  ink: Color(0xFF2D2512),
  muted: Color(0xFF6C5F41),
  line: Color(0xFFF0E7CD),
  outline: Color(0xFF877648),
  accent: Color(0xFF8F5400),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF8F5400),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFF4E5BC),
  containerInk: Color(0xFF7A4C03),
  fab: Color(0xFFC07200),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFFCC7800),
);

const _saffronDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF191307),
  card: Color(0xFF231B0C),
  elevated: Color(0xFF2E2412),
  ink: Color(0xFFF0E6C8),
  muted: Color(0xFFB7A87E),
  line: Color(0xFF3A2E17),
  outline: Color(0xFF978660),
  accent: Color(0xFFF2B705),
  onAccent: Color(0xFF1F1503),
  fill: Color(0xFFF2B705),
  fillInk: Color(0xFF1F1503),
  container: Color(0xFF3E2E10),
  containerInk: Color(0xFFF5D98F),
  fab: Color(0xFFF2B705),
  fabInk: Color(0xFF1F1503),
  accentOnInverse: Color(0xFF8F5400),
);

// midnight: iris violet on periwinkle white / indigo with a violet glow

const _midnightLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFF7F6FC),
  card: Color(0xFFEEEDF8),
  elevated: Color(0xFFE2E0F1),
  ink: Color(0xFF211E33),
  muted: Color(0xFF585474),
  line: Color(0xFFE5E3F3),
  outline: Color(0xFF767197),
  accent: Color(0xFF634CD7),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF634CD7),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFE4DEF9),
  containerInk: Color(0xFF4B38AE),
  fab: Color(0xFF6750D8),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFF8B7AE1),
);

const _midnightDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF131226),
  card: Color(0xFF1B1A33),
  elevated: Color(0xFF252342),
  ink: Color(0xFFE4E1F2),
  muted: Color(0xFFAFA9CB),
  line: Color(0xFF2C2A4A),
  outline: Color(0xFF8D87B3),
  accent: Color(0xFFA996F5),
  onAccent: Color(0xFF171335),
  fill: Color(0xFFA996F5),
  fillInk: Color(0xFF171335),
  container: Color(0xFF312B5E),
  containerInk: Color(0xFFD4CBF8),
  fab: Color(0xFFA996F5),
  fabInk: Color(0xFF171335),
  accentOnInverse: Color(0xFF634CD7),
);

// ocean: marine blue on sea mist / abyssal blue with sea-glass cyan

const _oceanLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFF5F9FC),
  card: Color(0xFFE9F1F7),
  elevated: Color(0xFFDCE8F0),
  ink: Color(0xFF1B2A36),
  muted: Color(0xFF52677A),
  line: Color(0xFFE0EBF3),
  outline: Color(0xFF6C8597),
  accent: Color(0xFF1565A8),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF1565A8),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFD8E8F4),
  containerInk: Color(0xFF0F4C81),
  fab: Color(0xFF1565A8),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFF3394E6),
);

const _oceanDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF0A1622),
  card: Color(0xFF101F30),
  elevated: Color(0xFF17293D),
  ink: Color(0xFFDDE9F2),
  muted: Color(0xFF98AEC1),
  line: Color(0xFF1E324A),
  outline: Color(0xFF7C97AE),
  accent: Color(0xFF74BFDD),
  onAccent: Color(0xFF07131D),
  fill: Color(0xFF74BFDD),
  fillInk: Color(0xFF07131D),
  container: Color(0xFF14374F),
  containerInk: Color(0xFFBCE0F2),
  fab: Color(0xFF74BFDD),
  fabInk: Color(0xFF07131D),
  accentOnInverse: Color(0xFF1565A8),
);

// graphite: concrete greys and silver ink — colourless by design

const _graphiteLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFF5F5F5),
  card: Color(0xFFECECEC),
  elevated: Color(0xFFE0E0E0),
  ink: Color(0xFF232323),
  muted: Color(0xFF5C5C5C),
  line: Color(0xFFE4E4E4),
  outline: Color(0xFF787878),
  accent: Color(0xFF55585D),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF55585D),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFDEDEDE),
  containerInk: Color(0xFF3A3D42),
  fab: Color(0xFF55585D),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFF878B91),
);

const _graphiteDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF121212),
  card: Color(0xFF1B1B1B),
  elevated: Color(0xFF262626),
  ink: Color(0xFFEDEDED),
  muted: Color(0xFFABABAB),
  line: Color(0xFF2B2B2B),
  outline: Color(0xFF8A8A8A),
  accent: Color(0xFFC6C9CE),
  onAccent: Color(0xFF14161A),
  fill: Color(0xFFC6C9CE),
  fillInk: Color(0xFF14161A),
  container: Color(0xFF2F3237),
  containerInk: Color(0xFFD9DCE1),
  fab: Color(0xFF9EA3AA),
  fabInk: Color(0xFF14161A),
  accentOnInverse: Color(0xFF55585D),
);

// bauhaus: gallery white, ink and vermilion / charcoal, signal red

const _bauhausLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFFAFAF7),
  card: Color(0xFFF0EFEA),
  elevated: Color(0xFFE4E3DC),
  ink: Color(0xFF1E1C19),
  muted: Color(0xFF5B5850),
  line: Color(0xFFE8E6DF),
  outline: Color(0xFF7C7869),
  accent: Color(0xFFB83322),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFFB83322),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFF1DCD5),
  containerInk: Color(0xFF8C2416),
  fab: Color(0xFFC13524),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFFDD5A49),
);

const _bauhausDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF161513),
  card: Color(0xFF201E1B),
  elevated: Color(0xFF2B2926),
  ink: Color(0xFFECE9E3),
  muted: Color(0xFFB0ABA1),
  line: Color(0xFF35322E),
  outline: Color(0xFF948E82),
  accent: Color(0xFFF26248),
  onAccent: Color(0xFF1F0C06),
  fill: Color(0xFFF26248),
  fillInk: Color(0xFF1F0C06),
  container: Color(0xFF402420),
  containerInk: Color(0xFFF5C1B4),
  fab: Color(0xFFF25C41),
  fabInk: Color(0xFF1F0C06),
  accentOnInverse: Color(0xFFB83322),
);

// porcelain: blue-white glaze stitched with kintsugi gold / deep glaze

const _porcelainLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFF9FAFC),
  card: Color(0xFFEFF1F6),
  elevated: Color(0xFFE2E5EE),
  ink: Color(0xFF20242F),
  muted: Color(0xFF565E70),
  line: Color(0xFFE5E8F1),
  outline: Color(0xFF737C92),
  accent: Color(0xFF7C5F1C),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF7C5F1C),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFEFE3C4),
  containerInk: Color(0xFF6B5110),
  fab: Color(0xFF8C6C22),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFFAE8527),
);

const _porcelainDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF101623),
  card: Color(0xFF182130),
  elevated: Color(0xFF212C40),
  ink: Color(0xFFE2E7F0),
  muted: Color(0xFFA3AEC4),
  line: Color(0xFF273349),
  outline: Color(0xFF8794AD),
  accent: Color(0xFFE8C56A),
  onAccent: Color(0xFF1D1603),
  fill: Color(0xFFE8C56A),
  fillInk: Color(0xFF1D1603),
  container: Color(0xFF383322),
  containerInk: Color(0xFFEDD9A0),
  fab: Color(0xFFE8C56A),
  fabInk: Color(0xFF1D1603),
  accentOnInverse: Color(0xFF7C5F1C),
);

// circuit: engineering cyan on a pale board / traces on midnight PCB

const _circuitLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFF5FAFB),
  card: Color(0xFFE8F3F5),
  elevated: Color(0xFFDBEBEE),
  ink: Color(0xFF15242A),
  muted: Color(0xFF4E6A72),
  line: Color(0xFFDFECEF),
  outline: Color(0xFF6A8891),
  accent: Color(0xFF067076),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF067076),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFD3EBEC),
  containerInk: Color(0xFF045E65),
  fab: Color(0xFF007F86),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFF0899A2),
);

const _circuitDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF071417),
  card: Color(0xFF0D2024),
  elevated: Color(0xFF142C31),
  ink: Color(0xFFDCEEF0),
  muted: Color(0xFF93B3B8),
  line: Color(0xFF193338),
  outline: Color(0xFF77989E),
  accent: Color(0xFF29C9C9),
  onAccent: Color(0xFF02161A),
  fill: Color(0xFF29C9C9),
  fillInk: Color(0xFF02161A),
  container: Color(0xFF0F3A3E),
  containerInk: Color(0xFFA8E8E8),
  fab: Color(0xFF29C9C9),
  fabInk: Color(0xFF02161A),
  accentOnInverse: Color(0xFF067076),
);

// afterimage: electric olive on chartreuse mist / void with electric lime

const _afterimageLight = NexSurfaceRamp(
  brightness: Brightness.light,
  page: Color(0xFFF8FAF2),
  card: Color(0xFFEDF1E2),
  elevated: Color(0xFFDFE7D0),
  ink: Color(0xFF212917),
  muted: Color(0xFF59644A),
  line: Color(0xFFE6EBD8),
  outline: Color(0xFF79855F),
  accent: Color(0xFF536D00),
  onAccent: Color(0xFFFFFFFF),
  fill: Color(0xFF536D00),
  fillInk: Color(0xFFFFFFFF),
  container: Color(0xFFE3ECC8),
  containerInk: Color(0xFF465F04),
  fab: Color(0xFF5C7700),
  fabInk: Color(0xFFFFFFFF),
  accentOnInverse: Color(0xFF769B00),
);

const _afterimageDark = NexSurfaceRamp(
  brightness: Brightness.dark,
  page: Color(0xFF101208),
  card: Color(0xFF171D0E),
  elevated: Color(0xFF202814),
  ink: Color(0xFFEBEFDC),
  muted: Color(0xFFADBBA0),
  line: Color(0xFF27311B),
  outline: Color(0xFF8C9C7C),
  accent: Color(0xFFB5E23C),
  onAccent: Color(0xFF101603),
  fill: Color(0xFFB5E23C),
  fillInk: Color(0xFF101603),
  container: Color(0xFF2A3512),
  containerInk: Color(0xFFD8F0A0),
  fab: Color(0xFFB5E23C),
  fabInk: Color(0xFF101603),
  accentOnInverse: Color(0xFF536D00),
);
