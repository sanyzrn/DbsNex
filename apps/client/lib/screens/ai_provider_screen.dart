import 'dart:async';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/display_date.dart';
import '../widgets/ai_capability_status.dart';
import '../widgets/feature_label.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_dialog.dart';
import 'local_model_screen.dart';
import 'package:nex_ai/cloud.dart';
import '../platform/local_ai_support.dart';
import '../platform/nex_preferences.dart';

part 'ai_provider/advanced_options.dart';
part 'ai_provider/capability_card.dart';
part 'ai_provider/model_browser.dart';
part 'ai_provider/provider_widgets.dart';

/// Where the intelligence features get their answers from.
///
/// Until this existed the Intelligence switches in Settings turned on
/// capabilities that had nothing behind them: the only adapters were a no-op
/// and a local heuristic, so "Summarization: on" changed nothing a user could
/// see. A provider makes those switches mean something.
class AiProviderScreen extends StatefulWidget {
  const AiProviderScreen({
    super.key,
    required this.preferences,
    this.client,
    this.onChanged,
  });

  @visibleForTesting
  final http.Client? client;

  final NexPreferences preferences;

  /// Told when a capability check has been stored, which can be after this
  /// screen is gone: the check runs on, and what it found has to reach the
  /// services that act on it.
  final VoidCallback? onChanged;

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

  /// Whether a downloaded model is behind the "on-device" option.
  ///
  /// Read from the binding at build time rather than stored: someone can
  /// download or delete the model and come straight back here, and a value
  /// captured in initState would describe a phone that no longer exists.
  bool get _localModelReady => ChatAdapterBinding.instance.available;

  bool _obscure = true;
  bool _testing = false;
  bool _saving = false;
  AiTestResult? _result;
  AiProviderConfig? _verified;

  /// What the check run from this screen found, by capability, with a null
  /// for each one still being asked; null when none has run here. Only the
  /// outcomes outlive the screen — the reasons are for now.
  Map<AiCapability, AiProbeResult?>? _found;

  /// Which provider and fields [_found] is about.
  String? _foundFor;

  bool get _checking => _found?.values.contains(null) ?? false;

  static String _checkKey(AiProviderConfig config) =>
      '${config.provider.wireName}|${config.capabilityFingerprint}';

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
      _activeProvider != _current.provider || !_sameConfig(_stored, _current);

