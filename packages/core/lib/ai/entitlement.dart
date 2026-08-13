/// Personal-assistant tier gating (09-ai.md — Free vs. Paid Boundary, ADR-030).
///
/// `free` covers general chat; `personalAssistant` covers memory, tool-calling
/// into Nex's own capabilities, and cross-AI import. No payment processor
/// exists yet — [AiEntitlementProvider] is the seam a real subscription check
/// replaces later without touching anything that depends on it.
enum AiEntitlement { free, personalAssistant }

abstract interface class AiEntitlementProvider {
  AiEntitlement get current;
}

/// Always returns the same entitlement. Defaults to `free`, the same
/// safe-default pattern as `NullAIAdapter` and `AiCapabilities.allOff` —
/// nothing paid is ever accidentally on.
class StaticEntitlementProvider implements AiEntitlementProvider {
  const StaticEntitlementProvider([this.current = AiEntitlement.free]);

  @override
  final AiEntitlement current;
}
