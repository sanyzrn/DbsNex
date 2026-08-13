/// A model's request to invoke one [ToolDefinition], by name and arguments.
class ToolCall {
  const ToolCall({required this.name, this.arguments = const {}});

  final String name;
  final Map<String, Object?> arguments;
}

/// The outcome of executing a [ToolCall].
///
/// Exactly one of [data] / [error] is set, matched by [success] — a plain
/// value type rather than a thrown exception, since a tool failure (unknown
/// tool, ungated call, a use case rejecting its input) is an ordinary result
/// a chat loop feeds back to the model, not a bug.
class ToolResult {
  const ToolResult.ok(this.data) : success = true, error = null;

  const ToolResult.error(String message)
    : success = false,
      data = null,
      error = message;

  final bool success;
  final Object? data;
  final String? error;
}
