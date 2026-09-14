import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';

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

  /// When a note should come back up, or that it should stop coming back up.
  ///
  /// The verb an assistant is for, and the one this list was missing. The
  /// daily brief is built almost entirely out of what is due and what is
  /// overdue, so an assistant that can read that list and not add to it was
  /// describing a job it could not do.
  remind,

  /// A note held at the top of the timeline, or let go.
  pin,

  /// A note's title set or cleared.
  title,

  /// A note brought back out of Recently Deleted.
  ///
  /// The only write here that *undoes* damage rather than doing any, which
  /// is why it is worth having even though nothing else about the trash is
  /// reachable from a conversation.
  restore,

  /// A tag renamed, everywhere it is worn.
  renameTag,

  /// A tag's colour.
  tagColor,

  /// A standing obligation created or changed — the insurance, the rent, the
  /// tablet every eight hours. Not a note; see [NexCommitment].
  commitment,

  /// One of those ticked off, which rolls it forward rather than finishing
  /// it. The difference between a commitment and a reminder in one verb.
  commitmentMet,

  /// One of those removed.
  commitmentDelete,
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
    this.at,
    this.repeat = NoteRepeat.once,
    this.flag,
    this.items = const [],
    this.tagName,
    this.cadence,
    this.every,
    this.commitmentName,
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

  /// When [AssistantActionKind.remind] should fire.
  ///
  /// Null is not "unset" here, it is the instruction: a remind action with
  /// no time on it is the one that clears the reminder. There is nothing
  /// else a dateless reminder could mean, so it does not need a second flag
  /// to say which it is.
  final DateTime? at;

  final NoteRepeat repeat;

  /// True to pin, false to unpin. Null for every other kind.
  ///
  /// A field rather than two kinds, because the confirmation card, the
  /// executor and the parser would all have to carry the pair around and
  /// nothing about the two directions differs except the verb.
  final bool? flag;

  /// A checklist's lines, when [AssistantActionKind.create] is making one.
  ///
  /// "Make me a shopping list with bread, milk and eggs" used to come back
  /// as a text note with three lines in it — which looks almost right and is
  /// not a checklist: nothing in it can be ticked.
  final List<String> items;

  /// The tag a library-wide tag action is about, by name.
  ///
  /// By name and not by id, for the same reason [addTags] is: the model only
  /// ever sees tag names, and an id it had to invent is an id it would
  /// invent. Resolved against the real list when the action runs.
  final String? tagName;

  /// How often a [AssistantActionKind.commitment] comes round, and the count
  /// that goes with it — "every 8 hours" is [NexCadence.hours] and 8.
  final NexCadence? cadence;
  final int? every;

  /// Which standing obligation an action is about, by the name it is stored
  /// under. Like [tagName] and for the same reason: names are all the model
  /// is ever shown, and an id it had to invent is an id it would invent.
  final String? commitmentName;

  /// Whether this changes anything. A search does not, so it is carried out
  /// as soon as it arrives; everything else waits for the user.
  bool get isRead => kind == AssistantActionKind.search;
}

