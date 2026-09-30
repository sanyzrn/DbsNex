/// Nex — the cloud AI provider layer (ADR-035).
///
/// Everything that talks to a provider the person configured in Settings →
/// Intelligence: the adapters, their options, the assistant's actions, and
/// the on-device record of every request (ADR-033). Pure Dart over `http`;
/// no platform plugin.
///
/// `apps/client` imports this library freely. The on-device runtime is the
/// other library, `nex_ai.dart`, and stays confined to the "ai" flavor's
/// entry point — CI's `ai-deletion-proof` job removes it and proves the rest
/// of the graph still builds.
library;

export 'src/cloud/ai_provider.dart';
export 'src/cloud/assistant_actions.dart';
export 'src/cloud/disclosure_log.dart';
