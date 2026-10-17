part of '../ai_provider_screen.dart';

extension _ProviderAdvancedOptions on _AiProviderScreenState {
  Widget _advanced() {
    final l10n = AppLocalizations.of(context);
    Widget field(
      String id,
      String label,
      String value,
      AiProviderConfig Function(String) update, {
      String? hint,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.md),
      child: TextFormField(
        key: ValueKey('ai-${_config.provider.name}-$id'),
        initialValue: value,
        enabled: !_saving,
        autocorrect: false,
        enableSuggestions: false,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => _updateAdvanced(update(value)),
      ),
    );
    Widget policy(
      String id,
      String label,
      AiCapabilityMode value,
      AiProviderConfig Function(AiCapabilityMode) update,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.md),
      child: DropdownButtonFormField<AiCapabilityMode>(
        key: ValueKey('ai-${_config.provider.name}-$id'),
        initialValue: value,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem(
            value: AiCapabilityMode.automatic,
            child: Text(l10n.aiPolicyDefault),
          ),
          DropdownMenuItem(
            value: AiCapabilityMode.enabled,
            child: Text(l10n.aiPolicyEnabled),
          ),
          DropdownMenuItem(
            value: AiCapabilityMode.disabled,
            child: Text(l10n.aiPolicyDisabled),
          ),
        ],
        onChanged: _saving
            ? null
            : (value) {
                if (value != null) {
                  _updateAdvanced(update(value));
                }
              },
      ),
    );
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor: Theme.of(
        context,
      ).colorScheme.surfaceContainerLow,
      title: Text(
        l10n.aiModelsCapabilities,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      children: [
        Text(
          l10n.aiAdvancedHelp,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        policy(
          'images',
          l10n.aiImageInput,
          _config.images,
          (v) => _config.copyWith(images: v),
        ),
        if (_config.provider != AiProvider.anthropic) ...[
          policy(
            'audio',
            l10n.transcription,
            _config.audio,
            (v) => _config.copyWith(audio: v),
          ),
          field(
            'audio-model',
            l10n.aiSpeechModel,
            _config.transcriptionModel,
            (v) => _config.copyWith(transcriptionModel: v),
            hint: _config.resolvedTranscriptionModel,
          ),
          policy(
            'embeddings',
            l10n.aiSearchEmbeddings,
            _config.embeddings,
            (v) => _config.copyWith(embeddings: v),
          ),
          field(
            'embedding-model',
            l10n.aiEmbeddingModel,
            _config.embeddingModelId,
            (v) => _config.copyWith(embeddingModelId: v),
            hint: _config.embeddingModel,
          ),
        ],
        if (_config.provider == AiProvider.custom) ...[
          field(
            'audio-url',
            l10n.aiSpeechEndpoint,
            _config.transcriptionUrl,
            (v) => _config.copyWith(transcriptionUrl: v),
          ),
          field(
            'embedding-url',
            l10n.aiEmbeddingEndpoint,
            _config.embeddingUrl,
            (v) => _config.copyWith(embeddingUrl: v),
          ),
        ],
      ],
    );
  }
}
