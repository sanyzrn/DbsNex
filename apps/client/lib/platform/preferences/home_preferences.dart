part of '../nex_preferences.dart';

/// The home screen: what it shows, the swipe and hold actions, the widget, the
/// nudge.
mixin _HomePreferences on _PreferencesStore {
  SwipeAction get leadingAction =>
      SwipeActionWire.fromWire(_prefs.getString('swipe.leading') ?? 'add_tag');

  SwipeAction get trailingAction =>
      SwipeActionWire.fromWire(_prefs.getString('swipe.trailing') ?? 'delete');

  /// Which note types the home-screen widget may show, by wire name.
  ///
  /// Empty means all of them, which is both the default and the honest
  /// encoding: a widget filtered to nothing would be a widget that is
  /// permanently empty, so "none selected" can only sensibly mean "no filter".
  Set<String> get widgetTypes =>
      (_prefs.getStringList('widget.types') ?? const <String>[]).toSet();

  /// Whether the widget floats pinned notes to the top, the way the timeline
  /// does.
  ///
  /// On by default, because the widget's promise is "the top of your
  /// timeline" and the timeline pins. Off is for someone who pins inside the
  /// app for a different reason than they use the widget for: pinned notes
  /// then sit wherever their own date puts them, as though they were not
  /// pinned at all, and the widget is purely the most recent thing that
  /// happened.
  bool get widgetPinnedFirst => _prefs.getBool('widget.pinned_first') ?? true;

  /// Whether the widget keeps its notes while the library is locked.
  ///
  /// Off by default, and off is the strict reading: the snapshot empties the
  /// moment the lock closes, so a phone lying on a table shows the widget's
  /// empty state rather than the top of someone's timeline.
  ///
  /// It is a choice rather than a rule because the honest answer depends on
  /// the phone. A lock set to close after an hour is protecting against
  /// someone picking the phone up later, not against the person holding it —
  /// and for them a widget that is blank whenever the lock happens to be
  /// closed is a widget that is usually blank. Whoever turned the lock on is
  /// the one who knows which of those they meant.
  bool get widgetShowWhenLocked =>
      _prefs.getBool('widget.show_when_locked') ?? false;

  /// Which tags the widget is limited to, as id to name. Empty is the whole
  /// timeline.
  ///
  /// A set rather than one tag, because one tag is not how anybody files:
  /// somebody who keeps Work and Errands wants both on the home screen and
  /// neither of the other six. The names ride along so the settings row can
  /// say which tags without a database read on every rebuild — a tag renamed
  /// elsewhere leaves this stale until the screen is opened again, which is a
  /// cosmetic cost paid to keep a synchronous getter synchronous.
  Map<String, String> get widgetTags {
    final raw = _prefs.getString('widget.tags');
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
      };
    } catch (_) {
      return const {};
    }
  }

  Set<String> get widgetTagIds => widgetTags.keys.toSet();

  /* --------------------------------------------------- Home screen layout */

  /// Which of the four things above the notes the home screen is showing.
  ///
  /// All four are on by default, and every one of them is something the app
  /// decided to put there rather than something the reader asked for: a
  /// greeting, a generated summary, a search field and a row of tags, on a
  /// screen whose subject is the notes underneath them. Someone who wants the
  /// notes and nothing else should be able to have that without the app
  /// arguing.
  ///
  /// Turning the search field off does not take search away — the app bar
  /// grows the icon back, which is where it lived before the field became
  /// permanent.
  bool get showGreeting => _prefs.getBool('home.greeting') ?? true;

  bool get showDaySummary => _prefs.getBool('home.day_summary') ?? true;

  bool get showSearchField => _prefs.getBool('home.search') ?? true;

  bool get showTagRow => _prefs.getBool('home.tags') ?? true;

  Future<void> setShowGreeting(bool value) => _setHomePart('greeting', value);

  Future<void> setShowDaySummary(bool value) =>
      _setHomePart('day_summary', value);

  Future<void> setShowSearchField(bool value) => _setHomePart('search', value);

  Future<void> setShowTagRow(bool value) => _setHomePart('tags', value);

  Future<void> _setHomePart(String key, bool value) async {
    await _prefs.setBool('home.$key', value);
    notifyListeners();
  }

  Future<void> setWidgetTypes(Set<String> value) async {
    await _prefs.setStringList('widget.types', value.toList()..sort());
    notifyListeners();
  }

  Future<void> setWidgetPinnedFirst(bool value) async {
    await _prefs.setBool('widget.pinned_first', value);
    notifyListeners();
  }

  Future<void> setWidgetShowWhenLocked(bool value) async {
    await _prefs.setBool('widget.show_when_locked', value);
    notifyListeners();
  }

  Future<void> setWidgetTags(Map<String, String> value) async {
    if (value.isEmpty) {
      await _prefs.remove('widget.tags');
    } else {
      await _prefs.setString('widget.tags', jsonEncode(value));
    }
    notifyListeners();
  }

  /// The silent quick-capture row in the notification shade (W5.2). Off by
  /// default: something that stays in the shade is opted into.
  bool get quickCaptureNotification =>
      _prefs.getBool('capture.quick_notification') ?? false;

  Future<void> setQuickCaptureNotification(bool value) =>
      _setBool('capture.quick_notification', value);

  /// Whether a capture that clearly continues something offers a thread
  /// (W5.3). Off until switched on in Settings → Capture: an offer after a
  /// capture is a question at the moment Nex promises to ask none.
  bool get threadSuggestions =>
      _prefs.getBool('capture.thread_suggestions') ?? false;

  Future<void> setThreadSuggestions(bool value) =>
      _setBool('capture.thread_suggestions', value);

  /// Assigns one edge, and only that edge.
  ///
  /// The edges are independent: setting one no longer displaces the other, so
  /// both may hold the same action, or none at all. Coupling them made the
  /// control a swap button wearing a menu's clothes.
  Future<void> setSwipeAction({
    required bool isLeading,
    required SwipeAction action,
  }) async {
    await _prefs.setString(
      isLeading ? 'swipe.leading' : 'swipe.trailing',
      action.wireName,
    );
    notifyListeners();
  }

  SwipeAction actionFor({required bool isLeading}) =>
      isLeading ? leadingAction : trailingAction;

  /// What the daily brief is — see [NexBriefStyle].
  ///
  /// Default is the style the card has always had, so an upgrade changes
  /// nothing for anyone who was happy with it. The one that asks nothing of a
  /// provider is a choice people make deliberately, not one they should be
  /// moved to behind their backs.
  /// What a note's hold menu offers, in menu order. Unset means the default
  /// five; an unknown name (from a newer build's backup) is skipped.
  List<NexHoldAction> get holdMenuActions {
    final stored = _prefs.getStringList('hold_menu.actions');
    if (stored == null) return NexHoldAction.defaults;
    final chosen = {
      for (final name in stored)
        if (NexHoldAction.fromWire(name) case final action?) action,
    };
    return [
      for (final action in NexHoldAction.values)
        if (chosen.contains(action)) action,
    ];
  }

  Future<void> setHoldMenuActions(Iterable<NexHoldAction> actions) async {
    await _prefs.setStringList('hold_menu.actions', [
      for (final action in actions) action.name,
    ]);
    notifyListeners();
  }

  /* --------------------------------------------------------- Saved searches */

  /// Searches the user asked to keep, newest first.
  ///
  /// Plain strings, because that is exactly what a search is now that `tag:`
  /// and `type:` are part of the box: one line captures the terms and the
  /// filters together, survives a tag being renamed as gracefully as anything
  /// could, and needs no schema.
  /* ------------------------------------------------------- Daily nudge */

  /// Whether Nex sends one notification a day.
  ///
  /// Off by default. A notes app that starts notifying without being asked is
  /// one people turn notifications off for entirely, which costs the reminders
  /// they actually set.
  bool get dailyNudge => _prefs.getBool('nudge.on') ?? false;

  Future<void> setDailyNudge(bool value) async {
    await _prefs.setBool('nudge.on', value);
    notifyListeners();
  }

  /// When it arrives, as minutes past midnight. Nine in the morning until
  /// someone says otherwise.
  int get dailyNudgeMinutes => _prefs.getInt('nudge.at') ?? 9 * 60;

  Future<void> setDailyNudgeMinutes(int value) async {
    await _prefs.setInt('nudge.at', value.clamp(0, 24 * 60 - 1));
    notifyListeners();
  }
}
