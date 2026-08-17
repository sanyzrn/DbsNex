import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../widgets/nex_banner.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';

/// Where the intelligence features get their answers from.
///
/// Until this existed the Intelligence switches in Settings turned on
/// capabilities that had nothing behind them: the only adapters were a no-op
/// and a local heuristic, so "Summarization: on" changed nothing a user could
/// see. A provider makes those switches mean something.
class AiProviderScreen extends StatefulWidget {
  const AiProviderScreen({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<AiProviderScreen> createState() => _AiProviderScreenState();
}

class _AiProviderScreenState extends State<AiProviderScreen> {
  late AiProviderConfig _config = widget.preferences.aiProvider;

  /// The provider actually in effect — unlike [_stored], this does not move
  /// just from looking at a different one, only from a save that adopts it.
  late AiProvider _activeProvider = _config.provider;

  /// What is stored for the provider currently on screen, whether or not it
  /// is [_activeProvider]. Each provider keeps its own key/URL/model now
  /// (see `NexPreferences.configFor`), so this is what the fields were last
  /// saved as for *this* provider — not whatever the previous provider being
  /// viewed happened to have typed into them.
  late AiProviderConfig _stored = _config;

  late final TextEditingController _key = TextEditingController(
    text: _config.apiKey,
  );
  late final TextEditingController _baseUrl = TextEditingController(
    text: _config.baseUrl,
  );
  late final TextEditingController _model = TextEditingController(
    text: _config.model,
  );

  bool _obscure = true;
  bool _testing = false;
  AiTestResult? _result;

  @override
  void dispose() {
    _key.dispose();
    _baseUrl.dispose();
    _model.dispose();
    super.dispose();
  }

  AiProviderConfig get _current => _config.copyWith(
    apiKey: _key.text,
    // A hidden field must not still be speaking. Typing an endpoint for
    // Custom and then switching to Gemini used to leave that endpoint in
    // effect against a provider that has only one host.
    baseUrl: _config.provider.needsBaseUrl ? _baseUrl.text : '',
    model: _model.text,
  );

  /// Whether anything on screen differs from what is stored.
  ///
  /// Saving used to be available at every moment, including the moment right
  /// after a save, which makes the button meaningless: there is no way to tell
  /// from it whether the thing on screen is the thing that is in effect.
  /// `AiProviderConfig` carries no equality, so the fields are compared here.
  ///
  /// Two things can make this true: the provider on screen is not the active
  /// one (so Save is how you switch to it), or its fields no longer match
  /// what was last saved for it (so Save is how you update it).
  bool get _dirty =>
      _activeProvider != _current.provider ||
      _stored.apiKey != _current.apiKey ||
      _stored.baseUrl != _current.baseUrl ||
      _stored.model != _current.model;

  Future<void> _save() async {
    final saving = _current;
    await widget.preferences.setAiProvider(saving);
    if (!mounted) return;
    setState(() {
      _config = saving;
      _stored = saving;
      _activeProvider = saving.provider;
    });
    // It said nothing at all before — no confirmation, no error, no change in
    // the button. There was no way to know whether the key had been kept.
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).aiProviderSaved,
    );
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final adapter = CloudAIAdapter(config: _current);
    try {
      final result = await adapter.test();
      if (!mounted) return;
      setState(() => _result = result);
      // Only a working configuration is worth keeping.
      if (result.success) await _save();
    } finally {
      adapter.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = _config.provider;
    final needsEndpoint = provider.needsBaseUrl;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiProvider)),
      // Test and Save live in a bar of their own. Six provider rows plus three
      // fields is more than one screenful, so inline actions sat below the fold
      // — the two buttons the screen exists for were the two you had to go
      // looking for.
      bottomNavigationBar: _ActionBar(
        testing: _testing,
        canSave: _dirty && !_testing,
        showTest: provider != AiProvider.none,
        onTest: () => unawaited(_test()),
        onSave: () => unawaited(_save()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          NexSpacing.lg,
          NexSpacing.md,
          NexSpacing.lg,
          NexSpacing.lg,
        ),
        children: [
          Text(l10n.aiProviderIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: NexSpacing.lg),
          // A list, not a dropdown. Six providers behind a popup menu meant the
          // one thing this screen is for was hidden behind a tap, and the menu
          // itself was the last Material default left in the app — a different
          // shape, a different shadow and a different motion from everything
          // around it.
          for (final candidate in AiProvider.values) ...[
            _ProviderTile(
              provider: candidate,
              selected: candidate == provider,
              subtitle: candidate == AiProvider.none
                  ? l10n.aiProviderNoneSubtitle
                  : candidate.defaultModel,
              onTap: () {
                if (candidate == provider) return;
                // Whatever was saved for this provider before, not whatever
                // is still sitting in the fields from the one just left —
                // switching to OpenAI used to keep showing Claude's key,
                // simply because nothing here ever looked at OpenAI's own
                // storage slot.
                final stored = widget.preferences.configFor(candidate);
                _key.text = stored.apiKey;
                _baseUrl.text = stored.baseUrl;
                _model.text = stored.model;
                setState(() {
                  _config = stored;
                  _stored = stored;
                  _result = null;
                });
              },
            ),
            const SizedBox(height: NexSpacing.sm),
          ],
          if (provider != AiProvider.none) ...[
            const SizedBox(height: NexSpacing.sm),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.apiKey,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: l10n.apiKey,
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => setState(() => _result = null),
            ),
            // Only Custom needs one. For the rest the host is fixed and the
            // field could only ever be filled in wrongly.
            if (needsEndpoint) ...[
              const SizedBox(height: NexSpacing.md),
              TextField(
                controller: _baseUrl,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: l10n.baseUrl,
                  hintText: 'https://…',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _result = null),
              ),
            ],
            const SizedBox(height: NexSpacing.md),
            TextField(
              controller: _model,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.model,
                hintText: needsEndpoint ? null : provider.defaultModel,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _result = null),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: NexSpacing.lg),
            _ResultBanner(result: _result!),
          ],
          if (provider != AiProvider.none) ...[
            const SizedBox(height: NexSpacing.lg),
            const Divider(),
            const SizedBox(height: NexSpacing.sm),
            Text(l10n.aiKeyStorage, style: theme.textTheme.bodySmall),
            const SizedBox(height: NexSpacing.sm),
            Text(l10n.aiCapabilityNote, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// The two actions, always reachable, whatever the list is doing above them.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.testing,
    required this.canSave,
    required this.showTest,
    required this.onTest,
    required this.onSave,
  });

  final bool testing;
  final bool canSave;
  final bool showTest;
  final VoidCallback onTest;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
        NexSpacing.lg,
        NexSpacing.md,
        NexSpacing.lg,
        NexSpacing.md + nexBottomInset(context),
      ),
      child: Row(
        children: [
          if (showTest) ...[
            Expanded(
              child: FilledButton.icon(
                onPressed: testing ? null : onTest,
                icon: testing
                    ? const NexInlineSpinner()
                    : const Icon(Icons.wifi_tethering),
                label: Text(l10n.testConnection),
              ),
            ),
            const SizedBox(width: NexSpacing.md),
          ],
          // Save is always here, including for "no provider": that is a choice
          // like any other, and it used to be unstorable because the only
          // button that could store it was hidden along with the key fields.
          OutlinedButton(
            onPressed: canSave ? onSave : null,
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

/// One provider, shown as a row you can see without opening anything.
class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.selected,
    required this.subtitle,
    required this.onTap,
  });

  final AiProvider provider;
  final bool selected;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: provider.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NexRadius.md),
        child: AnimatedContainer(
          duration: NexMotion.standard,
          curve: NexMotion.curve,
          constraints: const BoxConstraints(minHeight: nexMinTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NexRadius.md),
            color: selected
                ? accent.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              Icon(
                provider == AiProvider.none
                    ? Icons.phone_android_outlined
                    : Icons.cloud_outlined,
                size: 20,
                color: selected ? accent : theme.colorScheme.secondary,
              ),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      provider.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: selected ? accent : theme.colorScheme.onSurface,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              // A check that occupies its slot either way, so the rows do not
              // shift sideways as the selection moves down the list.
              Opacity(
                opacity: selected ? 1 : 0,
                child: Icon(Icons.check_circle, size: 20, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final AiTestResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = result.success
        ? theme.colorScheme.secondary
        : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.success ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              result.success ? l10n.connectionOk(result.detail) : result.detail,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
