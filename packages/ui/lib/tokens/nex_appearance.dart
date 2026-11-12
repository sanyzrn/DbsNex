import 'dart:math' as math;
import 'dart:ui';

// For `listEquals`, which `material.dart` does not re-export: its export of
// `foundation.dart` is a `show` list, and that is not on it.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/nex_theme_texture.dart';
import 'nex_tokens.dart';

/// The backdrop the whole app sits on.
///
/// Order is the order they are offered in: the quiet ones first, then the
/// ones that are unmistakably a choice. Names are stored, so an entry can be
/// added anywhere but never renamed — see [NexBackgroundPatternWire].
enum NexBackgroundPattern {
  plain,
  aurora,
  ripple,
  weave,
  dots,
  dusk,
  topography,
  prism,
}

extension NexBackgroundPatternWire on NexBackgroundPattern {
  String get wireName => name;

  static NexBackgroundPattern fromWire(String? value) =>
      NexBackgroundPattern.values.firstWhere(
        (pattern) => pattern.name == value,
        orElse: () => NexBackgroundPattern.plain,
      );
}

/// The four films that turn a blurred backdrop into glass.
///
/// A blur on its own is not a material: it leaves the backdrop's own range
/// intact, so a panel over a dark note is dark and the same panel over a pale
/// one is pale, and no tint that is transparent enough to see through can
/// carry text on both. The fix the previous pass reached for was to stop
/// seeing through it at all — a tint at 86% over a sigma-32 blur, which is a
/// painted panel wearing a blur, not glass.
///
/// Apple's own kit does something better, and the structure here is its
/// structure, read out of the iOS 27 UI kit's `Button - Liquid Glass`
/// (`Refraction 70 · Frost 6 · Opacity 25`). Two flat films squeeze the
/// backdrop's range toward the middle, an additive film lifts the floor, and
/// a luminosity film pins the result's brightness while leaving the
/// backdrop's hue alone. What comes out is translucent — a blue note behind
/// the glass really does tint it blue — and yet lands inside a band narrow
/// enough that one text colour reads on all of it.
///
/// Where this departs from the kit is *where* that band sits, and the reason
/// is in `nex_tokens.dart` beside the numbers: Apple's light band is pinned
/// near white, and a panel on a near-white page that comes out near white is
/// a material nobody can see. The band was moved down until a panel reads as
/// a shape lying on the page. The light anchor is bright enough to feel like
/// frosted glass, while the contrast tests keep text legible over the extremes
/// behind it.
@immutable
class NexGlassWash {
  const NexGlassWash({
    required this.films,
    required this.lift,
    required this.anchor,
  });

  /// Painted straight onto the blurred backdrop, in order, source-over.
  ///
  /// One dark and one light, and the order is the point: each one pulls the
  /// backdrop a fixed fraction of the way to its own colour, so together they
  /// compress the range rather than shifting it.
  final List<Color> films;

  /// A source-over lift that keeps dark backdrops readable.
  final Color lift;

  /// The final source-over tint. All four films are independent of the
  /// destination blend state, including during a sliver's first paint.
  final Color anchor;

  /// Reference source-over composition, also used to bound foreground contrast.
  Color over(Color backdrop) {
    var result = backdrop;
    for (final film in [...films, lift, anchor]) {
      result = Color.alphaBlend(film, result);
    }
    return result;
  }

