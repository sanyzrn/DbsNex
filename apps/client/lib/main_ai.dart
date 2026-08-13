import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ai/nex_ai.dart';
import 'package:nex_core/nex_core.dart';
import 'bootstrap_host.dart';
import 'platform/crash_reporter.dart';

/// Entry point for the "ai" Android flavor (09-ai.md — Phase 1, ADR-031).
/// The only file outside packages/ai allowed to import package:nex_ai/ —
/// CI's ai-deletion-proof job enforces this. Otherwise identical to
/// main.dart; see that file for why each line here is here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  (await NexCrashLog.open()).install();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  AIAdapterBinding.bind(const OnDeviceAIAdapter());
  ChatAdapterBinding.bind(const PlaceholderLocalChatAdapter());
  runApp(const NexBootstrapHost());
}
