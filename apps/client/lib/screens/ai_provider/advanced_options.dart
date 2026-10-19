part of '../ai_provider_screen.dart';

/// The speech and search models, and for Custom where they live.
///
/// What used to sit here as well — three dropdowns asking whether this model
/// takes images, audio and embeddings — is gone (2.1.8). Nobody could be
/// expected to know, the providers' own pages disagree with their APIs, and
/// a wrong guess either hid a feature that worked or offered one that failed
/// on every request. Test now asks the model, and the card above shows what
/// it said. What is left is what only the person can know: that their
/// account uses another model, or a gateway serves these elsewhere.
extension _ProviderAdvancedOptions on _AiProviderScreenState {
  Widget _advanced() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget field(
      String id,
      String label,
      String value,
      AiProviderConfig Function(String) update, {
      String? fallback,
      TextInputType? keyboard,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.md),
      child: TextFormField(
        key: ValueKey('ai-${_config.provider.name}-$id'),
        initialValue: value,
        enabled: !_saving,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: keyboard,
        // Model ids and addresses are machine text: left to right always.
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        decoration: InputDecoration(
          labelText: label,
          hintText: fallback,
          helperText: fallback == null ? null : l10n.aiModelDefault(fallback),
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => _updateAdvanced(update(value)),
      ),
    );
    final custom = _config.provider == AiProvider.custom;
    return ExpansionTile(
      key: ValueKey('ai-advanced-${_config.provider.name}'),
      tilePadding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
      childrenPadding: const EdgeInsets.all(NexSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
      ),
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      collapsedBackgroundColor: theme.colorScheme.surfaceContainerLow,
      title: Text(l10n.aiModelsCapabilities, style: theme.textTheme.bodyMedium),
      children: [
        Text(
          l10n.aiAdvancedHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        field(
          'audio-model',
          l10n.aiSpeechModel,
          _config.transcriptionModel,
          (v) => _config.copyWith(transcriptionModel: v),
          fallback: _config
              .copyWith(transcriptionModel: '', model: _model.text)
              .resolvedTranscriptionModel,
        ),
        if (custom)
          field(
            'audio-url',
            l10n.aiSpeechEndpoint,
            _config.transcriptionUrl,
            (v) => _config.copyWith(transcriptionUrl: v),
            keyboard: TextInputType.url,
          ),
        field(
          'embedding-model',
          l10n.aiEmbeddingModel,
          _config.embeddingModelId,
          (v) => _config.copyWith(embeddingModelId: v),
          fallback: _config.copyWith(embeddingModelId: '').embeddingModel,
        ),
        if (custom)
          field(
            'embedding-url',
            l10n.aiEmbeddingEndpoint,
            _config.embeddingUrl,
            (v) => _config.copyWith(embeddingUrl: v),
            keyboard: TextInputType.url,
          ),
      ],
    );
  }
}