  /// Film counts are not assumed to match: a theme built with one generation
  /// of the material can be interpolated into the next during a live switch,
  /// and a shorter stack holds its last film rather than throwing on an index
  /// the other side still has.
  NexGlassWash lerp(NexGlassWash other, double t) => NexGlassWash(
    films: [
      for (var i = 0; i < math.max(films.length, other.films.length); i++)
        Color.lerp(
          i < films.length
              ? films[i]
              : (films.isEmpty ? Colors.transparent : films.last),
          i < other.films.length
              ? other.films[i]
              : (other.films.isEmpty ? Colors.transparent : other.films.last),
          t,
        )!,
    ],
    lift: Color.lerp(lift, other.lift, t)!,
    anchor: Color.lerp(anchor, other.anchor, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is NexGlassWash &&
      listEquals(other.films, films) &&
      other.lift == lift &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(Object.hashAll(films), lift, anchor);
}

@immutable
class NexVisualStyle extends ThemeExtension<NexVisualStyle> {
  const NexVisualStyle({
    required this.liquidGlass,
    this.minimal = false,
    required this.baseColor,
    required this.glassWash,
    NexGlassWash? floatingGlassWash,
    required this.glassOpaque,
    required this.glassRim,
    required this.glassBorder,
    required this.glassShadow,
    required this.glassSpecular,
    required this.glassShade,
    required this.glassHighlight,
    required this.glassDepth,
    required this.blurSigma,
    this.glassAura = Colors.transparent,
    this.glassBounce = Colors.transparent,
    this.glassVibrancy = 1,
    this.glassEdgeWidth = 1.2,
    this.glassGrain = 0,
  }) : floatingGlassWash = floatingGlassWash ?? glassWash;

  final bool liquidGlass;

  /// Flat, quiet default surfaces without decorative edges or shadows.
  /// Glass may be opted into independently; focus/high-contrast stay available.
  final bool minimal;
  final Color baseColor;

  /// What the blurred backdrop is turned into — see [NexGlassWash].
  final NexGlassWash glassWash;

  /// More backdrop transmission for menus and floating action bars, with
  /// smaller blur so the shapes beneath remain perceptible.
  final NexGlassWash floatingGlassWash;

  /// The least favourable backdrop for ink, including the optical gradient.
  Color floatingContrastGround(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return Color.alphaBlend(
      (dark ? glassHighlight : glassDepth).withValues(
        alpha: (dark ? glassHighlight : glassDepth).a * 0.6,
      ),
      floatingGlassWash.over(dark ? Colors.white : Colors.black),
    );
  }

  /// What a glass surface falls back to when the backdrop must not show
  /// through: high contrast, and the non-glass appearance's sheets.
  final Color glassOpaque;

  /// The bright sliver down the left and right edges.
  ///
  /// Apple's kit draws it as two zero-blur shadows offset ±1.25 and pulled
  /// back 0.75, which leaves half a pixel showing on each side and nothing at
  /// the top or bottom. That asymmetry is most of what reads as a curved edge
  /// catching the light, and a border drawn evenly all the way round cannot
  /// say it — see the light angle of 0 in the kit's variables.
  final Color glassRim;

  /// The hairline around the whole shape, under the rim.
  final Color glassBorder;

  /// The drop shadow, which is very nearly nothing: Apple's is black at 2%,
  /// 8 down, 15 of blur. A heavy one is what made the old panels read as
  /// cards that had been blurred rather than as glass lying on the page.
  final Color glassShadow;

  /// The lit inner edge along the top of a pane.
  ///
  /// This is what was missing from the first rebuild of the material. The
  /// wash and the rim made a panel that was legible and had a boundary, but
  /// on a plain page — the one backdrop every glass surface in this app is
  /// guaranteed to sit over, because background patterns are a separate
  /// opt-in — there was nothing catching the light, and glass without a
  /// highlight is fog. A thick pane standing on end catches a light above
  /// it along its top curve; this is that highlight, drawn as a short
  /// gradient stroke inside the shape so it never enters the reading area.
  final Color glassSpecular;

  /// The shaded inner edge along the bottom of a pane, giving the same
  /// curve a ground to settle on. With [glassSpecular] these two say
  /// "this is a solid thing the light is moving across" without an
  /// opaque fill anywhere.
  final Color glassShade;

  /// A faint change of light across a pane. The wash makes the backdrop safe
  /// for text; these two colours make the curved surface visible without
  /// flattening the backdrop into an opaque fill.
  final Color glassHighlight;
  final Color glassDepth;

  final double blurSigma;

  /// The ambient light a pane throws on its own page: a second, wider shadow
  /// under the contact shadow. A single tight drop makes a shape float; a
  /// wide, very faint halo is what makes it look like it is *lit*. Transparent
  /// disables it, which is what the still preset wants.
  final Color glassAura;

  /// The reflected line along the bottom edge — page light bouncing back into
  /// the material. It is the cue that separates this from a tinted rectangle:
  /// one lit edge and one bouncing edge cannot belong to a flat fill.
  final Color glassBounce;

  /// How much the backdrop's own colour is allowed to sing through the blur.
  ///
  /// 1.0 leaves it alone. Above 1 it is Apple's vibrancy, implemented as a
  /// colour matrix *inside the same backdrop pass* rather than as a blend
  /// layer reading the destination — the matrix preserves relative luminance,
  /// so the contrast floors the wash was solved against do not move. The
  /// earlier additive/luminosity experiments failed because they read the
  /// layer beneath; a backdrop filter always has a backdrop to read.
  final double glassVibrancy;

  /// The width of the lit bevel ring inside the hairline, in logical pixels.
  /// A 1px line reads as a stroke; a ring this size reads as thickness.
  final double glassEdgeWidth;

  /// Fine frost grain in the edge band, 0 disables it. Kept out of the
  /// reading area on purpose: texture belongs where the material meets the
  /// light, not behind a paragraph.
  final double glassGrain;

  @override
  NexVisualStyle copyWith({
    bool? liquidGlass,
    bool? minimal,
    Color? baseColor,
    NexGlassWash? glassWash,
    NexGlassWash? floatingGlassWash,
    Color? glassOpaque,
    Color? glassRim,
    Color? glassBorder,
    Color? glassShadow,
    Color? glassSpecular,
    Color? glassShade,
    Color? glassHighlight,
    Color? glassDepth,
    double? blurSigma,
    Color? glassAura,
    Color? glassBounce,
    double? glassVibrancy,
    double? glassEdgeWidth,
    double? glassGrain,
  }) => NexVisualStyle(
    liquidGlass: liquidGlass ?? this.liquidGlass,
    minimal: minimal ?? this.minimal,
    baseColor: baseColor ?? this.baseColor,
    glassWash: glassWash ?? this.glassWash,
    floatingGlassWash: floatingGlassWash ?? this.floatingGlassWash,
    glassOpaque: glassOpaque ?? this.glassOpaque,
    glassRim: glassRim ?? this.glassRim,
    glassBorder: glassBorder ?? this.glassBorder,
    glassShadow: glassShadow ?? this.glassShadow,
    glassSpecular: glassSpecular ?? this.glassSpecular,
    glassShade: glassShade ?? this.glassShade,
    glassHighlight: glassHighlight ?? this.glassHighlight,
    glassDepth: glassDepth ?? this.glassDepth,
    blurSigma: blurSigma ?? this.blurSigma,
    glassAura: glassAura ?? this.glassAura,
    glassBounce: glassBounce ?? this.glassBounce,
    glassVibrancy: glassVibrancy ?? this.glassVibrancy,
    glassEdgeWidth: glassEdgeWidth ?? this.glassEdgeWidth,
    glassGrain: glassGrain ?? this.glassGrain,
  );

  @override
  NexVisualStyle lerp(covariant NexVisualStyle? other, double t) {
    if (other == null) return this;
    return NexVisualStyle(
      liquidGlass: t < 0.5 ? liquidGlass : other.liquidGlass,
      minimal: t < 0.5 ? minimal : other.minimal,
      baseColor: Color.lerp(baseColor, other.baseColor, t)!,
      glassWash: glassWash.lerp(other.glassWash, t),
      floatingGlassWash: floatingGlassWash.lerp(other.floatingGlassWash, t),
      glassOpaque: Color.lerp(glassOpaque, other.glassOpaque, t)!,
      glassRim: Color.lerp(glassRim, other.glassRim, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassShadow: Color.lerp(glassShadow, other.glassShadow, t)!,
      glassSpecular: Color.lerp(glassSpecular, other.glassSpecular, t)!,
      glassShade: Color.lerp(glassShade, other.glassShade, t)!,
      glassHighlight: Color.lerp(glassHighlight, other.glassHighlight, t)!,
      glassDepth: Color.lerp(glassDepth, other.glassDepth, t)!,
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t)!,
      glassAura: Color.lerp(glassAura, other.glassAura, t)!,
      glassBounce: Color.lerp(glassBounce, other.glassBounce, t)!,
      glassVibrancy: lerpDouble(glassVibrancy, other.glassVibrancy, t)!,
      glassEdgeWidth: lerpDouble(glassEdgeWidth, other.glassEdgeWidth, t)!,
      glassGrain: lerpDouble(glassGrain, other.glassGrain, t)!,
    );
  }

  /// The wide, faint shadows painted before [glassEdge]. They are kept out of
  /// [glassEdge] on purpose: that list is the public four-edge contract, and a
  /// theme interpolating between generations must not change its length.
  List<BoxShadow> get glassAmbient => [
    BoxShadow(
      color: glassShadow.withValues(alpha: glassShadow.a * 0.6),
      offset: const Offset(0, 3),
      blurRadius: 6,
      spreadRadius: -1,
    ),
    if (glassAura.a > 0)
      BoxShadow(color: glassAura, offset: const Offset(0, 14), blurRadius: 30),
  ];

  /// The four shadows every glass shape carries: the two rim slivers, the
  /// hairline, and the drop.
  ///
  /// All four sit *outside* the shape, which is why they live here and not in
  /// the decoration the blur is clipped to — a border painted inside the clip
  /// would be blurred along with everything behind it.
  List<BoxShadow> get glassEdge => [
    BoxShadow(color: glassBorder, spreadRadius: 0.5),
    BoxShadow(
      color: glassRim,
      offset: const Offset(1.25, 0),
      spreadRadius: -0.75,
    ),
    BoxShadow(
      color: glassRim,
      offset: const Offset(-1.25, 0),
      spreadRadius: -0.75,
    ),
    BoxShadow(color: glassShadow, offset: const Offset(0, 8), blurRadius: 15),
  ];
}

extension NexVisualStyleContext on BuildContext {
  NexVisualStyle get nexVisualStyle {
    final theme = Theme.of(this);
    return theme.extension<NexVisualStyle>() ??
        NexVisualStyle(
          liquidGlass: false,
          baseColor: theme.scaffoldBackgroundColor,
          glassWash: const NexGlassWash(
            films: [Colors.transparent, Colors.transparent],
            lift: Colors.transparent,
            anchor: Colors.transparent,
          ),
          glassOpaque: theme.colorScheme.surfaceContainerLowest,
          glassRim: Colors.transparent,
          glassBorder: theme.colorScheme.outlineVariant,
          glassShadow: Colors.transparent,
          glassSpecular: Colors.transparent,
          glassShade: Colors.transparent,
          glassHighlight: Colors.transparent,
          glassDepth: Colors.transparent,
          blurSigma: 0,
        );
  }
}

class NexAppBackground extends StatelessWidget {
  const NexAppBackground({
    super.key,
    required this.pattern,
    required this.child,
    this.texture = NexThemeTexture.none,
  });

  final NexBackgroundPattern pattern;
  final Widget child;

  /// The theme's own faint motif along the bottom of the screen, if it has
  /// one. Under a plain background only.
  final NexThemeTexture texture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = context.nexVisualStyle.baseColor;
    if (pattern == NexBackgroundPattern.plain) {
      return ColoredBox(
        color: base,
        child: NexTextureBackdrop(texture: texture, child: child),
      );
    }
    return ColoredBox(
      color: base,
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _BackgroundPainter(
                pattern: pattern,
                brightness: theme.brightness,
                accent: theme.colorScheme.primary,
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Panels keep a reading wash; menus and bars reveal more of the page.
enum NexGlassMaterial { panel, floating }

class NexGlassSurface extends StatelessWidget {
  const NexGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(NexRadius.xl)),
    this.padding,
    this.fallbackColor,
    this.showShadow = true,
    this.material = NexGlassMaterial.panel,
    this.blur = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool showShadow;
  final NexGlassMaterial material;

  /// Live backdrop blur is for overlays. In-page cards and nested controls
  /// keep the same optical finish over a stable tint, without sampling the
  /// scrolling page or blurring a second time inside a glass sheet.
  final bool blur;

  /// What to draw outside the glass appearance.
  ///
  /// Null keeps the old behaviour — nothing at all, for a caller that is
  /// already sitting on a surface of its own and only wanted the blur when
  /// there was one. Anything that floats over the page has to pass a colour,
  /// or it is text on whatever line of somebody's note happens to be behind
  /// it for every reader who has glass switched off.
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final visual = context.nexVisualStyle;
    if (!visual.liquidGlass) {
      final ground = fallbackColor;
      final body = Padding(padding: padding ?? EdgeInsets.zero, child: child);
      if (ground == null) return body;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: ground,
          borderRadius: borderRadius,
          border: visual.minimal && !MediaQuery.highContrastOf(context)
              ? null
              : Border.all(
                  color: MediaQuery.highContrastOf(context)
                      ? Theme.of(context).colorScheme.outline
                      : visual.glassBorder,
                ),
        ),
        child: body,
      );
    }
    if (MediaQuery.highContrastOf(context)) {
      final opaqueSurface = Color.alphaBlend(
        visual.glassOpaque,
        visual.baseColor,
      ).withValues(alpha: 1);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: opaqueSurface,
          borderRadius: borderRadius,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      );
    }
    final floating = material == NexGlassMaterial.floating;
    final recipe = _GlassRecipe.of(visual, floating);
    final content = CustomPaint(
      painter: _GlassWashPainter(
        floating ? visual.floatingGlassWash : visual.glassWash,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // The light has a direction: a bright bloom across the top-left,
          // a clear reading band through the middle, and the depth gathering
          // toward the bottom-right corner. The gradient is kept under the
          // content and out of the contrast model, so it shapes the material
          // without changing how much ink a theme can carry.
          gradient: _glassLightGradient(visual, recipe.optical),
        ),
        child: CustomPaint(
          painter: _GlassGrainPainter(
            visual: visual,
            radius: borderRadius,
            amount: recipe.grain,
          ),
          foregroundPainter: _GlassOpticsPainter(
            borderRadius,
            visual,
            floating,
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
    return CustomPaint(
      painter: _GlassEdgePainter(
        shadows: showShadow
            ? [...visual.glassAmbient, ...visual.glassEdge]
            : visual.glassEdge.take(3).toList(),
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: blur
            ? BackdropFilter(
                // One pass per surface: blur and vibrancy are composed into
                // the same backdrop filter rather than layered on top of it.
                filter: _glassFilter(recipe),
                child: content,
              )
            : ColoredBox(color: visual.glassOpaque, child: content),
      ),
    );
  }
}

/// The numbers a material is drawn from at a given elevation.
///
/// A floating surface sits above the page: it reveals a little more of what is
/// behind it and blurs a little less, so the shapes underneath stay readable.
/// A panel is for reading and gets the full blur and the quieter optics.
@immutable
class _GlassRecipe {
  const _GlassRecipe({
    required this.sigma,
    required this.vibrancy,
    required this.optical,
    required this.grain,
  });

  factory _GlassRecipe.of(NexVisualStyle visual, bool floating) => _GlassRecipe(
    sigma: visual.blurSigma * (floating ? 0.72 : 1),
    vibrancy: 1 + (visual.glassVibrancy - 1) * (floating ? 1 : 0.72),
    optical: floating ? 0.62 : 1,
    grain: visual.glassGrain * (floating ? 1.15 : 1),
  );

  final double sigma;
  final double vibrancy;
  final double optical;
  final double grain;
}

/// The gradient under the content: a lit corner, a clean reading band, and
/// depth gathering toward the far corner.
LinearGradient _glassLightGradient(
  NexVisualStyle visual,
  double strength,
) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  stops: const [0, 0.16, 0.44, 0.78, 1],
  colors: [
    visual.glassHighlight.withValues(alpha: visual.glassHighlight.a * strength),
    Colors.transparent,
    Colors.transparent,
    visual.glassDepth.withValues(alpha: visual.glassDepth.a * strength * 0.45),
    visual.glassDepth.withValues(alpha: visual.glassDepth.a * strength),
  ],
);

/// Blur plus vibrancy in a single backdrop pass.
///
/// Saturation is a luminance-preserving matrix, so everything the wash's
/// contrast floors were solved against stays exactly where it was; what
/// changes is that the colour of a note behind the pane arrives at full voice
/// instead of being flattened by the frosted films.
ImageFilter _glassFilter(_GlassRecipe recipe) {
  final sigma = math.max(0.0, recipe.sigma);
  final blur = ImageFilter.blur(sigmaX: sigma * 1.06, sigmaY: sigma);
  if (recipe.vibrancy <= 1.001) return blur;
  return ImageFilter.compose(
    outer: _glassSaturation(recipe.vibrancy),
    inner: blur,
  );
}

final _saturationFilters = <int, ColorFilter>{};

ColorFilter _glassSaturation(double amount) =>
    _saturationFilters.putIfAbsent((amount * 1000).round(), () {
      // Rec. 709 coefficients. Each output row is `s * channel + (1-s) * Y`,
      // which leaves relative luminance untouched by construction — the one
      // property that lets vibrancy be added without re-solving every ink
      // pair in the material.
      const lr = 0.2126, lg = 0.7152, lb = 0.0722;
      final inverse = 1 - amount;
      return ColorFilter.matrix(<double>[
        lr * inverse + amount,
        lg * inverse,
        lb * inverse,
        0,
        0,
        lr * inverse,
        lg * inverse + amount,
        lb * inverse,
        0,
        0,
        lr * inverse,
        lg * inverse,
        lb * inverse + amount,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    });

/// A pane's optics: the hairline, the lit top edge, and the shaded bottom.
///
/// Three strokes, all inside the shape, none reading the destination, so a
/// sliver's first paint is the same as its hundredth:
///
/// * the hairline, a gradient round the whole shape (as before);
/// * the specular, [NexVisualStyle.glassSpecular] fading down from the top
///   curve — a pane catching a light above it, which is the one cue that
///   survives even on a plain page with nothing behind the glass to blur;
/// * the shade, [NexVisualStyle.glassShade] rising from the bottom, so the
///   same curve has a grounded side and the surface reads as volume rather
///   than as a flat sticker with a border.
class _GlassOpticsPainter extends CustomPainter {
  const _GlassOpticsPainter(this.radius, this.visual, this.floating);
  final BorderRadius radius;
  final NexVisualStyle visual;
  final bool floating;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(0.7);
    final shape = radius.toRRect(rect);
    final specular = visual.glassSpecular;
    final bounce = visual.glassBounce;
    final shade = visual.glassShade;

    // 1. The boundary. Five stops rather than one long ramp: the top-left
    // catches the key light, the bottom-right carries the bounced one, and
    // the sides fall back to the hairline. Same stroke, a real light angle.
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            visual.glassRim,
            visual.glassBorder,
            bounce.withValues(alpha: bounce.a * 0.55),
            visual.glassBorder,
            visual.glassRim.withValues(alpha: visual.glassRim.a * 0.55),
          ],
          stops: const [0, 0.30, 0.74, 0.90, 1],
        ).createShader(rect),
    );

    // 2. The bevel. A single pixel reads as a stroke; a ring this wide reads
    // as material with thickness, brighter where the light enters and
    // throwing a bounce where it leaves.
    final bevel = visual.glassEdgeWidth;
    if (bevel > 0) {
      final inner = (Offset.zero & size).deflate(0.7 + bevel / 2);
      canvas.drawRRect(
        radius.toRRect(inner),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bevel
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              specular.withValues(alpha: specular.a * 0.42),
              specular.withValues(alpha: specular.a * 0.05),
              Colors.transparent,
              bounce.withValues(alpha: bounce.a * 0.20),
              shade.withValues(alpha: shade.a * 0.30),
            ],
            stops: const [0, 0.16, 0.46, 0.86, 1],
          ).createShader(inner),
      );
    }

    // 3. The bloom. Light entering the top-left corner does not stop at the
    // stroke; it spills a short way into the pane. Clipped to the shape, and
    // far enough from the reading band to never touch a glyph.
    if (specular.a > 0) {
      final bloomRadius =
          math.min(rect.width, rect.height) * (floating ? 0.38 : 0.34);
      final centre = Offset(
        rect.left + rect.width * 0.08,
        rect.top + rect.height * 0.05,
      );
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawCircle(
        centre,
        bloomRadius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              specular.withValues(alpha: specular.a * (floating ? 0.09 : 0.08)),
              specular.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: bloomRadius)),
      );
      canvas.restore();
    }

    // 4. The lit and shaded inner edges. Both follow a shape inset past the
    // hairline, and each is clipped to its own end of the pane with its
    // gradient landing on zero exactly at the clip, so the halves meet in the
    // middle without a seam. The specular is drawn twice: a soft, blurred
    // under-stroke and the crisp 1px arc above it — the pair is what makes it
    // read as a curved surface rather than as a highlight drawn on a box.
    final inner = (Offset.zero & size).deflate(1.5);
    final innerShape = radius.toRRect(inner);
    final band = size.height * (floating ? 0.9 : 0.62);
    if (specular.a > 0) {
      final clip = Rect.fromLTWH(0, 0, size.width, band);
      final shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [specular, specular.withValues(alpha: 0)],
      ).createShader(clip);
      canvas.save();
      canvas.clipRect(clip);
      canvas.drawRRect(
        innerShape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
          ..shader = shader,
      );
      canvas.drawRRect(
        innerShape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.05
          ..shader = shader,
      );
      canvas.restore();
    }
    if (shade.a > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, band, size.width, size.height - band));
      canvas.drawRRect(
        innerShape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..shader =
              LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [shade, shade.withValues(alpha: 0)],
              ).createShader(
                Rect.fromLTWH(0, band, size.width, size.height - band),
              ),
      );
      canvas.restore();
    }

    // 5. The bounce. Light comes off the page and back into the bottom edge,
    // which is why real glass is brighter along its lower rim than its sides.
    // A thin centre-weighted line with a short glow beneath it, both kept
    // inside the rounded shape.
    if (bounce.a > 0) {
      final bounceShape = radius.toRRect((Offset.zero & size).deflate(1.2));
      final glowHeight = math.min(18.0, size.height * 0.28);
      final glow = Rect.fromLTWH(
        0,
        size.height - glowHeight,
        size.width,
        glowHeight,
      );
      canvas.save();
      canvas.clipRRect(bounceShape);
      canvas.drawRect(
        glow,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              bounce.withValues(alpha: bounce.a * 0.22),
              bounce.withValues(alpha: 0),
            ],
          ).createShader(glow),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - 2.1, size.width, 1.1),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              bounce.withValues(alpha: 0),
              bounce.withValues(alpha: bounce.a * 0.85),
              bounce.withValues(alpha: 0),
            ],
            stops: const [0.03, 0.5, 0.97],
          ).createShader(Offset.zero & size),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GlassOpticsPainter old) =>
      old.radius != radius || old.visual != visual || old.floating != floating;
}

