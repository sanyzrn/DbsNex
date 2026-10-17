import 'package:nex_core/nex_core.dart';
import 'local_budget.dart';

/// A conservative input budget, independent of provider/model defaults.
abstract final class CloudBudget {
  static const inputTokens = 24000;
  static const maxTurns = 60;

  /// Preserve the latest real question and its lookup exchange whole. Refuse
  /// an oversized current exchange instead of silently altering user input.
  static List<ChatMessage>? fit(String system, List<ChatMessage> turns) {
    var room = inputTokens - LocalBudget.estimate(system);
    final question = turns.lastIndexWhere(
      (turn) =>
          turn.role == ChatRole.user && !turn.content.startsWith('<<<NOTES\n'),
    );
    final kept = <ChatMessage>[];
    var oldest = turns.length;
    for (var i = turns.length - 1; i >= 0 && kept.length < maxTurns; i--) {
      final cost = LocalBudget.estimate(turns[i].content) + 8;
      if (cost > room) {
        if (i >= question) return null;
        break;
      }
      kept.add(turns[i]);
      oldest = i;
      room -= cost;
    }
    if (question >= 0 && oldest > question) return null;
    final ordered = kept.reversed.toList();
    while (ordered.isNotEmpty && ordered.first.role == ChatRole.assistant) {
      ordered.removeAt(0);
    }
    return ordered;
  }
}
