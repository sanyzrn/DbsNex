import 'dart:convert';

import 'package:flutter/foundation.dart';

/// What the assistant is allowed to do to someone's notes.
enum AssistantActionKind {
  create,
  edit,
  delete,
  tag,

  /// Reads rather than writes: the assistant looking through the library for
  /// itself. The only kind that runs without asking, because nothing changes
  /// and waiting for a button before it may read is a conversation nobody
  /// wants to have.
  search,

  /// Several notes into one, the others deleted.
  merge,

  /// A note rewritten as a checklist, one item per line.
  toChecklist,

  /// One checklist item ticked or unticked.
  check,

  /// One app setting, from a short list this app is willing to hand over.
  setting,
}

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
    this.noteIds = const [],
    this.text,
    this.addTags = const [],
    this.removeTags = const [],
    this.index,
    this.settingKey,
    this.settingValue,
  });

  final AssistantActionKind kind;

  /// The note being acted on. Null only for [AssistantActionKind.create].
  final String? noteId;

  /// The note's new contents, for create and edit.
  final String? text;

  final List<String> addTags;
  final List<String> removeTags;

  /// The notes a merge folds together, in the order they will be joined.
  final List<String> noteIds;

  /// Which checklist item [AssistantActionKind.check] means, zero-based.
  final int? index;

  final String? settingKey;
  final String? settingValue;

  /// Whether this changes anything. A search does not, so it is carried out
  /// as soon as it arrives; everything else waits for the user.
  bool get isRead => kind == AssistantActionKind.search;
}

/// The settings the assistant is allowed to change.
///
/// A list rather than a rule, and a short one. "Let it change settings" is a
/// sentence that quietly includes the API key, the sync endpoint and the
/// retention policy, and none of those should ever move because a model read
/// a sentence a certain way. These four are all reversible in one tap from
/// the screen the user is already looking at.
const assistantSettableKeys = {'theme', 'language', 'ai_language'};

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
```nex
{"action": "merge", "ids": ["<id>", "<id>"], "text": "the combined text"}
```
```nex
{"action": "to_checklist", "id": "<note id>"}
```
```nex
{"action": "check", "id": "<note id>", "index": 0, "done": true}
```
```nex
{"action": "setting", "key": "theme", "value": "dark"}
```

Settings you may change, and nothing else: `theme` (light/dark/system),
`language` (en/fa/system), `ai_language` (auto/en/fa).

When you need a note that is not in the list below, look for it first and
wait for the result before doing anything else:

```nex
{"action": "search", "query": "cooler"}
```

Rules: no words outside the block — the app shows
the user what you asked for and waits for them to confirm it, so anything you
write around it is never read. You may send more than one block when a
request genuinely needs several changes; they are confirmed together. Ids
come only from the notes listed below or from a search result; never invent
one. If you are not certain which note is meant, ask instead of
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
  final all = parseAssistantActions(reply);
  return all.isEmpty ? null : all.first;
}

/// Every action in a reply, in the order the model wrote them.
///
/// More than one is allowed because a real request often is more than one —
/// "tag these two and delete the third" is three changes and one intention.
/// They are confirmed together, so the user still sees the whole set before
/// any of it happens.
List<AssistantAction> parseAssistantActions(String reply) {
  final bodies = [
    for (final match in _blockPattern.allMatches(reply)) match.group(1)!.trim(),
  ];
  // A reply that is bare JSON with no fence at all. Models do this when the
  // prompt has been in context a while, and refusing it would mean the
  // feature works for the first few messages of a conversation and then
  // quietly stops.
  if (bodies.isEmpty) bodies.add(reply.trim());

  final actions = <AssistantAction>[];
  for (final body in bodies) {
    if (!body.startsWith('{') && !body.startsWith('[')) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      continue;
    }
    for (final entry in decoded is List ? decoded : [decoded]) {
      if (entry is! Map) continue;
      final action = _action(entry);
      if (action != null) actions.add(action);
    }
  }
  return actions;
}

AssistantAction? _action(Map<Object?, Object?> decoded) {
  final id = _string(decoded['id']);
  final text = _string(decoded['text']);
  final index = decoded['index'];
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
    'search' when _string(decoded['query']) != null => AssistantAction(
      kind: AssistantActionKind.search,
      text: _string(decoded['query']),
    ),
    // Two is the smallest number of notes a merge can be about. One would be
    // a rename with extra steps, and zero is a model filling in a shape.
    'merge' when _strings(decoded['ids']).length > 1 => AssistantAction(
      kind: AssistantActionKind.merge,
      noteIds: _strings(decoded['ids']),
      text: text,
    ),
    'to_checklist' || 'checklist' when id != null => AssistantAction(
      kind: AssistantActionKind.toChecklist,
      noteId: id,
    ),
    'check' when id != null && index is int && index >= 0 => AssistantAction(
      kind: AssistantActionKind.check,
      noteId: id,
      index: index,
    ),
    'setting' => _settingAction(decoded),
    _ => null,
  };
}

/// Only the keys this app has agreed to hand over, and only with a value.
AssistantAction? _settingAction(Map<Object?, Object?> decoded) {
  final key = _string(decoded['key'])?.toLowerCase();
  final value = _string(decoded['value'])?.toLowerCase();
  if (key == null || value == null) return null;
  if (!assistantSettableKeys.contains(key)) return null;
  return AssistantAction(
    kind: AssistantActionKind.setting,
    settingKey: key,
    settingValue: value,
  );
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