/// Frost grain, confined to the edge band.
///
/// The films are flat, and flat alpha over a gradient bands on an 8-bit
/// screen — a real material always carries a little tooth. The texture is
/// deterministic, blitted as two point clouds in one draw call each, and
/// cached per size so a scrolling page never regenerates it. It stops short
/// of the reading area: a paragraph is not where grain belongs.
class _GlassGrainPainter extends CustomPainter {
  const _GlassGrainPainter({
    required this.visual,
    required this.radius,
    required this.amount,
  });

  final NexVisualStyle visual;
  final BorderRadius radius;
  final double amount;

  static final _cache = <int, Float32List>{};
  static const _step = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final strength = amount.clamp(0.0, 0.12);
    if (strength <= 0 || size.width < 8 || size.height < 8) return;
    final band = math.min(16.0, math.min(size.width, size.height) * 0.24);
    final key = Object.hash(
      (size.width * 2).round(),
      (size.height * 2).round(),
      (band * 4).round(),
    );
    if (_cache.length > 8) _cache.clear();
    final points = _cache.putIfAbsent(key, () => _build(size, band));
    final alpha = (visual.glassSpecular.a * strength * 0.55).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    canvas.save();
    canvas.clipRRect(radius.toRRect(Offset.zero & size));
    canvas.drawRawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = 1
        ..isAntiAlias = false,
    );
    canvas.restore();
  }

  static Float32List _build(Size size, double band) {
    final points = <double>[];
    var seed = 0x9E3779B9;
    double next() {
      seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
      return seed / 0xFFFFFFFF;
    }

    for (var y = 1.5; y < size.height; y += _step) {
      final edgeRow = y < band || y > size.height - band;
      for (var x = 1.5; x < size.width; x += _step) {
        if (!edgeRow && x >= band && x <= size.width - band) continue;
        points
          ..add(x + (next() - 0.5) * _step * 0.8)
          ..add(y + (next() - 0.5) * _step * 0.8);
        next();
      }
    }
    return Float32List.fromList(points);
  }

  @override
  bool shouldRepaint(_GlassGrainPainter old) =>
      old.visual != visual || old.radius != radius || old.amount != amount;
}

