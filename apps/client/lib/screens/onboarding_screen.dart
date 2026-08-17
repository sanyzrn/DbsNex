import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import '../widgets/choice_cards.dart';

/// What someone sees the very first time they open Nex.
///
/// Four pages saying what the app is, then one that asks for the handful of
/// things it genuinely cannot guess. Deliberately not a tour of the interface:
/// every control here is one tap from the timeline, and pointing at buttons
/// someone is about to see anyway is the kind of onboarding people skip.
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

  /// Set by the first attempt to leave the last page without a name, so the
  /// field is not scolding anyone before they have had a chance to type.
  bool _nameTouched = false;

  static const _pageCount = 5;
  bool get _onSetup => _page == _pageCount - 1;
  bool get _hasName => _name.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _name.text = widget.preferences.displayName ?? '';
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _advance() async {
    if (!_onSetup) {
      await _pages.nextPage(
        duration: NexMotion.standard,
        curve: NexMotion.curve,
      );
      return;
    }
    if (!_hasName) {
      setState(() => _nameTouched = true);
      return;
    }
    // The name is the only thing not already written: the three pickers save
    // as they are tapped, the way they do in Settings, so backing out of this
    // screen mid-way could never leave a half-applied choice.
    await widget.preferences.setDisplayName(_name.text);
    await widget.preferences.completeOnboarding();
  }

  Future<void> _back() =>
      _pages.previousPage(duration: NexMotion.standard, curve: NexMotion.curve);

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
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (value) => setState(() => _page = value),
                    children: [
                      _Page(
                        icon: Icons.auto_stories_outlined,
                        title: l10n.onboardingWelcomeTitle,
                        body: l10n.onboardingWelcomeBody,
                      ),
                      _Page(
                        icon: Icons.bolt_outlined,
                        title: l10n.onboardingCaptureTitle,
                        body: l10n.onboardingCaptureBody,
                      ),
                      _Page(
                        icon: Icons.auto_awesome_outlined,
                        title: l10n.onboardingIntelligenceTitle,
                        body: l10n.onboardingIntelligenceBody,
                      ),
                      _Page(
                        icon: Icons.notifications_off_outlined,
                        title: l10n.onboardingSilenceTitle,
                        body: l10n.onboardingSilenceBody,
                      ),
                      _SetupPage(
                        preferences: widget.preferences,
                        name: _name,
                        showNameError: _nameTouched && !_hasName,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NexSpacing.lg,
                    NexSpacing.md,
                    NexSpacing.lg,
                    NexSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      // Holds its width whether or not it is showing, so the
                      // primary button does not shift sideways between pages.
                      SizedBox(
                        width: 88,
                        child: _page == 0
                            ? null
                            : Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton(
                                  onPressed: () => unawaited(_back()),
                                  child: Text(l10n.onboardingBack),
                                ),
                              ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < _pageCount; i++)
                              _Dot(active: i == _page),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FilledButton(
                            onPressed: () => unawaited(_advance()),
                            child: Text(
                              _onSetup
                                  ? l10n.onboardingStart
                                  : l10n.onboardingNext,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// One of the four pages that only say something.
class _Page extends StatelessWidget {
  const _Page({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(NexSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: NexSpacing.xl),
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(icon, size: 40, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: NexSpacing.xl),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The last page: the four things the app cannot guess.
///
/// Each picker writes straight through to preferences, the way it does in
/// Settings, so the theme and language change under the user as they choose —
/// which is the point. Picking Persian and only finding out on the next screen
/// that it took would be a worse way to ask.
class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.preferences,
    required this.name,
    required this.showNameError,
  });

  final NexPreferences preferences;
  final TextEditingController name;
  final bool showNameError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          NexSpacing.lg,
          NexSpacing.lg,
          NexSpacing.lg,
          NexSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.onboardingSetupTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              l10n.onboardingSetupBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            _Field(label: l10n.yourName),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.yourNamePlaceholder,
                errorText: showNameError ? l10n.onboardingNameRequired : null,
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            _Field(label: l10n.theme),
            NexChoiceCards<ThemeMode>(
              haptics: preferences.haptics,
              selected: preferences.themeMode,
              onSelected: preferences.setThemeMode,
              choices: [
                NexChoice(
                  value: ThemeMode.light,
                  label: l10n.themeLight,
                  preview: NexThemeSwatch(
                    mode: ThemeMode.light,
                    comfort: preferences.comfortMode,
                  ),
                ),
                NexChoice(
                  value: ThemeMode.dark,
                  label: l10n.themeDark,
                  preview: NexThemeSwatch(
                    mode: ThemeMode.dark,
                    comfort: preferences.comfortMode,
                  ),
                ),
                NexChoice(
                  value: ThemeMode.system,
                  label: l10n.themeSystem,
                  preview: NexThemeSwatch(
                    mode: ThemeMode.system,
                    comfort: preferences.comfortMode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.lg),
            _Field(label: l10n.language),
            NexChoiceCards<String>(
              haptics: preferences.haptics,
              selected: preferences.locale?.languageCode ?? 'system',
              onSelected: preferences.setLocale,
              choices: [
                NexChoice(
                  value: 'system',
                  label: l10n.languageSystem,
                  preview: const NexScriptSample(
                    icon: Icons.phone_iphone_outlined,
                  ),
                ),
                const NexChoice(
                  value: 'en',
                  label: 'English',
                  preview: NexScriptSample(sample: 'Aa'),
                ),
                const NexChoice(
                  value: 'fa',
                  label: 'فارسی',
                  preview: NexScriptSample(sample: 'اَ'),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.lg),
            _Field(
              label: l10n.aiOutputLanguage,
              hint: l10n.aiOutputLanguageSubtitle,
            ),
            NexChoiceCards<AiOutputLanguage>(
              haptics: preferences.haptics,
              selected: preferences.aiOutputLanguage,
              onSelected: (value) =>
                  unawaited(preferences.setAiOutputLanguage(value)),
              choices: [
                NexChoice(
                  value: AiOutputLanguage.auto,
                  label: l10n.aiOutputLanguageAuto,
                  preview: const NexScriptSample(icon: Icons.auto_awesome),
                ),
                NexChoice(
                  value: AiOutputLanguage.english,
                  label: l10n.aiOutputLanguageEnglish,
                  preview: const NexScriptSample(sample: 'Aa'),
                ),
                NexChoice(
                  value: AiOutputLanguage.persian,
                  label: l10n.aiOutputLanguagePersian,
                  preview: const NexScriptSample(sample: 'اَ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A label over one of the setup page's controls.
class _Field extends StatelessWidget {
  const _Field({required this.label, this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          if (hint != null)
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: NexMotion.standard,
      curve: NexMotion.curve,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? scheme.primary : scheme.outlineVariant,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
