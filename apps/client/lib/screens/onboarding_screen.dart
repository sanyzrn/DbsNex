import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../widgets/choice_cards.dart';
import '../widgets/nex_brand.dart';
import '../widgets/nex_shelf.dart';
import 'guide_screen.dart';

part 'onboarding/onboarding_art.dart';
part 'onboarding/onboarding_scenes.dart';
part 'onboarding/onboarding_setup.dart';

/// What someone sees the very first time they open Nex.
///
/// Four pages that each *show* one thing the app does — the octopus catching
/// the pieces of a day, notes landing on a timeline with no Save button, a
/// search that reads Persian the way it is typed, a lock closing round all of
/// it — then one page that asks for the handful of things the app cannot
/// guess, with the greeting those answers buy drawn live above them.
///
/// It used to be six pages of a grey circle and a paragraph. The words were
/// right and nothing on screen said them: every page looked like the last, and
/// the only picture was a logo. Each page now leads with a small illustration
/// built from the app's own parts — its cards, its search field, its mark —
/// that plays once when the page arrives and then holds still, so nothing is
/// still moving by the time anyone is reading. With animations turned off the
/// finished picture is shown at once.
///
/// Still not a tour of the interface: every control here is one tap from the
/// timeline, and pointing at buttons someone is about to see anyway is the
/// kind of onboarding people skip.
///
/// It shows exactly once. [NexPreferences.load] marks an install that already
/// has any preference at all as done, so nobody who upgrades into this build
/// is introduced to an app they have been using for months.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  final TextEditingController _name = TextEditingController();

  int _page = 0;

  static const _pageCount = 5;
  bool get _onSetup => _page == _pageCount - 1;
  bool get _hasName => _name.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _name.text = widget.preferences.displayName ?? '';
    _lastText = _name.text;
    _name.addListener(_onChanged);
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.removeListener(_onChanged);
    _name.dispose();
    super.dispose();
  }

  /// The text as the chrome below last saw it.
  ///
  /// A `TextEditingController` notifies when the **selection** moves as well
  /// as when the text does, and dragging a selection handle is a stream of
  /// selection changes. Rebuilding on every notification rebuilt this sheet
  /// underneath the drag, frame after frame, which is what makes selecting
  /// text feel like it is fighting back. Nothing the rebuild is for depends
  /// on where the caret is — the greeting preview reads the text — so the
  /// text is what is watched.
  String _lastText = '';

  void _onChanged() {
    if (_name.text == _lastText) return;
    setState(() => _lastText = _name.text);
  }

  Future<void> _advance() async {
    if (!_onSetup) {
      await _pages.nextPage(duration: NexMotion.slow, curve: NexMotion.curve);
      return;
    }
    await _finish();
  }

  /// Writes whatever has been given and opens the app.
  ///
  /// The name is optional: it buys a greeting, and the header already handles
  /// not having one. An app whose first promise is "capture in seconds"
  /// cannot open with a mandatory text field.
  ///
  /// The name is the only thing not already written: the pickers save as they
  /// are tapped, the way they do in Settings, so backing out of this screen
  /// mid-way could never leave a half-applied choice.
  Future<void> _finish() async {
    if (_hasName) await widget.preferences.setDisplayName(_name.text);
    await widget.preferences.completeOnboarding();
  }

  Future<void> _back() =>
      _pages.previousPage(duration: NexMotion.slow, curve: NexMotion.curve);

  /// Finishes. Skip means skip: someone who taps it is saying "let me in",
  /// and every choice on the last page is in Settings under the same labels.
  Future<void> _skip() => _finish();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                SizedBox(
                  height: nexMinTapTarget,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NexSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        // The same footprint whether or not it is there, so
                        // the progress bar between does not jump when the
                        // first page turns.
                        SizedBox(
                          width: nexMinTapTarget,
                          child: _page > 0
                              ? IconButton(
                                  onPressed: () => unawaited(_back()),
                                  tooltip: l10n.onboardingBack,
                                  icon: const BackButtonIcon(),
                                )
                              : null,
                        ),
                        Expanded(
                          child: _Progress(
                            page: _page,
                            count: _pageCount,
                            label: l10n.onboardingStep(_page + 1, _pageCount),
                          ),
                        ),
                        SizedBox(
                          width: 88,
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: _onSetup
                                ? null
                                : TextButton(
                                    onPressed: () => unawaited(_skip()),
                                    child: Text(l10n.onboardingSkip),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (value) => setState(() => _page = value),
                    children: [
                      _StoryPage(
                        active: _page == 0,
                        art: (play) => _WelcomeArt(play: play),
                        eyebrow: l10n.splashTagline,
                        title: l10n.onboardingWelcomeTitle,
                        body: l10n.onboardingWelcomeBody,
                      ),
                      _StoryPage(
                        active: _page == 1,
                        art: (play) => _CaptureArt(play: play),
                        title: l10n.onboardingCaptureTitle,
                        body: l10n.onboardingCaptureBody,
                        points: [
                          (Icons.notes, l10n.text, NexHue.sky),
                          (Icons.mic_none, l10n.voice, NexHue.violet),
                          (Icons.photo_outlined, l10n.photo, NexHue.rose),
                          (Icons.checklist, l10n.checklist, NexHue.teal),
                          (Icons.link, l10n.link, NexHue.amber),
                          (Icons.attach_file, l10n.file, NexHue.slate),
                        ],
                      ),
                      _StoryPage(
                        active: _page == 2,
                        art: (play) => _FindArt(play: play),
                        title: l10n.onboardingFindTitle,
                        body: l10n.onboardingFindBody,
                      ),
                      _StoryPage(
                        active: _page == 3,
                        art: (play) => _YoursArt(play: play),
                        title: l10n.onboardingYoursTitle,
                        body: l10n.onboardingYoursBody,
                        points: [
                          (
                            Icons.airplanemode_active,
                            l10n.onboardingYoursOffline,
                            NexHue.sky,
                          ),
                          (
                            Icons.fingerprint,
                            l10n.onboardingYoursLock,
                            NexHue.teal,
                          ),
                          (
                            Icons.key_outlined,
                            l10n.onboardingYoursVault,
                            NexHue.amber,
                          ),
                          (
                            Icons.folder_zip_outlined,
                            l10n.onboardingYoursBackup,
                            NexHue.violet,
                          ),
                        ],
                      ),
                      _SetupPage(preferences: widget.preferences, name: _name),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NexSpacing.lg,
                    NexSpacing.sm,
                    NexSpacing.lg,
                    NexSpacing.lg,
                  ),
                  // Full width, and the only button on the row: it is the one
                  // thing to do on every page.
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => unawaited(_advance()),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(NexRadius.lg),
                        ),
                      ),
                      icon: Icon(
                        _onSetup ? Icons.check : Icons.arrow_forward,
                        size: 20,
                      ),
                      iconAlignment: IconAlignment.end,
                      label: Text(
                        _onSetup ? l10n.onboardingStart : l10n.onboardingNext,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Size and weight from the type scale, colour from
                        // the button. `titleSmall` carries the page's ink,
                        // and handing the whole style over put that ink on
                        // the accent: near-white on a pale blue in the dark
                        // theme.
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where you are: one segment per page, the ones behind you filled and the
/// current one filling.
///
/// It was a row of dots, which said "one of seven" and nothing about how far
/// along that was. A bar reads as a distance.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.page,
    required this.count,
    required this.label,
  });

  final int page;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
        child: Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: NexSpacing.xs),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(NexRadius.xs),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Not outlineVariant: on the dark theme it sits a few
                        // percent off the background, and the segments still
                        // ahead disappeared.
                        ColoredBox(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
                        ),
                        AnimatedFractionallySizedBox(
                          duration: NexMotion.slow,
                          curve: NexMotion.curve,
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: i <= page ? 1 : 0,
                          child: ColoredBox(color: scheme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One of the pages that only say something: an illustration, then the
/// words, then — where a page has them — the few things it is naming, as
/// chips in their own colours.
class _StoryPage extends StatelessWidget {
  const _StoryPage({
    required this.active,
    required this.art,
    required this.title,
    required this.body,
    this.eyebrow,
    this.points = const [],
  });

  /// Whether this is the page on screen, which is when its picture plays.
  final bool active;

  /// Built with whether to play, so the picture can start over each time
  /// its page comes back rather than sitting finished from the last visit.
  final Widget Function(bool play) art;

  final String? eyebrow;
  final String title;
  final String body;
  final List<(IconData, String, NexHue)> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A minimum height of the viewport, so a short page centres and a long
    // one — large text, a small phone — scrolls instead of overflowing.
    return LayoutBuilder(
      builder: (context, constraints) {
        final artHeight = (constraints.maxHeight * 0.5).clamp(200.0, 360.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: artHeight,
                  width: double.infinity,
                  child: ExcludeSemantics(child: art(active)),
                ),
                const SizedBox(height: NexSpacing.lg),
                if (eyebrow case final eyebrow?) ...[
                  Text(
                    eyebrow,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: NexSpacing.xs),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: NexSpacing.sm),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.55,
                  ),
                ),
                if (points.isNotEmpty) ...[
                  const SizedBox(height: NexSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: NexSpacing.sm,
                    runSpacing: NexSpacing.sm,
                    children: [
                      for (final (icon, label, hue) in points)
                        _Point(icon: icon, label: label, hue: hue),
                    ],
                  ),
                ],
                const SizedBox(height: NexSpacing.md),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A thing a page names, in its own colour.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.label, required this.hue});

  final IconData icon;
  final String label;
  final NexHue hue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = hue.of(theme.brightness);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(NexRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.md - 4,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