/// The blurred band behind a top bar, for a bar the content scrolls under.
///
/// [NexGlassSurface] is the wrong shape for this: it is a rounded panel with a
/// shadow and a border all the way round, which is right for a card floating
/// over a page and wrong for a strip welded to the top edge of one. This is
/// the same material — the same blur and the same four films — squared off,
/// with no rim and a hairline only along the bottom, where the bar actually
/// meets the list. A bar runs off both sides of the screen, so it has no left
/// or right edge for a rim to catch.
///
/// Meant for an `AppBar`'s `flexibleSpace`, and only worth anything if that
/// bar's own `backgroundColor` is transparent and the body extends behind it.
/// A `BackdropFilter` blurs whatever has already been painted beneath it, so a
/// bar that fills itself in first has nothing left to blur but its own fill,
/// and a body that stops at the bar's bottom edge gives it nothing to blur at
/// all — which is how a translucent bar ends up looking like a dimmed pane of
/// glass rather than a frosted one.
///
/// Nothing at all outside the glass appearance: there the bar is opaque, and
/// its own colour is the right one to paint it with.
class NexGlassBar extends StatelessWidget {
  const NexGlassBar({super.key});

  @override
  Widget build(BuildContext context) {
    final visual = context.nexVisualStyle;
    if (!visual.liquidGlass) return const SizedBox.shrink();
    // Reading what is behind a bar is the point of the effect and the enemy of
    // this setting, so it stops being translucent rather than being blurred
    // harder — the same trade [NexGlassSurface] makes.
    if (MediaQuery.highContrastOf(context)) {
      return ColoredBox(
        color: Color.alphaBlend(
          visual.glassOpaque,
          visual.baseColor,
        ).withValues(alpha: 1),
      );
    }
    // An `AppBar` hands its flexible space *loose* constraints under an
    // `Align`, and everything inside this bar sizes to its child — the
    // innermost `DecoratedBox` has none — so without this the whole bar
    // collapsed to zero height and glass mode drew no bar at all. Expanded to
    // whatever the slot offers, the bar is the height of the bar.
    return SizedBox.expand(
      child: ClipRect(
        child: BackdropFilter(
          // Same material as a pane, same single backdrop pass. The bar is
          // read as a panel rather than as a floating control, so it keeps
          // the panel's blur and vibrancy.
          filter: _glassFilter(_GlassRecipe.of(visual, false)),
          child: CustomPaint(
            painter: _GlassWashPainter(visual.glassWash),
            foregroundPainter: _GlassBarEdgePainter(visual),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.55, 1],
                  colors: [
                    visual.glassHighlight,
                    Colors.transparent,
                    visual.glassDepth,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar's one edge that faces the page: the same hairline and lit inner
/// line every pane has, along the bottom only.
///
/// A bar runs off both sides of the screen, so it has no left or right edge
/// for a rim to catch and its top sits under the status bar; the bottom is
/// the only place this material meets the content, and it is where a pane's
/// optics have to show up for the two to read as the same stuff.
class _GlassBarEdgePainter extends CustomPainter {
  const _GlassBarEdgePainter(this.visual);
  final NexVisualStyle visual;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // A shallow shade under the status bar. The bar is translucent, so the
    // clock and battery can otherwise land on whatever bright note happens to
    // be scrolling beneath them.
    final shade = visual.glassShade;
    if (shade.a > 0) {
      final scrim = Rect.fromLTWH(
        0,
        0,
        size.width,
        math.min(28.0, size.height * 0.45),
      );
      canvas.drawRect(
        scrim,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              shade.withValues(alpha: shade.a * 0.5),
              shade.withValues(alpha: 0),
            ],
          ).createShader(scrim),
      );
    }

    // The one edge that faces the page gets the whole optical stack: a
    // hairline, a bounce and a lit meniscus above it. From a little distance
    // that trio reads as the bar's thickness, not as three lines.
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 1, size.width, 1),
      Paint()..color = visual.glassBorder,
    );
    final bounce = visual.glassBounce;
    if (bounce.a > 0) {
      final glow = Rect.fromLTWH(0, size.height - 12, size.width, 12);
      canvas.drawRect(
        glow,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              bounce.withValues(alpha: bounce.a * 0.16),
              bounce.withValues(alpha: 0),
            ],
          ).createShader(glow),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - 2.6, size.width, 1.2),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              bounce.withValues(alpha: 0),
              bounce.withValues(alpha: bounce.a * 0.8),
              bounce.withValues(alpha: 0),
            ],
            stops: const [0.04, 0.5, 0.96],
          ).createShader(Offset.zero & size),
      );
    }
    final specular = visual.glassSpecular;
    if (specular.a > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - 4.4, size.width, 1.0),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              specular.withValues(alpha: 0),
              specular.withValues(alpha: specular.a * 0.5),
              specular.withValues(alpha: 0),
            ],
            stops: const [0.05, 0.5, 0.95],
          ).createShader(Offset.zero & size),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassBarEdgePainter old) => old.visual != visual;
}

