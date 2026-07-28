import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
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
  late final TextEditingController _key =
      TextEditingController(text: _config.apiKey);
  late final TextEditingController _baseUrl =
      TextEditingController(text: _config.baseUrl);
  late final TextEditingController _model =
      TextEditingController(text: _config.model);

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
        baseUrl: _baseUrl.text,
        model: _model.text,
      );

  Future<void> _save() async {
    await widget.preferences.setAiProvider(_current);
    if (!mounted) return;
    setState(() => _config = _current);
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
    final needsEndpoint = provider == AiProvider.custom;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiProvider)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          NexSpacing.lg,
          NexSpacing.md,
          NexSpacing.lg,
          NexSpacing.xl,
        ),
        children: [
          Text(l10n.aiProviderIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: NexSpacing.lg),
          DropdownButtonFormField<AiProvider>(
            initialValue: provider,
            decoration: InputDecoration(
              labelText: l10n.aiProvider,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final candidate in AiProvider.values)
                DropdownMenuItem(
                  value: candidate,
                  child: Text(candidate.label),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _config = _config.copyWith(provider: value);
                _result = null;
              });
            },
          ),
          if (provider != AiProvider.none) ...[
            const SizedBox(height: NexSpacing.md),
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
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => setState(() => _result = null),
            ),
            const SizedBox(height: NexSpacing.md),
            TextField(
              controller: _baseUrl,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.baseUrl,
                hintText: needsEndpoint
                    ? 'https://…'
                    : provider.defaultBaseUrl,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _result = null),
            ),
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
            const SizedBox(height: NexSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _testing ? null : () => unawaited(_test()),
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: Text(l10n.testConnection),
                  ),
                ),
                const SizedBox(width: NexSpacing.md),
                OutlinedButton(
                  onPressed: () => unawaited(_save()),
                  child: Text(l10n.save),
                ),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: NexSpacing.md),
              _ResultBanner(result: _result!),
            ],
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

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final AiTestResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color =
        result.success ? theme.colorScheme.secondary : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NexColors.cardRadius),
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
              result.success
                  ? l10n.connectionOk(result.detail)
                  : result.detail,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