/// The settings the assistant is allowed to change.
///
/// A list rather than a rule. "Let it change settings" is a sentence that
/// quietly includes the API key, the sync endpoint, the app lock and the
/// retention policy, and none of those should ever move because a model read
/// a sentence a certain way.
///
/// What is on the list is everything that passes three tests: a person
/// changes it by hand from a settings screen, it is visible the moment it
/// changes, and it is reversible in one tap from the screen they are already
/// looking at. That is the whole rule, and it is what lets the list grow
/// without the argument being had again each time.
///
/// What stays off it, and always will: the app lock and its timing (a lock a
/// conversation can open is not a lock), the AI provider and its key, the
/// sync endpoint and its token, the entitlement, and anything that deletes —
/// backups, retention, the trash.
const assistantSettableKeys = {
  'theme',
  'language',
  'ai_language',
  // Appearance. Each of these is a switch or a slider on the Appearance
  // screen and shows its effect on the frame after it changes.
  'text_size',
  'background',
  'accent',
  'comfort_mode',
  'haptics',
  // The timeline's own furniture — the four parts of the home screen a
  // person can already turn off one at a time.
  'show_greeting',
  'show_digest',
  'show_search',
  'show_tags',
  // The morning notification and when it arrives. "Wake me with the digest
  // at eight" is a sentence people say to an assistant, and it is two taps
  // in settings.
  'daily_nudge',
  'daily_nudge_time',
};

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
```nex
{"action": "remind", "id": "<note id>", "at": "2026-03-14T09:00", "repeat": "once"}
```
```nex
{"action": "pin", "id": "<note id>", "pinned": true}
```
```nex
{"action": "title", "id": "<note id>", "text": "Boiler"}
```
```nex
{"action": "restore", "id": "<note id>"}
```
```nex
{"action": "rename_tag", "tag": "work", "name": "job"}
```
```nex
{"action": "tag_color", "tag": "work", "color": "#1D4ED8"}
```
```nex
{"action": "commitment", "name": "car insurance", "every": 1, "unit": "years", "at": "2027-03-14T09:00"}
```
```nex
{"action": "commitment_met", "name": "drink water"}
```
```nex
{"action": "commitment_delete", "name": "gym membership"}
```

A `create` makes a checklist instead of a text note when you send items:

```nex
{"action": "create", "items": ["bread", "milk", "eggs"]}
```

`remind` sets when a note comes back up. `at` is local time,
`YYYY-MM-DDTHH:MM`, and must be in the future — work it out from the current
time given below, and never send a date you were not able to work out. `repeat`
is `once`, `daily` or `weekly`. **Leave `at` out entirely to cancel a
reminder**, and send nothing else with it. `title` with no `text` clears the
title. `restore` only works on a note that is in Recently Deleted.

`commitment` is for the things that come back round — a yearly insurance
renewal, the rent, a tablet every eight hours, water every two. They are not
notes and never appear on the timeline. `unit` is `hours`, `days`, `weeks`,
`months` or `years`, and `at` is when it next falls due, in the same local
`YYYY-MM-DDTHH:MM` shape as a reminder. Sending the same `name` again edits
the one that is already there rather than making a second. Use
`commitment_met` when they say they have done one — it rolls forward to the
next turn by itself, so never send a new date for that.

Settings you may change, and nothing else:
`theme` (light/dark/system), `language` (en/fa/system),
`ai_language` (auto/en/fa),
`text_size` (small/default/large/larger),
`background` (plain/aurora/ripple/weave/dots/dusk/topography/prism),
`accent` (a `#RRGGBB` colour, or `default`),
`comfort_mode` (on/off), `haptics` (on/off),
`show_greeting`, `show_digest`, `show_search`, `show_tags` (on/off),
`daily_nudge` (on/off), `daily_nudge_time` (`HH:MM`).

When you need a note that is not in the list below, look for it first and
wait for the result before doing anything else:

```nex
{"action": "search", "query": "cooler"}
```

Rules: nothing outside the block — no words, no emoji, no leading bullet,
not even "Sure:". The app shows the user what you asked for and waits for
them to confirm it, so anything you write around it is never read, and any
preference you have been given about tone or emoji does not apply to a reply
that carries a block. You may send more than one block when a
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
  // A reply with no fence at all. Models do this when the prompt has been in
  // context a while, and refusing it would mean the feature works for the
  // first few messages of a conversation and then quietly stops.
  //
  // Every JSON object in the reply, not the reply itself: an action arriving
  // with anything at all in front of it — a stray emoji, "Sure:", a leading
  // bullet — used to fail `startsWith('{')`, and a failed parse does not
  // degrade to "no action", it degrades to the raw protocol JSON appearing in
  // the chat as the assistant's answer. That is what a user sees when they
  // ask for a note and get `{"action": "create", ...}` back.
  if (bodies.isEmpty) bodies.addAll(_objectsIn(reply));

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

