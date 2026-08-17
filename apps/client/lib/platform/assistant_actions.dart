import 'dart:convert';

import 'package:flutter/foundation.dart';

/// What the assistant is allowed to do to someone's notes.
enum AssistantActionKind { create, edit, delete, tag }

/// One thing the assistant has asked to do, already parsed and validated.
///
/// Never executed on arrival. Every one of these is shown to the user as a
/// sentence with a button under it — see `_ActionCard` in the chat sheet. A
/// model that misreads "which one did I write about the cooler" as "delete
/// the note about the cooler" is not a hypothetical on the small models this
/// app is usually pointed at, and a wrong delete is not something an apology
/// afterwards fixes.
@immutable
class AssistantAction {
  const AssistantAction({
    required this.kind,
    this.noteId,
    this.text,
    this.addTags = const [],
    this.removeTags = const [],
  });

  final AssistantActionKind kind;

  /// The note being acted on. Null only for [AssistantActionKind.create].
  final String? noteId;

  /// The note's new contents, for create and edit.
  final String? text;

  final List<String> addTags;
  final List<String> removeTags;
}

/// The instruction block appended to the system prompt when acting is on.
///
/// A text protocol rather than the providers' own function calling, and
/// deliberately so. Tool calling is three different wire shapes, and — the
/// deciding fact — the free and cheap models this app is most often pointed
/// at either do not implement it or implement it badly. A fenced block is
/// something every model that can write JSON at all can produce, which makes
/// this the version that works for the people actually using it.
const assistantActionPrompt = '''
You can act on the user's notes. When they ask you to, reply with nothing but
a fenced block tagged `nex` containing one JSON object:

```nex
{"action": "create", "text": "buy oat milk"}
```
```nex
{"action": "edit", "id": "<note id>", "text": "the full new text"}
```
```nex
{"action": "delete", "id": "<note id>"}
```
```nex
{"action": "tag", "id": "<note id>", "add": ["work"], "remove": ["home"]}
```

Rules: one action per reply, and no words outside the block — the app shows
the user what you asked for and waits for them to confirm it, so anything you
write around it is never read. Ids come only from the notes listed below;
never invent one. If you are not certain which note is meant, ask instead of
guessing. For anything that is a question rather than a request to change
something, answer normally and use no block at all.''';

/// The fenced block, wherever in the reply it landed.
///
/// Models put fences after a preamble, in the wrong case, or with a trailing
/// space, whatever they are told. Being liberal here costs one regex and
/// saves the feature from looking broken half the time.
final _blockPattern = RegExp(
  r'```[ \t]*(?:nex|json)?[ \t]*\r?\n(.*?)```',
  dotAll: true,
  caseSensitive: false,
);

/// Reads the action out of a reply, or null when there is not one.
///
/// Returns null for anything malformed rather than throwing: an unparseable
/// block means the model wrote prose that happened to contain a fence, and
/// the honest response is to show the prose.
AssistantAction? parseAssistantAction(String reply) {
  final match = _blockPattern.firstMatch(reply);
  final body = (match?.group(1) ?? reply).trim();
  if (!body.startsWith('{')) return null;

  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;

  final id = _string(decoded['id']);
  final text = _string(decoded['text']);
  return switch (_string(decoded['action'])?.toLowerCase()) {
    'create' when text != null => AssistantAction(
      kind: AssistantActionKind.create,
      text: text,
    ),
    'edit' when id != null && text != null => AssistantAction(
      kind: AssistantActionKind.edit,
      noteId: id,
      text: text,
    ),
    'delete' when id != null => AssistantAction(
      kind: AssistantActionKind.delete,
      noteId: id,
    ),
    'tag' when id != null => _tagAction(decoded, id),
    _ => null,
  };
}

AssistantAction? _tagAction(Map<Object?, Object?> decoded, String id) {
  final add = _strings(decoded['add']);
  final remove = _strings(decoded['remove']);
  // A tag action that neither adds nor removes anything is not an action.
  if (add.isEmpty && remove.isEmpty) return null;
  return AssistantAction(
    kind: AssistantActionKind.tag,
    noteId: id,
    addTags: add,
    removeTags: remove,
  );
}

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (_string(entry) case final name?) name,
  ];
}

/// What the model wrote with the block taken out.
///
/// Used when a reply carries both, which the prompt forbids and models do
/// anyway. The prose is worth showing; the JSON never is.
String withoutActionBlock(String reply) =>
    reply.replaceAll(_blockPattern, '').trim();
