import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'package:nex_ai/cloud.dart';
import '../platform/local_ai_support.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_banner.dart';
import 'ai_provider_screen.dart';
import 'disclosures_screen.dart';
import 'local_model_screen.dart';
import '../widgets/nex_dialog.dart';

/// Each of the six abilities, as its glyph and whether it is working now —
/// on, and something the chosen provider (or the search model) can do. For
/// the glance on the Settings page.
List<(Widget, bool)> nexAbilityGlance(NexPreferences prefs) {
  final provider = prefs.aiProvider.provider;
  final c = prefs.aiCapabilities;
  final on = prefs.aiEnabled;
  final embeds =
      provider.embeds || NexServices.activeSearchModel(prefs) != null;
  return [
    (
      const Icon(Icons.graphic_eq),
      on && c.transcription && provider.hearsAudio,
    ),
    (const Icon(Icons.image_search), on && c.ocr && provider.readsImages),
    (const NexSummariseIcon(), on && c.summarization),
    (const Icon(Icons.label_outline), on && c.tagSuggestions),
    (const Icon(Icons.travel_explore), on && c.semanticSearch && embeds),
    (const Icon(Icons.hub_outlined), on && c.relatedNotes && embeds),
  ];
}

/// Everything the intelligence layer can do, behind one switch.
///
/// It lives on its own screen because it is the one part of Nex that can send a
/// note off the device, and it had been sitting in the middle of the settings
/// sheet between Comfort Mode and the trash — a row of switches that quietly
/// did nothing, because there was no provider behind them and no way to say so.
class IntelligenceScreen extends StatefulWidget {
  const IntelligenceScreen({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<IntelligenceScreen> createState() => _IntelligenceScreenState();
}

class _IntelligenceScreenState extends State<IntelligenceScreen> {
  NexPreferences get _prefs => widget.preferences;

  bool _backfilling = false;

  Future<void> _setEnabled(bool value) async {
    if (!value) {
      await _prefs.setAiEnabled(false);
      widget.services.applyAiPreferences(_prefs);
      if (mounted) setState(() {});
      return;
    }
    // Turning it on is the moment the offline promise stops being absolute, so
    // it is the moment to say so — once, plainly, and not again afterwards.
    final accepted = await _confirm();
    if (accepted != true) return;
    await _prefs.setAiEnabled(true);
    widget.services.applyAiPreferences(_prefs);
    if (mounted) setState(() {});
  }

  Future<bool?> _confirm() {
    final l10n = AppLocalizations.of(context);
    return nexShowDialog<bool>(
      context: context,
      builder: (ctx) => NexAlertDialog(
        title: Text(l10n.intelligenceConsentTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: Text(l10n.intelligenceConsentBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.intelligenceConsentAccept),
          ),
        ],
      ),
    );
  }

  /// Works through the notes captured before the layer could read them.
  ///
  /// This runs on its own when the layer is switched on; the button is here
  /// because one pass is bounded, and because a backlog that stalled on a bad
  /// key should be retryable without toggling the whole thing off and on.
  Future<void> _catchUp() async {
    final l10n = AppLocalizations.of(context);
    final banner = NexBannerHost.of(context);
    setState(() => _backfilling = true);
    final done = await widget.services.backfillEnrichment();
    if (!mounted) return;
    setState(() => _backfilling = false);
    banner?.show(message: l10n.catchUpDone(done));
  }

  Future<void> _setCapabilities(AiCapabilities capabilities) async {
    await _prefs.setAiCapabilities(capabilities);
    widget.services.applyAiPreferences(_prefs);
    if (mounted) setState(() {});
  }

  Future<void> _openProvider() async {
    await Navigator.push(
      context,
      NexPageRoute<void>(builder: (_) => AiProviderScreen(preferences: _prefs)),
    );
    widget.services.applyAiPreferences(_prefs);
    if (mounted) setState(() {});
  }

  Future<void> _openSearchModel() async {
    await Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) => LocalModelScreen(
          preferences: _prefs,
          search: true,
          onSearchModelChanged: () =>
              widget.services.applyAiPreferences(_prefs),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = _prefs.aiEnabled;
    final provider = _prefs.aiProvider.provider;
    final capabilities = _prefs.aiCapabilities;
    // The on-device search model makes these two work whatever the provider
    // is, and with none at all.
    final searchModel = NexServices.activeSearchModel(_prefs) != null;
    final embeds = provider.embeds || searchModel;
    final abilities = <_Ability>[
      _Ability(
        icon: const Icon(Icons.graphic_eq),
        title: l10n.transcription,
        subtitle: l10n.transcriptionSubtitle,
        value: capabilities.transcription,
        supported: provider.hearsAudio,
        set: (v) => capabilities.copyWith(transcription: v),
      ),
      _Ability(
        icon: const Icon(Icons.image_search),
        title: l10n.ocr,
        subtitle: l10n.ocrSubtitle,
        value: capabilities.ocr,
        supported: provider.readsImages,
        set: (v) => capabilities.copyWith(ocr: v),
      ),
      _Ability(
        icon: const NexSummariseIcon(),
        title: l10n.summarization,
        subtitle: l10n.summarizationSubtitle,
        value: capabilities.summarization,
        supported: true,
        set: (v) => capabilities.copyWith(summarization: v),
      ),
      _Ability(
        icon: const Icon(Icons.label_outline),
        title: l10n.tagSuggestions,
        subtitle: l10n.tagSuggestionsSubtitle,
        value: capabilities.tagSuggestions,
        supported: true,
        set: (v) => capabilities.copyWith(tagSuggestions: v),
      ),
      _Ability(
        icon: const Icon(Icons.travel_explore),
        title: l10n.semanticSearch,
        subtitle: l10n.semanticSearchSubtitle,
        value: capabilities.semanticSearch,
        supported: embeds,
        set: (v) => capabilities.copyWith(semanticSearch: v),
      ),
      _Ability(
        icon: const Icon(Icons.hub_outlined),
        title: l10n.relatedNotes,
        subtitle: l10n.relatedNotesSubtitle,
        value: capabilities.relatedNotes,
        supported: embeds,
        set: (v) => capabilities.copyWith(relatedNotes: v),
      ),
    ];
    final working = abilities.where((a) => a.supported && a.value).length;
    final persian = l10n.localeName == 'fa';
    String digits(int n) => nexDigits('$n', persian: persian);
    return Scaffold(
      appBar: NexAppBar(title: Text(l10n.intelligence)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NexSpacing.md,
          NexSpacing.sm,
          NexSpacing.md,
          NexSpacing.xl + nexBottomInset(context),
        ),
        children: [
          // The state of the whole layer at a glance, and the one switch
          // that decides it.
          _Panel(
            glow: enabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: NexSpacing.md,
                    top: NexSpacing.md,
                  ),
                  child: Row(
                    children: [
                      NexIntelligenceOrb(lit: enabled),
                      const SizedBox(width: NexSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              enabled
                                  ? l10n.intelligenceStateOn(provider.label)
                                  : l10n.intelligenceOff,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              enabled
                                  ? l10n.intelligenceAbilitiesOn(
                                      digits(working),
                                      digits(abilities.length),
                                    )
                                  : l10n.intelligenceStateOffShort,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                NexSwitchTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.md,
                    vertical: NexSpacing.xs,
                  ),
                  title: Text(l10n.intelligence),
                  subtitle: Text(l10n.intelligenceMasterSubtitle),
                  value: enabled,
                  onChanged: (value) => unawaited(_setEnabled(value)),
                ),
              ],
            ),
          ),
          if (!enabled) ...[
            const SizedBox(height: NexSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.intelligenceOffBody,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (enabled) ...[
            const SizedBox(height: NexSpacing.md),
            // Who reads, and what has been read: the provider, and the log
            // of every request that left — side by side, because they are
            // the two halves of one question.
            _Panel(
              child: Column(
                children: [
                  _LinkRow(
                    icon: Icons.key_outlined,
                    title: l10n.aiProvider,
                    value: provider.label,
                    onTap: () => unawaited(_openProvider()),
                  ),
                  const Divider(height: 1, indent: 64),
                  _LinkRow(
                    icon: Icons.cloud_upload_outlined,
                    title: l10n.disclosuresTitle,
                    value: l10n.disclosuresRow,
                    onTap: () => Navigator.push(
                      context,
                      NexPageRoute<void>(
                        builder: (_) =>
                            DisclosuresScreen(services: widget.services),
                      ),
                    ),
                  ),
                  // Only in the build that can run a model on the phone.
                  if (LocalAi.flavorSupportsLocalModels) ...[
                    const Divider(height: 1, indent: 64),
                    _LinkRow(
                      key: const ValueKey('search-model-row'),
                      icon: Icons.manage_search,
                      title: l10n.searchModelTitle,
                      value: searchModel
                          ? l10n.searchModelRowOn
                          : l10n.searchModelRowOff,
                      onTap: () => unawaited(_openSearchModel()),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            _Heading(l10n.automatic),
            // What it does, as tiles to switch with one tap: six abilities
            // read faster as a grid than as six rows of switches, and the
            // ones this provider cannot do sit greyed in their place.
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = NexSpacing.sm;
                final width = (constraints.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final ability in abilities)
                      SizedBox(
                        width: width,
                        child: _AbilityTile(
                          ability: ability,
                          onChanged: (value) =>
                              unawaited(_setCapabilities(ability.set(value))),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: NexSpacing.lg),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(NexSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history_toggle_off, color: scheme.primary),
                        const SizedBox(width: NexSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.catchUpTitle,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    Text(
                      l10n.catchUpBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: NexSpacing.md),
                    FilledButton.tonalIcon(
                      onPressed: _backfilling
                          ? null
                          : () => unawaited(_catchUp()),
                      icon: _backfilling
                          ? const NexInlineSpinner()
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(l10n.catchUpAction),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.sm,
                NexSpacing.lg,
                NexSpacing.sm,
                0,
              ),
              child: Text(
                l10n.intelligenceQuietNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      NexSpacing.sm,
      0,
      NexSpacing.sm,
      NexSpacing.sm,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// A group of settings on a rounded card, as every settings page draws them.
/// [glow] edges it in the assistant's own spectrum, for the panel that says
/// the layer is on.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.glow = false});

  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    if (!glow) return card;
    return AnimatedContainer(
      duration: NexMotion.standard,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NexRadius.lg + 1.5),
        gradient: const LinearGradient(colors: nexAssistantSpectrum),
      ),
      child: card,
    );
  }
}

/// The assistant's light as a small orb: lit in its spectrum when the layer
/// is on, a quiet grey ring when it is off.
class NexIntelligenceOrb extends StatelessWidget {
  const NexIntelligenceOrb({super.key, required this.lit});

  final bool lit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: lit
            ? const SweepGradient(colors: nexAssistantSpectrum)
            : null,
        color: lit ? null : scheme.outlineVariant,
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHighest,
        ),
        child: Icon(
          lit ? Icons.auto_awesome : Icons.auto_awesome_outlined,
          size: 22,
          color: lit ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(NexRadius.md),
        ),
        child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      ),
      title: Text(title),
      subtitle: Text(value),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// One thing the layer can do, and how to switch it.
class _Ability {
  const _Ability({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.supported,
    required this.set,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool supported;
  final AiCapabilities Function(bool value) set;
}

/// One ability as a tile: lit in the accent when on, outlined when off, and
/// greyed with the reason when the chosen provider cannot do it.
///
/// Disabled rather than hidden: a switch that vanishes when you change
/// provider leaves you wondering whether you imagined it. Disabled says "this
/// exists, your provider cannot do it".
class _AbilityTile extends StatelessWidget {
  const _AbilityTile({required this.ability, required this.onChanged});

  final _Ability ability;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = ability.supported && ability.value;
    return Semantics(
      toggled: on,
      enabled: ability.supported,
      label: ability.title,
      excludeSemantics: true,
      child: Opacity(
        opacity: ability.supported ? 1 : 0.55,
        child: AnimatedContainer(
          duration: NexMotion.standard,
          curve: NexMotion.curve,
          decoration: BoxDecoration(
            color: on
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(NexRadius.lg),
            border: Border.all(
              color: on ? scheme.primary : scheme.outlineVariant,
              width: on ? 1.5 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(NexRadius.lg),
              onTap: ability.supported
                  ? () {
                      nexTick();
                      onChanged(!ability.value);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(NexSpacing.sm + 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: on
                                ? scheme.primary
                                : scheme.surfaceContainerHigh,
                          ),
                          child: IconTheme(
                            data: IconThemeData(
                              size: 18,
                              color: on
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                            ),
                            child: Center(child: ability.icon),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          on ? Icons.toggle_on : Icons.toggle_off_outlined,
                          size: 30,
                          color: on ? scheme.primary : scheme.outline,
                        ),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    Text(
                      ability.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ability.supported
                          ? ability.subtitle
                          : l10n.notSupportedByProvider,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
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
