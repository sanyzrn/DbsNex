import 'ai_adapter.dart';

/// Process-wide AI adapter binding (09-ai.md dependency inversion).
///
/// Core never imports `packages/ai`. Composition roots (or an optional AI
/// package initializer) call [bind]; until then [instance] is [NullAIAdapter]
/// so capture/search keep working with AI unavailable.
class AIAdapterBinding {
  AIAdapterBinding._();

  static AIAdapter _instance = const NullAIAdapter();

  static AIAdapter get instance => _instance;

  static void bind(AIAdapter adapter) {
    _instance = adapter;
  }

  /// Restores the no-AI default (tests / after deleting packages/ai).
  static void reset() {
    _instance = const NullAIAdapter();
  }
}
