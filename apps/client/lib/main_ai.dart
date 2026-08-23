import 'package:flutter/widgets.dart' show runApp;
// nex_ai re-exports the Core AI contracts this file binds, so importing
// nex_core alongside it is redundant.
import 'package:nex_ai/nex_ai.dart';

import 'bootstrap_host.dart';
import 'entry_bootstrap.dart';
import 'platform/local_ai_support.dart';
import 'platform/model_store.dart';

/// Entry point for the "ai" Android flavor (09-ai.md — Phase 1, ADR-031).
/// The only file outside packages/ai allowed to import package:nex_ai/ —
/// CI's ai-deletion-proof job enforces this. Otherwise identical to
/// main.dart; see entry_bootstrap.dart for the shared setup.
Future<void> main() async {
  await bootstrapEntry();
  AIAdapterBinding.bind(const OnDeviceAIAdapter());

  // Only this build can load a model, so only this build offers to download
  // one. Settings reads the flag; nothing in the standard flavor sets it.
  LocalAi.flavorSupportsLocalModels = true;

  // Bound whether or not the weights are on disk yet. LiteRtChatAdapter
  // reports unavailable — a null Future, the same convention every AIAdapter
  // method uses — until the file exists, which is exactly the placeholder's
  // old job done honestly instead of with a canned sentence.
  final store = await NexModelStore.open();
  ChatAdapterBinding.bind(
    LiteRtChatAdapter(modelPath: store.fileFor(NexModels.gemma4E2B).path),
  );
  runApp(const NexBootstrapHost());
}
