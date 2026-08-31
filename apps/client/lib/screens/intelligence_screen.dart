import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_banner.dart';
import 'ai_provider_screen.dart';

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
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final enabled = _prefs.aiEnabled;
    final provider = _prefs.aiProvider.provider;
    final capabilities = _prefs.aiCapabilities;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.intelligence)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: NexSpacing.xl + nexBottomInset(context),
        ),
        children: [
          NexSwitchTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.lg,
              vertical: NexSpacing.sm,
            ),
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: Text(l10n.intelligence),
            subtitle: Text(l10n.intelligenceMasterSubtitle),
            value: enabled,
            onChanged: (value) => unawaited(_setEnabled(value)),
          ),
          if (!enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.lg,
                NexSpacing.md,
                NexSpacing.lg,
                0,
              ),
              child: Text(
                l10n.intelligenceOffBody,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (enabled) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: Text(l10n.aiProvider),
              subtitle: Text(provider.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  NexPageRoute<void>(
                    builder: (_) => AiProviderScreen(preferences: _prefs),
                  ),
                );
                widget.services.applyAiPreferences(_prefs);
                if (mounted) setState(() {});
              },
            ),
            const Divider(),
            _Heading(l10n.automatic),
            _Capability(
              icon: Icons.graphic_eq,
              title: l10n.transcription,
              subtitle: l10n.transcriptionSubtitle,
              value: capabilities.transcription,
              supported: provider.hearsAudio,
              onChanged: (value) => unawaited(
                _setCapabilities(capabilities.copyWith(transcription: value)),
              ),
            ),
            _Capability(
              icon: Icons.image_search,
              title: l10n.ocr,
              subtitle: l10n.ocrSubtitle,
              value: capabilities.ocr,
              supported: provider.readsImages,
              onChanged: (value) => unawaited(
                _setCapabilities(capabilities.copyWith(ocr: value)),
              ),
            ),
            _Capability(
              icon: Icons.summarize_outlined,
              title: l10n.summarization,
              subtitle: l10n.summarizationSubtitle,
              value: capabilities.summarization,
              supported: true,
              onChanged: (value) => unawaited(
                _setCapabilities(capabilities.copyWith(summarization: value)),
              ),
            ),
            _Capability(
              icon: Icons.label_outline,
              title: l10n.tagSuggestions,
              subtitle: l10n.tagSuggestionsSubtitle,
              value: capabilities.tagSuggestions,
              supported: true,
              onChanged: (value) => unawaited(
                _setCapabilities(capabilities.copyWith(tagSuggestions: value)),
              ),
            ),
            _Capability(
              icon: Icons.travel_explore,
              title: l10n.semanticSearch,
              subtitle: l10n.semanticSearchSubtitle,
              value: capabilities.semanticSearch,
              supported: provider.embeds,
              onChanged: (value) => unawaited(
                _setCapabilities(capabilities.copyWith(semanticSearch: value)),
              ),
            ),
            _Capability(
              icon: Icons.hub_outlined,
              title: l10n.relatedNotes,
              subtitle: l10n.relatedNotesSubtitle,
              value: capabilities.relatedNotes,
              supported: provider.embeds,
              onChanged: (value) => unawaited(
                _setCapabilities(capabilities.copyWith(relatedNotes: value)),
              ),
            ),
            const Divider(),
            _Heading(l10n.catchUpTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.lg,
                0,
                NexSpacing.lg,
                NexSpacing.sm,
              ),
              child: Text(l10n.catchUpBody, style: theme.textTheme.bodyMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _backfilling ? null : () => unawaited(_catchUp()),
                  icon: _backfilling
                      ? const NexInlineSpinner()
                      : const Icon(Icons.history_toggle_off),
                  label: Text(l10n.catchUpAction),
                ),
              ),
            ),
            const Divider(height: NexSpacing.xl),
            Padding(
              padding: const EdgeInsets.all(NexSpacing.lg),
              child: Text(
                l10n.intelligenceQuietNote,
                style: theme.textTheme.bodySmall,
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
      NexSpacing.lg,
      NexSpacing.md,
      NexSpacing.lg,
      NexSpacing.xs,
    ),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

/// One capability, greyed out when the chosen provider cannot serve it.
///
/// Disabled rather than hidden: a switch that vanishes when you change provider
/// leaves you wondering whether you imagined it. Disabled says "this exists,
/// your provider cannot do it".
class _Capability extends StatelessWidget {
  const _Capability({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.supported,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool supported;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NexSwitchTile(
      // Matched to the settings sheet's own rows, which carry the same
      // vertical room — these sit in the same kind of list and were the
      // tightest of the lot.
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.lg,
        vertical: NexSpacing.sm,
      ),
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(supported ? subtitle : l10n.notSupportedByProvider),
      value: supported && value,
      onChanged: supported ? onChanged : null,
    );
  }
}
