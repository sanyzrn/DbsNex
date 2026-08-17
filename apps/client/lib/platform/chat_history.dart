import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved conversation with the assistant.
@immutable
class ChatThread {
  const ChatThread({
    required this.id,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  /// What the list shows for this thread: the first thing the user asked.
  ///
  /// Not a generated title. Naming a conversation would mean a second model
  /// call for every thread, paid for and waited on, to produce something the
  /// opening question already says — and on the small models this app is
  /// usually pointed at, says better.
  String get title {
    for (final message in messages) {
      if (message.role == ChatRole.user && message.content.trim().isNotEmpty) {
        return message.content.trim();
      }
    }
    return '';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': updatedAt.toUtc().toIso8601String(),
    'm': [
      for (final message in messages)
        {
          'r': message.role == ChatRole.assistant ? 'a' : 'u',
          'c': message.content,
        },
    ],
  };

  /// Returns null for anything that does not decode cleanly.
  ///
  /// A thread is a convenience, never data the user would miss the way they
  /// would miss a note — so one corrupt entry drops itself rather than
  /// throwing and taking the whole history with it.
  static ChatThread? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final at = raw['at'];
    final messages = raw['m'];
    if (id is! String || at is! String || messages is! List) return null;
    final when = DateTime.tryParse(at);
    if (when == null) return null;
    final turns = <ChatMessage>[];
    for (final entry in messages) {
      if (entry is! Map) continue;
      final content = entry['c'];
      if (content is! String) continue;
      turns.add(
        ChatMessage(
          role: entry['r'] == 'a' ? ChatRole.assistant : ChatRole.user,
          content: content,
        ),
      );
    }
    if (turns.isEmpty) return null;
    return ChatThread(id: id, updatedAt: when, messages: turns);
  }
}

/// Every conversation the user has had with the assistant, on this device.
///
/// Stored in preferences rather than in the notes database on purpose. A
/// conversation is not a note: it does not sync, does not appear in the
/// timeline, is not searched by FTS and is not exported — and putting it in
/// the notes table would have made it all four by default. It is also the
/// only store in the app that is deliberately lossy, capped at
/// [maxThreads] so a year of asking questions cannot grow without limit.
///
/// Nothing here leaves the device. The threads are replayed into the
/// provider only as the running context of a conversation the user has
/// reopened, exactly as the live conversation is.
class ChatHistory extends ChangeNotifier {
  ChatHistory(this._prefs);

  static const _key = 'ai.chatThreads';

  /// Deliberately small. This is a scrollback, not an archive: past a couple
  /// of dozen, nobody is finding an old conversation by scrolling, and the
  /// preference store is the wrong place to hold a transcript that large.
  static const maxThreads = 30;

  /// Per thread. A conversation this long has usually stopped being one.
  static const maxMessagesPerThread = 60;

  final SharedPreferences _prefs;

  List<ChatThread>? _cache;

  /// Newest first.
  List<ChatThread> get threads {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return _cache = const [];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return _cache = const [];
    }
    if (decoded is! List) return _cache = const [];
    final threads = <ChatThread>[
      for (final entry in decoded)
        if (ChatThread.fromJson(entry) case final thread?) thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _cache = List.unmodifiable(threads);
  }

  /// Writes [messages] as thread [id], replacing what was stored for it.
  ///
  /// Called after every exchange rather than when the sheet closes: a sheet
  /// is dismissed by swiping it away, which is not a moment anything is
  /// guaranteed to run in, and a conversation lost because the app was killed
  /// mid-answer is exactly the kind of thing this feature exists to stop.
  Future<void> save(String id, List<ChatMessage> messages) async {
    final kept = [
      for (final message in messages)
        if (message.content.trim().isNotEmpty) message,
    ];
    if (kept.isEmpty) return;
    final trimmed = kept.length > maxMessagesPerThread
        // From the end: the recent turns are the conversation, the opening
        // ones are its history. Except the very first user turn, which is
        // what the list shows as the thread's name.
        ? [kept.first, ...kept.sublist(kept.length - maxMessagesPerThread + 1)]
        : kept;
    final updated = <ChatThread>[
      ChatThread(id: id, updatedAt: DateTime.now(), messages: trimmed),
      for (final thread in threads)
        if (thread.id != id) thread,
    ];
    await _write(updated.take(maxThreads).toList());
  }

  Future<void> remove(String id) async {
    final remaining = [
      for (final thread in threads)
        if (thread.id != id) thread,
    ];
    if (remaining.length == threads.length) return;
    await _write(remaining);
  }

  Future<void> clear() => _write(const []);

  Future<void> _write(List<ChatThread> threads) async {
    _cache = List.unmodifiable(threads);
    if (threads.isEmpty) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(
        _key,
        jsonEncode([for (final thread in threads) thread.toJson()]),
      );
    }
    notifyListeners();
  }
}
