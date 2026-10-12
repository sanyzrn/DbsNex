part of '../onboarding_screen.dart';

/// The last page: the things the app cannot guess.
///
/// Each picker writes straight through to preferences, the way it does in
/// Settings, so the theme and language change under the user as they choose —
/// which is the point. Picking Persian and only finding out on the next screen
/// that it took would be a worse way to ask.
///
/// Above them sits what the answers buy: the timeline's own greeting, drawn
/// live. A name field on its own asks for something without saying why; the
/// line over it saying "Good evening, Saeed" as it is typed is the why.
///
/// The AI output language is not asked here (UX-04): intelligence is off
/// until a provider is added, so nothing on first run could make that answer
/// mean anything.
class _SetupPage extends StatelessWidget {
  const _SetupPage({required this.preferences, required this.name});

  final NexPreferences preferences;
  final TextEditingController name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          NexSpacing.lg,
          NexSpacing.md,
          NexSpacing.lg,
          NexSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.onboardingSetupTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
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
            _GreetingPreview(name: name.text),
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              title: l10n.yourName,
              icon: Icons.badge_outlined,
              child: NexAutoDirection(
                controller: name,
                builder: (context, direction) => TextField(
                  controller: name,
                  selectionWidthStyle: BoxWidthStyle.tight,
                  contextMenuBuilder: nexReadingMenu,
                  textCapitalization: TextCapitalization.words,
                  // The one field in the app most likely to be in a different
                  // script from the interface: someone setting Nex to English
                  // still writes their own name in Persian.
                  textDirection: direction,
                  textAlign: TextAlign.start,
                  textInputAction: TextInputAction.done,
                  // No error state: leaving it blank is a valid answer, and
                  // the header simply does not greet anyone by name.
                  decoration: InputDecoration(
                    hintText: l10n.yourNamePlaceholder,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(NexRadius.md),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              title: l10n.theme,
              icon: Icons.contrast,
              child: NexChoiceCards<ThemeMode>(
                selected: preferences.themeMode,
                onSelected: preferences.setThemeMode,
                choices: [
                  for (final (mode, label) in [
                    (ThemeMode.light, l10n.themeLight),
                    (ThemeMode.dark, l10n.themeDark),
                    (ThemeMode.system, l10n.themeSystem),
                  ])
                    NexChoice(
                      value: mode,
                      label: label,
                      preview: NexThemeSwatch(
                        mode: mode,
                        comfort: preferences.comfortMode,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              title: l10n.language,
              icon: Icons.translate,
              child: NexChoiceCards<String>(
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
                    preview: NexScriptSample(sample: 'فا'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            // Four pages cannot cover an app this size, and the honest answer
            // to that is not more pages — it is saying, once and clearly,
            // where the whole of it is written down.
            _GuideRow(onTap: () => unawaited(GuideScreen.show(context))),
          ],
        ),
      ),
    );
  }
}

/// The top of the timeline as it will look: the wordmark, the greeting with
/// the name being typed, and the search field under it — in the theme and
/// language just picked.
class _GreetingPreview extends StatelessWidget {
  const _GreetingPreview({required this.name});

  final String name;

  /// The greeting the timeline opens with, for [name] at [hour].
  ///
  /// The same rule the timeline uses: greeted in the language the name is
  /// written in, whatever the interface is set to, and with no name, the
  /// phrase on its own.
  static String greeting(AppLocalizations interface, String name, int hour) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final short = words.take(2).join(' ');
    final l10n = short.isEmpty
        ? interface
        : nexDirectionOf(short) == TextDirection.rtl
        ? lookupAppLocalizations(const Locale('fa'))
        : lookupAppLocalizations(const Locale('en'));
    final phrase = switch (hour) {
      >= 5 && < 12 => l10n.greetingMorning,
      >= 12 && < 17 => l10n.greetingAfternoon,
      >= 17 && < 23 => l10n.greetingEvening,
      _ => l10n.greetingNight,
    };
    return short.isEmpty
        ? phrase('').replaceFirst(RegExp(r'[,،]\s*$'), '').trim()
        : phrase(short);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = greeting(l10n, name, DateTime.now().hour);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm + 4,
        NexSpacing.md,
        NexSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(NexRadius.xl),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const NexLogotype(height: 12, semanticLabel: null),
              const Spacer(),
              Text(
                l10n.onboardingSetupPreview,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          AnimatedSwitcher(
            duration: NexMotion.standard,
            child: Text(
              text,
              key: ValueKey(text),
              textAlign: TextAlign.center,
              textDirection: nexDirectionOf(text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(NexRadius.pill),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: NexSpacing.sm),
                const Expanded(child: _Bar(0.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amber = NexHue.amber.of(theme.brightness);
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(NexRadius.md),
                ),
                child: Icon(Icons.menu_book_outlined, color: amber),
              ),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.onboardingGuideTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.onboardingGuideBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NexSpacing.sm),
              Text(
                l10n.onboardingGuideOpen,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