/// Draws a glass shape's edge, and only the part of it that falls outside
/// the shape.
///
/// That clip is the whole reason this exists rather than a `boxShadow` on a
/// [BoxDecoration]. Flutter paints a box shadow as a *filled* shape behind
/// the box — under an opaque fill nobody can tell, but glass is not opaque,
/// and four filled shapes showing through it put every pane on a grey plate
/// of its own making. Worse, the blur reads them too, so the backdrop a pane
/// is supposed to show is its own shadow. CSS clips outer shadows to outside
/// the border box; `BoxDecoration` does not, so this does.
class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter({required this.shadows, required this.borderRadius});

  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = borderRadius.toRRect(Offset.zero & size);
    // How far outside the shape a shadow can reach, so the clip's outer
    // rectangle is big enough to hold all of them. Blur is doubled because a
    // Gaussian carries visibly past its radius.
    var reach = 1.0;
    for (final shadow in shadows) {
      reach = math.max(
        reach,
        shadow.offset.distance + shadow.spreadRadius + shadow.blurRadius * 2,
      );
    }
    // Everything except the shape itself, as an even-odd path. `clipRRect`
    // takes no `clipOp` — only `clipRect` does — so subtracting a rounded
    // rectangle has to be said this way.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(reach + 1))
      ..addRRect(shape);
    canvas.save();
    canvas.clipPath(outside);
    for (final shadow in shadows) {
      if (shadow.color.a == 0) continue;
      canvas.drawRRect(
        shape.shift(shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      !listEquals(oldDelegate.shadows, shadows);
}

/// Lays [NexGlassWash]'s four source-over films over the blurred backdrop.
class _GlassWashPainter extends CustomPainter {
  const _GlassWashPainter(this.wash);

  final NexGlassWash wash;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    for (final film in wash.films) {
      canvas.drawRect(area, Paint()..color = film);
    }
    canvas.drawRect(area, Paint()..color = wash.lift);
    canvas.drawRect(area, Paint()..color = wash.anchor);
  }

  @override
  bool shouldRepaint(_GlassWashPainter oldDelegate) => oldDelegate.wash != wash;
}

class NexBackgroundPreview extends StatelessWidget {
  const NexBackgroundPreview({super.key, required this.pattern});

  final NexBackgroundPattern pattern;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(NexRadius.md),
    child: SizedBox(
      width: 46,
      height: 40,
      child: NexAppBackground(
        pattern: pattern,
        child: Center(
          child: Container(
            width: 23,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest
                  .withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter({
    required this.pattern,
    required this.brightness,
    required this.accent,
  });

  final NexBackgroundPattern pattern;
  final Brightness brightness;
  final Color accent;

  bool get _dark => brightness == Brightness.dark;

  @override
  void paint(Canvas canvas, Size size) {
    switch (pattern) {
      case NexBackgroundPattern.plain:
        return;
      case NexBackgroundPattern.aurora:
        _paintAurora(canvas, size);
        return;
      case NexBackgroundPattern.ripple:
        _paintRipple(canvas, size);
        return;
      case NexBackgroundPattern.weave:
        _paintWeave(canvas, size);
        return;
      case NexBackgroundPattern.dots:
        _paintDots(canvas, size);
        return;
      case NexBackgroundPattern.dusk:
        _paintDusk(canvas, size);
        return;
      case NexBackgroundPattern.topography:
        _paintTopography(canvas, size);
        return;
      case NexBackgroundPattern.prism:
        _paintPrism(canvas, size);
        return;
    }
  }

  void _paintAurora(Canvas canvas, Size size) {
    final alpha = _dark ? 0.18 : 0.11;
    final radius = size.longestSide * 0.62;
    final blooms = [
      (Offset(size.width * 0.08, size.height * 0.10), accent),
      (Offset(size.width * 0.92, size.height * 0.42), const Color(0xFF8B5CF6)),
      (Offset(size.width * 0.25, size.height * 0.92), const Color(0xFF14B8A6)),
    ];
    for (final bloom in blooms) {
      canvas.drawCircle(
        bloom.$1,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              bloom.$2.withValues(alpha: alpha),
              bloom.$2.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: bloom.$1, radius: radius)),
      );
    }
  }

  void _paintRipple(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: _dark ? 0.10 : 0.08);
    final center = Offset(size.width * 0.78, size.height * 0.18);
    for (var radius = 36.0; radius < size.longestSide; radius += 44) {
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintWeave(Canvas canvas, Size size) {
    const step = 28.0;
    final paint = Paint()
      ..strokeWidth = 0.75
      ..color = (_dark ? Colors.white : Colors.black).withValues(alpha: 0.045);
    for (var offset = -size.height; offset < size.width; offset += step) {
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset + size.height, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(offset + size.height, 0),
        Offset(offset, size.height),
        paint,
      );
    }
  }

  /// Graph paper, at the density of a notebook rather than a spreadsheet.
  ///
  /// The quietest thing that is still visibly *something*: a grid of dots
  /// carries no direction and no focal point, so nothing on top of it has to
  /// compete with it. 26 apart is far enough that a line of text crosses only
  /// a handful.
  void _paintDots(Canvas canvas, Size size) {
    const step = 26.0;
    final paint = Paint()
      ..color = (_dark ? Colors.white : Colors.black).withValues(alpha: 0.06);
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  /// One wash of accent rising off the bottom edge.
  ///
  /// Aurora with a single bloom and no colours of its own — the timeline
  /// starts at the top and ends here, so the only tinted part of the screen
  /// is the part with the least on it.
  void _paintDusk(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, size.height * 0.45, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            accent.withValues(alpha: _dark ? 0.20 : 0.13),
            accent.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  /// Contour lines, the way a map draws a hill.
  ///
  /// Deliberately not concentric circles — [_paintRipple] already is one, and
  /// what makes a contour read as terrain is that no two rings are the same
  /// shape. Each ring is a circle whose radius is bent by a fixed pair of
  /// sines, so the drawing is elaborate and entirely deterministic: no seed,
  /// no stored state, and the same picture on every repaint.
  void _paintTopography(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withValues(alpha: _dark ? 0.13 : 0.10);
    final center = Offset(size.width * 0.62, size.height * 0.34);
    const steps = 72;
    for (var ring = 0; ring < 11; ring++) {
      final base = 40.0 + ring * 46;
      final path = Path();
      for (var i = 0; i <= steps; i++) {
        final angle = i / steps * 2 * math.pi;
        // Two waves at different frequencies, drifting per ring, so the
        // rings nest without ever running parallel.
        final wobble =
            math.sin(angle * 3 + ring * 0.6) * (10 + ring * 2.2) +
            math.sin(angle * 5 - ring * 0.35) * 6;
        final radius = base + wobble;
        final point = Offset(
          center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius * 0.82,
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  /// Wide diagonal bands of colour, edges dissolved into each other.
  ///
  /// The loudest of the set and the only one that does not take its colour
  /// from the accent: the point of it is the spread between the bands, which
  /// a single hue cannot produce. Still built from gradients that reach zero
  /// at both ends, so it is a tint across the screen rather than stripes on
  /// it — text sits on top of it as readably as on any of the others.
  void _paintPrism(Canvas canvas, Size size) {
    final alpha = _dark ? 0.22 : 0.15;
    final bands = <(Color, double)>[
      (accent, -0.15),
      (const Color(0xFFEC4899), 0.18),
      (const Color(0xFFF59E0B), 0.52),
      (const Color(0xFF10B981), 0.86),
    ];
    // Rotated about the centre so the bands run corner to corner whatever
    // the screen's proportions are.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 5);
    canvas.translate(-size.width / 2, -size.height / 2);
    final span = size.longestSide * 1.6;
    final width = span / 2.6;
    for (final band in bands) {
      final left = -size.width * 0.3 + band.$2 * span;
      final rect = Rect.fromLTWH(left, -span * 0.3, width, span * 1.6);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              band.$1.withValues(alpha: 0),
              band.$1.withValues(alpha: alpha),
              band.$1.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) =>
      pattern != oldDelegate.pattern ||
      brightness != oldDelegate.brightness ||
      accent != oldDelegate.accent;
}
