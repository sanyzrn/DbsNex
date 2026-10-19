part of '../ai_provider_screen.dart';

/// Picking a model from the provider's own list (2.1.8), with the key that
/// is on screen. Typing an id from memory was how most setups that connect
/// and then fail every request began.
extension _ProviderModelBrowser on _AiProviderScreenState {
  Future<void> _browseModels() async {
    final l10n = AppLocalizations.of(context);
    final config = _current;
    if (config.apiKey.trim().isEmpty) {
      nexShowBanner(context, message: l10n.aiModelBrowseNeedsKey);
      return;
    }
    final chosen = await nexShowSheet<String>(
      context: context,
      builder: (_) => _ModelBrowser(config: config, client: widget.client),
    );
    if (chosen == null || !mounted) return;
    _model.text = chosen;
    // Through the state's own method: an extension may not call setState.
    _updateAdvanced(_config);
  }
}

class _ModelBrowser extends StatefulWidget {
  const _ModelBrowser({required this.config, this.client});

  final AiProviderConfig config;
  final http.Client? client;

  @override
  State<_ModelBrowser> createState() => _ModelBrowserState();
}

class _ModelBrowserState extends State<_ModelBrowser> {
  late final CloudAIAdapter _adapter = CloudAIAdapter(
    config: widget.config,
    client: widget.client,
  );
  late final Future<List<String>> _models = _adapter.listModels();
  final _query = TextEditingController();

  @override
  void dispose() {
    _adapter.close();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = widget.config.provider;
    final current = widget.config.resolvedModel;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NexSpacing.md,
          NexSpacing.md,
          NexSpacing.md,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.aiModelBrowseTitle(nexProviderName(l10n, provider)),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.md),
            TextField(
              key: const ValueKey('ai-model-search'),
              controller: _query,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                hintText: l10n.aiModelBrowseSearch,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: NexSpacing.sm),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _models,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: NexInlineSpinner());
                  }
                  if (snapshot.hasError) {
                    final detail = snapshot.error is AiUnavailableException
                        ? (snapshot.error! as AiUnavailableException).message
                        : '';
                    return _BrowserMessage(
                      icon: Icons.cloud_off_outlined,
                      text: l10n.aiModelBrowseFailed,
                      detail: detail == const AiUnavailableException().message
                          ? null
                          : detail,
                    );
                  }
                  final needle = _query.text.trim().toLowerCase();
                  final models = [
                    for (final id in snapshot.data!)
                      if (needle.isEmpty || id.toLowerCase().contains(needle))
                        id,
                  ];
                  if (models.isEmpty) {
                    return _BrowserMessage(
                      icon: Icons.search_off,
                      text: l10n.aiModelBrowseEmpty,
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.only(bottom: nexBottomInset(context)),
                    itemCount: models.length,
                    itemBuilder: (context, index) {
                      final id = models[index];
                      final selected = id == current;
                      return ListTile(
                        key: ValueKey('ai-model-$id'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.sm,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(NexRadius.md),
                        ),
                        selected: selected,
                        selectedTileColor: scheme.primary.withValues(
                          alpha: 0.08,
                        ),
                        title: Text(
                          id,
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: id == provider.defaultModel
                            ? Text(l10n.aiModelBrowseDefault)
                            : null,
                        trailing: selected
                            ? Icon(Icons.check_circle, color: scheme.primary)
                            : null,
                        onTap: () => Navigator.pop(context, id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserMessage extends StatelessWidget {
  const _BrowserMessage({required this.icon, required this.text, this.detail});

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: NexSpacing.sm),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.xs),
              Text(
                detail!,
                textAlign: TextAlign.center,
                // Usually the provider's own English.
                textDirection: nexDirectionOf(detail!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
