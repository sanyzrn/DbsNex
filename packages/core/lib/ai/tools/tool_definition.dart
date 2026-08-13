import '../entitlement.dart';

/// Describes one action a chat model can invoke against Nex (09-ai.md —
/// Phase 2, ADR-029).
///
/// [parametersSchema] is a JSON-Schema-shaped map (`{"type": "object",
/// "properties": {...}, "required": [...]}`) — the same shape every major
/// tool-calling wire format (OpenAI, Anthropic, Gemini) already expects, so
/// one [ToolDefinition] serializes to any of them without a contract change,
/// mirroring the "one contract, many wire formats" approach `AIAdapter`
/// already takes.
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parametersSchema,
    required this.requiresEntitlement,
  });

  final String name;
  final String description;
  final Map<String, Object?> parametersSchema;

  /// Checked by [GatedToolExecutor] before dispatch.
  final AiEntitlement requiresEntitlement;
}
