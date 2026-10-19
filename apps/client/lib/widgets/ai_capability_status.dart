import 'package:nex_ai/cloud.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;

import '../l10n/app_localizations.dart';

/// A provider's name as the reader's language says it.
///
/// The brands stay as they are written everywhere; the two that are
/// descriptions — on-device, and a gateway of your own — are translated.
/// `AiProvider.label` stays English: it is also the name the request log
/// records, which is data rather than interface.
String nexProviderName(AppLocalizations l10n, AiProvider provider) =>
    switch (provider) {
      AiProvider.none => l10n.aiProviderNoneLabel,
      AiProvider.custom => l10n.aiProviderCustomLabel,
      _ => provider.label,
    };

/// How one capability stands, for an icon and a colour.
enum NexCapabilityState { works, checking, expected, off, unknown }

/// What to say about [capability] for [config] (2.1.8).
///
/// [found] is what a check run on this screen found, with its reason; once
/// the screen is left only the outcome is stored, and the line is read from
/// the configuration instead. Where Nex reaches no such service at all the
/// line says so by name, before anything else — no check can change that.
({NexCapabilityState state, String line}) nexCapabilityLine(
  AppLocalizations l10n,
  AiProviderConfig config,
  AiCapability capability, {
  AiProbeResult? found,
  bool checking = false,
}) {
  final persian = l10n.localeName == 'fa';
  final provider = config.provider;
  if (provider == AiProvider.none) {
    return (state: NexCapabilityState.off, line: l10n.aiCanNeedsCloud);
  }
  final name = nexProviderName(l10n, provider);
  final absent = switch (capability) {
    AiCapability.images => null,
    AiCapability.audio =>
      provider == AiProvider.anthropic
          ? l10n.aiCanAbsentAudio(name)
          : provider != AiProvider.gemini &&
                config.transcriptionEndpoint == null
          ? l10n.aiCanAbsentAddress
          : null,
    AiCapability.embeddings =>
      provider == AiProvider.anthropic
          ? l10n.aiCanAbsentSearch(name)
          : config.embeddingEndpoint == null
          ? l10n.aiCanAbsentAddress
          : null,
    AiCapability.video =>
      provider == AiProvider.gemini ? null : l10n.aiCanAbsentVideo,
  };
  if (absent != null) return (state: NexCapabilityState.off, line: absent);
  if (checking) {
    return (state: NexCapabilityState.checking, line: l10n.aiCanChecking);
  }
  String works() => switch (capability) {
    AiCapability.audio => l10n.aiCanWorksWith(
      config.resolvedTranscriptionModel,
    ),
    AiCapability.embeddings => l10n.aiCanWorksWith(config.embeddingModel),
    _ => l10n.aiCanWorks,
  };
  String status(String line, int? code) =>
      code == null ? line : '$line (${nexDigits('$code', persian: persian)})';
  if (found != null) {
    return switch (found.verdict) {
      AiProbeVerdict.works => (state: NexCapabilityState.works, line: works()),
      AiProbeVerdict.unknown => (
        state: NexCapabilityState.unknown,
        line: status(l10n.aiCanUnknown, found.status),
      ),
      AiProbeVerdict.refused || AiProbeVerdict.absent => (
        state: NexCapabilityState.off,
        line: status(switch (capability) {
          AiCapability.images => l10n.aiCanRefusedImages,
          AiCapability.audio => l10n.aiCanRefusedAudio(
            config.resolvedTranscriptionModel,
          ),
          AiCapability.embeddings => l10n.aiCanRefusedSearch(
            config.embeddingModel,
          ),
          AiCapability.video => l10n.aiCanRefusedVideo,
        }, found.status),
      ),
    };
  }
  final mode = switch (capability) {
    AiCapability.images => config.images,
    AiCapability.audio => config.audio,
    AiCapability.embeddings => config.embeddings,
    AiCapability.video => config.video,
  };
  final supported = switch (capability) {
    AiCapability.images => config.supportsImages,
    AiCapability.audio => config.supportsTranscription,
    AiCapability.embeddings => config.supportsEmbeddings,
    AiCapability.video => config.supportsVideo,
  };
  if (config.checkedTime != null && mode != AiCapabilityMode.automatic) {
    return mode == AiCapabilityMode.enabled
        ? (state: NexCapabilityState.works, line: works())
        : (state: NexCapabilityState.off, line: l10n.aiCanFailedBefore);
  }
  return supported
      ? (state: NexCapabilityState.expected, line: l10n.aiCanExpected)
      : (state: NexCapabilityState.off, line: l10n.aiCanUncheckedOff);
}