  /// Whether [tested] (or what is on screen) was stored.
  Future<bool> _save([AiProviderConfig? tested]) async {
    if (_saving) return false;
    final saving = tested ?? _current;
    // The exact configuration being persisted must have passed the test.
    // Choosing on-device only is not a network configuration.
    if (saving.provider != AiProvider.none &&
        (_verified == null ||
            !_sameConfig(saving, _verified!) ||
            !_sameConfig(saving, _current))) {
      return false;
    }
    setState(() => _saving = true);
    try {
      await widget.preferences.setAiProvider(saving);
      if (!mounted) return true;
      setState(() {
        _config = saving;
        _stored = saving;
        _activeProvider = saving.provider;
      });
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).aiProviderSaved,
      );
      return true;
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).aiProviderSaveFailed,
          kind: NexBannerKind.failed,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Tests the connection, saves what passed, then finds out what the model
  /// can do (2.1.8). The check comes after the save on purpose: the
  /// connection is usable the moment it is known to work, and the four
  /// capability requests, a video among them, can take a while.
  Future<void> _test() async {
    if (_testing || _saving || _checking) return;
    final before = widget.preferences.aiProvider;
    setState(() {
      _testing = true;
      _result = null;
    });
    final testing = _current;
    final adapter = CloudAIAdapter(config: testing, client: widget.client);
    var saved = false;
    try {
      final result = await adapter.test();
      if (!mounted || !_sameConfig(_current, testing)) return;
      setState(() {
        _result = result;
        _verified = result.success ? testing : null;
      });
      // Only a working configuration is worth keeping.
      if (result.success) saved = await _save(testing);
    } finally {
      adapter.close();
      if (mounted) setState(() => _testing = false);
    }
    // Only after a passing test: a key that is refused would read as a
    // model that can do nothing.
    if (saved) await _check(testing, before);
  }

  Future<void> _check(AiProviderConfig tested, AiProviderConfig before) async {
    final key = _checkKey(tested);
    setState(() {
      _foundFor = key;
      _found = {for (final capability in AiCapability.values) capability: null};
    });
    final check = await nexCheckCapabilities(
      tested,
      client: widget.client,
      onResult: (capability, result) {
        if (mounted && _foundFor == key) {
          setState(() => _found![capability] = result);
        }
      },
    );
    final prefs = widget.preferences;
    // Stored against what is saved now, and only if that is still what was
    // asked about: fields changed and saved meanwhile make it someone
    // else's answer.
    final stored = prefs.configFor(tested.provider);
    if (_checkKey(stored) != key) return;
    final updated = check.applyTo(stored);
    try {
      await prefs.setAiCapabilityCheck(updated);
    } catch (_) {
      return;
    }
    // Search indexes notes already written as soon as it can. A model found
    // to embed where it could not before must not start that on its own: the
    // switch waits for the person, as an upgrade has always made it wait.
    var held = false;
    final active = prefs.aiProvider;
    if (active.provider == tested.provider &&
        nexNewlyOffered(before, active).contains(AiCapability.embeddings)) {
      final capabilities = prefs.aiCapabilities;
      if (capabilities.semanticSearch || capabilities.relatedNotes) {
        await prefs.setAiCapabilities(
          capabilities.copyWith(semanticSearch: false, relatedNotes: false),
        );
        held = true;
      }
    }
    widget.onChanged?.call();
    if (!mounted) return;
    AiProviderConfig carry(AiProviderConfig config) => config.copyWith(
      images: updated.images,
      audio: updated.audio,
      embeddings: updated.embeddings,
      video: updated.video,
      checkedAt: updated.checkedAt,
      checkedFor: updated.checkedFor,
    );
    setState(() {
      if (_config.provider == tested.provider) {
        _config = carry(_config);
        _stored = carry(_stored);
        if (_verified?.provider == tested.provider) {
          _verified = carry(_verified!);
        }
      }
    });
    if (held) {
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).aiSearchHeld,
      );
    }
  }

  /// The model saved for [provider], when there is one; the picker's
  /// example otherwise.
  String _savedModelOr(AiProvider provider) {
    final saved = widget.preferences.configFor(provider).model.trim();
    return saved.isNotEmpty ? saved : provider.exampleModel;
  }

  static bool _sameConfig(AiProviderConfig a, AiProviderConfig b) {
    final right = b.toMap();
    return a.toMap().entries.every((entry) => right[entry.key] == entry.value);
  }

  void _updateAdvanced(AiProviderConfig config) => setState(() {
    _config = config;
    _result = null;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = _config.provider;
    final needsEndpoint = provider.needsBaseUrl;
    return Scaffold(
      appBar: NexAppBar(title: Text(l10n.aiProvider)),
      // Test and Save live in a bar of their own. Six provider rows plus three
      // fields is more than one screenful, so inline actions sat below the fold
      // — the two buttons the screen exists for were the two you had to go
      // looking for.
      bottomNavigationBar: _ActionBar(
        testing: _testing || _saving || _checking,
        canSave:
            _dirty &&
            !_testing &&
            !_saving &&
            (provider == AiProvider.none ||
                (_verified != null && _sameConfig(_verified!, _current))),
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
          // Said once, here, rather than discovered later by a mic button that
          // does nothing: the local model reads and writes text and that is
          // all it does.
          if (_localModelReady) ...[
            const SizedBox(height: NexSpacing.sm),
            Text(
              l10n.aiProviderLocalNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: NexSpacing.lg),
          // A list, not a dropdown. Six providers behind a popup menu meant the
          // one thing this screen is for was hidden behind a tap, and the menu
          // itself was the last Material default left in the app — a different
          // shape, a different shadow and a different motion from everything
          // around it.
          for (final candidate in AiProvider.values) ...[
            _ProviderTile(
              provider: candidate,
              name: nexProviderName(l10n, candidate),
              selected: candidate == provider,
              subtitle: candidate == AiProvider.none
                  // "On-device" used to mean the tag heuristics and nothing
                  // else, and the copy said so. With a model downloaded it
                  // means a real one, and a subtitle still promising less
                  // than the phone can do is how someone concludes the two
                  // gigabytes did nothing.
                  ? (_localModelReady
                        ? l10n.aiProviderNoneSubtitleLocal
                        : l10n.aiProviderNoneSubtitle)
                  : _savedModelOr(candidate),
              onTap: () {
                if (_saving || candidate == provider) return;
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
          // Managing the downloaded model belongs here, beside choosing it.
          // It used to be its own Settings row, which meant the switch that
          // turns the on-device model on and the screen that puts one on the
          // phone were in different places, and picking "On-device only"
          // looked like it had done nothing.
          if (LocalAi.flavorSupportsLocalModels &&
              provider == AiProvider.none) ...[
            const SizedBox(height: NexSpacing.sm),
            _ManageModelRow(
              installed: _localModelReady,
              onTap: () async {
                await Navigator.push(
                  context,
                  NexPageRoute<void>(
                    builder: (_) =>
                        LocalModelScreen(preferences: widget.preferences),
                  ),
                );
                // The model may have arrived or been deleted while that screen
                // was open, and every label here depends on which.
                if (mounted) setState(() {});
              },
            ),
          ],
          if (provider != AiProvider.none) ...[
            const SizedBox(height: NexSpacing.sm),
            TextField(
              enabled: !_saving,
              controller: _key,
              selectionWidthStyle: BoxWidthStyle.tight,
              contextMenuBuilder: nexReadingMenu,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              // Keys, endpoints and model ids are machine text, never prose.
              // Left in the interface's direction they render right-to-left
              // under a Persian UI: the caret starts at the wrong end, a
              // pasted key reads back-to-front, and `https://…` puts its
              // scheme on the right.
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
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
                enabled: !_saving,
                controller: _baseUrl,
                selectionWidthStyle: BoxWidthStyle.tight,
                contextMenuBuilder: nexReadingMenu,
                autocorrect: false,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                decoration: InputDecoration(
                  labelText: nexLabel(
                    context,
                    'Chat endpoint URL',
                    'آدرس کامل سرویس گفتگو',
                  ),
                  hintText: 'https://api.example.com/v1/chat/completions',
                  // Said outright, because every other app in this space
                  // quietly appends a path and people have learned to type
                  // only the host.
                  helperText: nexLabel(
                    context,
                    'Used exactly as written — nothing is added to it.',
                    'دقیقاً همان‌طور که نوشته می‌شود استفاده می‌شود و چیزی به آن اضافه نمی‌شود.',
                  ),
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _result = null),
              ),
            ],
            const SizedBox(height: NexSpacing.md),
            TextField(
              enabled: !_saving,
              controller: _model,
              selectionWidthStyle: BoxWidthStyle.tight,
              contextMenuBuilder: nexReadingMenu,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                labelText: l10n.model,
                hintText: needsEndpoint ? null : provider.defaultModel,
                // Said outright: a hint only shows in a focused empty field,
                // so the model actually used when this is left empty was
                // nowhere to be seen.
                helperText: needsEndpoint
                    ? null
                    : l10n.aiModelDefault(provider.defaultModel),
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: const ValueKey('ai-model-browse'),
                  tooltip: l10n.aiModelBrowse,
                  icon: const Icon(Icons.format_list_bulleted),
                  onPressed: _saving ? null : () => unawaited(_browseModels()),
                ),
              ),
              onChanged: (_) => setState(() => _result = null),
            ),
            const SizedBox(height: NexSpacing.sm),
            // Under the field, because this is the field it is about. Every
            // provider here sells models across an order of magnitude of
            // capability at the same endpoint, and the cheap end genuinely
            // cannot do what Nex asks of it — a summary is a judgement, and a
            // tool call is an instruction followed exactly. A key that
            // connects and then answers badly is the hardest kind of setup to
            // debug from the outside, so the choice is named here rather than
            // left to whichever id the person had to hand.
            Text(
              l10n.modelChoiceHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textDirection: nexDirectionOf(l10n.modelChoiceHint),
              textAlign: TextAlign.start,
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: NexSpacing.lg),
            _ResultBanner(result: _result!),
          ],
          if (provider != AiProvider.none) ...[
            const SizedBox(height: NexSpacing.lg),
            _CapabilityCard(
              config: _current,
              found: _foundFor == _checkKey(_current) ? _found : null,
              canCheck:
                  !_dirty &&
                  !_testing &&
                  !_saving &&
                  !_checking &&
                  _current.isUsable,
              solar: widget.preferences.solarCalendar,
              onCheck: () => unawaited(_test()),
            ),
            if (provider != AiProvider.anthropic) ...[
              const SizedBox(height: NexSpacing.md),
              _advanced(),
            ],
            const SizedBox(height: NexSpacing.lg),
            const Divider(),
            const SizedBox(height: NexSpacing.sm),
            Text(l10n.aiKeyStorage, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