/// Every top-level `{...}` in a string, braces balanced and strings respected.
///
/// A regex cannot do this: `}` is legal inside a JSON string value, and note
/// text routinely contains one. Scanning is a few lines and cannot be fooled
/// by the note that happens to be about a shell script.
///
/// Only depth-1 objects are returned — a nested one is part of its parent, not
/// a second action.
List<String> _objectsIn(String reply) {
  final found = <String>[];
  var depth = 0;
  var start = -1;
  var inString = false;
  var escaped = false;
  for (var i = 0; i < reply.length; i++) {
    final char = reply[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
    } else if (char == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (char == '}') {
      if (depth == 0) continue;
      depth--;
      if (depth == 0 && start >= 0) {
        found.add(reply.substring(start, i + 1));
        start = -1;
      }
    }
  }
  return found;
}

AssistantAction? _action(Map<Object?, Object?> decoded) {
  final id = _string(decoded['id']);
  final text = _string(decoded['text']);
  final index = decoded['index'];
  final items = _strings(decoded['items']);
  return switch (_string(decoded['action'])?.toLowerCase()) {
    // Items first: a create that carries both is a checklist whose lines the
    // model also wrote out as prose, and the checklist is the thing that was
    // asked for.
    'create' when items.isNotEmpty => AssistantAction(
      kind: AssistantActionKind.create,
      items: items,
      text: items.join('\n'),
    ),
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
    'remind' || 'reminder' when id != null => _remindAction(decoded, id),
    // `pinned` decides which way, and its absence means pin: "pin this" is
    // the request people make, and a model that leaves the field off has
    // still said which one it meant.
    'pin' when id != null => AssistantAction(
      kind: AssistantActionKind.pin,
      noteId: id,
      flag: _bool(decoded['pinned']) ?? true,
    ),
    'unpin' when id != null => AssistantAction(
      kind: AssistantActionKind.pin,
      noteId: id,
      flag: false,
    ),
    // No text is the instruction, not a malformed action: it clears the
    // title. Same shape as remind's missing `at`.
    'title' when id != null => AssistantAction(
      kind: AssistantActionKind.title,
      noteId: id,
      text: text,
    ),
    'restore' || 'undelete' when id != null => AssistantAction(
      kind: AssistantActionKind.restore,
      noteId: id,
    ),
    'rename_tag' when _string(decoded['tag']) != null => _renameTagAction(
      decoded,
    ),
    'tag_color' when _string(decoded['tag']) != null => _tagColorAction(
      decoded,
    ),
    'commitment' when _string(decoded['name']) != null => _commitmentAction(
      decoded,
    ),
    'commitment_met' when _string(decoded['name']) != null => AssistantAction(
      kind: AssistantActionKind.commitmentMet,
      commitmentName: _string(decoded['name']),
    ),
    'commitment_delete' when _string(decoded['name']) != null =>
      AssistantAction(
        kind: AssistantActionKind.commitmentDelete,
        commitmentName: _string(decoded['name']),
      ),
    _ => null,
  };
}

/// A standing obligation, created or changed.
///
/// The cadence is required and the date is not: editing one to say "actually
/// it is every three months" should not force the model to restate a due date
/// it was never told. A missing date means "leave it where it is" on an edit,
/// and the app picks one on a create.
AssistantAction? _commitmentAction(Map<Object?, Object?> decoded) {
  final name = _string(decoded['name']);
  if (name == null) return null;
  final unit = _string(decoded['unit'])?.toLowerCase();
  // No default cadence. "Every what?" has no sensible guess — a wrong one is
  // an insurance renewal quietly set to every day — so an action that does
  // not say is not an action.
  if (unit == null || !_cadences.containsKey(unit)) return null;
  final at = _string(decoded['at']);
  final parsed = at == null ? null : DateTime.tryParse(at);
  // Present but unreadable is a refusal, not a fallback: same rule as a
  // reminder's date, and for the same reason.
  if (at != null && parsed == null) return null;
  return AssistantAction(
    kind: AssistantActionKind.commitment,
    commitmentName: name,
    cadence: _cadences[unit],
    every: switch (decoded['every']) {
      final int value when value >= 1 => value.clamp(1, 1000),
      _ => 1,
    },
    at: parsed == null
        ? null
        : (parsed.isUtc ? parsed.toLocal() : parsed),
  );
}

/// The units the protocol names, mapped to the cadences the app has.
///
/// Spelled out rather than matched against `NexCadence.values` by name, so
/// that renaming an enum case cannot silently change what a model is allowed
/// to say — the prompt above is the contract, and it is a string.
const _cadences = <String, NexCadence>{
  'hours': NexCadence.hours,
  'hour': NexCadence.hours,
  'days': NexCadence.days,
  'day': NexCadence.days,
  'weeks': NexCadence.weeks,
  'week': NexCadence.weeks,
  'months': NexCadence.months,
  'month': NexCadence.months,
  'years': NexCadence.years,
  'year': NexCadence.years,
};

/// A reminder, or the removal of one.
///
/// A time that cannot be read is not a reminder with a default — it is a
/// clear, which is the opposite of what was asked for. So an `at` that is
/// present and unparseable refuses the whole action rather than quietly
/// becoming the cancel branch.
AssistantAction? _remindAction(Map<Object?, Object?> decoded, String id) {
  final raw = decoded['at'];
  if (raw == null) {
    return AssistantAction(kind: AssistantActionKind.remind, noteId: id);
  }
  final text = _string(raw);
  if (text == null) return null;
  // Local time, deliberately. The prompt asks for `YYYY-MM-DDTHH:MM` with no
  // zone, and `DateTime.parse` reads that as local — which is what somebody
  // saying "nine on Friday" means. A model that sends a `Z` is taken at its
  // word and converted, because it said something specific.
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return AssistantAction(
    kind: AssistantActionKind.remind,
    noteId: id,
    at: parsed.isUtc ? parsed.toLocal() : parsed,
    repeat: NoteRepeat.fromWire(_string(decoded['repeat'])?.toLowerCase()),
  );
}

AssistantAction? _renameTagAction(Map<Object?, Object?> decoded) {
  final tag = _string(decoded['tag']);
  final name = _string(decoded['name']) ?? _string(decoded['text']);
  // Renaming a tag to what it is already called is not a change, and
  // renaming it to nothing is a tag nobody can see.
  if (tag == null || name == null) return null;
  if (tag.toLowerCase() == name.toLowerCase()) return null;
  return AssistantAction(
    kind: AssistantActionKind.renameTag,
    tagName: tag,
    text: name,
  );
}

/// A tag's colour, which must be a `#RRGGBB` this app can actually paint.
///
/// `default` clears it back to the shipped colour — the same thing the
/// picker's own reset does, and the only way to undo a colour by talking.
AssistantAction? _tagColorAction(Map<Object?, Object?> decoded) {
  final tag = _string(decoded['tag']);
  final color = _string(decoded['color']) ?? _string(decoded['value']);
  if (tag == null || color == null) return null;
  final normalised = color.toLowerCase() == 'default'
      ? null
      : _hexColor(color);
  if (normalised == null && color.toLowerCase() != 'default') return null;
  return AssistantAction(
    kind: AssistantActionKind.tagColor,
    tagName: tag,
    text: normalised,
  );
}

/// `#RRGGBB`, upper case, or null when it is not one.
///
/// Accepts a missing `#` because models drop it, and nothing else: a colour
/// is stored and later parsed by the theme, and "blue" stored in that slot
/// is a tag that renders as no colour at all with nothing to say why.
String? _hexColor(String value) {
  final body = value.startsWith('#') ? value.substring(1) : value;
  if (body.length != 6) return null;
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(body)) return null;
  return '#${body.toUpperCase()}';
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

/// A JSON boolean, or null when the field was absent or was something else.
///
/// Only a real boolean counts. `"pinned": "false"` is a model that wrote the
/// wrong type, and reading a non-empty string as true would turn it into the
/// opposite of what it asked for.
bool? _bool(Object? value) => value is bool ? value : null;

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
