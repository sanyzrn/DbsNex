import 'package:flutter/widgets.dart' show runApp;
import 'package:nex_ai/nex_ai.dart';
import 'package:nex_core/nex_core.dart';

import 'bootstrap_host.dart';
import 'entry_bootstrap.dart';

/// Entry point for the "ai" Android flavor (09-ai.md — Phase 1, ADR-031).
/// The only file outside packages/ai allowed to import package:nex_ai/ —
/// CI's ai-deletion-proof job enforces this. Otherwise identical to
/// main.dart; see entry_bootstrap.dart for the shared setup.
Future<void> main() async {
  await bootstrapEntry();
  AIAdapterBinding.bind(const OnDeviceAIAdapter());
  ChatAdapterBinding.bind(const PlaceholderLocalChatAdapter());
  runApp(const NexBootstrapHost());
}
