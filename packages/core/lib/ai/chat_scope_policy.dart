import 'chat_adapter.dart';

/// Phase 1's scope ceiling (09-ai.md — "a scope ceiling, not a topic
/// restriction"): any request within a reasonable length/complexity budget
/// is answered in full; a request that exceeds it (e.g. "build me a
/// complete app") gets an explicit "this is outside Nex's current scope" —
/// never a truncated or degraded attempt. This is a model instruction, not a
/// pre-filter: the model itself is best placed to judge whether a request
/// fits, and Nex has no request-side classifier that would make that call
/// (and risk refusing something the model could have answered fine, or vice
/// versa). [nexChatMaxResponseTokens] is the technical backstop for a model
/// that fails to police itself, not the primary mechanism.
const String nexChatScopeCeilingPrompt = '''
You are Nex's built-in assistant, running fully on-device with no internet
access. Help with general questions, math, writing and editing help,
translation, summarization, and idea generation — answered directly and in
full within a normal chat-length reply.

If a request is beyond that scope — for example, asking you to build a
complete application, write a large multi-file codebase, or produce
something that would take far longer than a normal reply — say plainly
that it's outside Nex's current scope, instead of attempting a partial or
truncated answer.''';

/// Hard cap on a single response, as a technical backstop only — see
/// [nexChatScopeCeilingPrompt]. Not a target length; ordinary replies are
/// expected to land well under it.
const int nexChatMaxResponseTokens = 1024;

/// Prepends [nexChatScopeCeilingPrompt] as a system message, unless
/// [conversation] already starts with one (so callers can't accidentally
/// stack it on every turn if they pass their own system message).
List<ChatMessage> withScopeCeiling(List<ChatMessage> conversation) {
  if (conversation.isNotEmpty && conversation.first.role == ChatRole.system) {
    return conversation;
  }
  return [
    const ChatMessage(
      role: ChatRole.system,
      content: nexChatScopeCeilingPrompt,
    ),
    ...conversation,
  ];
}
