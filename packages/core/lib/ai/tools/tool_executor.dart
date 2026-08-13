import '../entitlement.dart';
import 'nex_tool_registry.dart';
import 'tool_call.dart';

abstract interface class ToolExecutor {
  ToolResult execute(ToolCall call);
}

/// Checks [AiEntitlement] before dispatching to [NexToolRegistry] — the
/// concrete gating mechanism behind the Free vs. Paid Boundary (09-ai.md,
/// ADR-030). No payment processor is wired up: [entitlement] is whatever
/// [AiEntitlementProvider] the caller supplies, defaulting to
/// [StaticEntitlementProvider]'s `free` everywhere until a real subscription
/// check exists.
class GatedToolExecutor implements ToolExecutor {
  GatedToolExecutor(this._registry, this._entitlement);

  final NexToolRegistry _registry;
  final AiEntitlementProvider _entitlement;

  @override
  ToolResult execute(ToolCall call) {
    final definition = _registry.definitionFor(call.name);
    if (definition == null) {
      return ToolResult.error('unknown_tool: ${call.name}');
    }
    if (!_satisfies(_entitlement.current, definition.requiresEntitlement)) {
      return ToolResult.error(
        'entitlement_required: ${definition.requiresEntitlement.name}',
      );
    }
    return _registry.dispatch(call);
  }

  /// `free` requires nothing; every other tier must match exactly. Revisit
  /// this if a third tier is ever added between `free` and `personalAssistant`.
  bool _satisfies(AiEntitlement current, AiEntitlement required) {
    if (required == AiEntitlement.free) return true;
    return current == required;
  }
}
