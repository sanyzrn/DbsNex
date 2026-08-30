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

/// Puts [nexChatScopeCeilingPrompt] in front of [conversation].
///
/// When [conversation] already starts with a system message — the app's local
/// path always sends one — the ceiling is *appended* to it rather than
/// skipped. Skipping meant the ceiling never reached the model at all on the
/// only path that runs it: the adapter applies this on every call, saw a
/// system message already present, and bowed out, so the instruction existed
/// in core, was tested here, and was silently absent from every real local
/// reply. Appending also keeps the anti-stacking promise: one ceiling per
/// system message, never one per turn.
List<ChatMessage> withScopeCeiling(List<ChatMessage> conversation) {
  if (conversation.isNotEmpty && conversation.first.role == ChatRole.system) {
    final existing = conversation.first.content;
    // Already carrying the ceiling (a caller that applies it itself, or this
    // function run twice over the same list): unchanged.
    if (existing.contains(nexChatScopeCeilingPrompt)) return conversation;
    return [
      ChatMessage(
        role: ChatRole.system,
        content: '$existing\n\n$nexChatScopeCeilingPrompt',
      ),
      ...conversation.skip(1),
    ];
  }
  return [
    const ChatMessage(
      role: ChatRole.system,
      content: nexChatScopeCeilingPrompt,
    ),
    ...conversation,
  ];
}
