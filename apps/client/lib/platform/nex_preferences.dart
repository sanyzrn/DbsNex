import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nex_core/nex_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_provider.dart';
import 'chat_history.dart';
import 'package:uuid/uuid.dart';

/// The actions a swipe edge can be bound to.
///
/// `none` is a real choice, not an absence: a user who wants one gesture and
/// not two needs a way to say so. ADR-022 originally fixed this at exactly two
/// and called the set deliberately closed; the set is open now, and adding to
/// it means adding an entry here and a case in the resolver — nothing else.
/// What one edge of a card does when it is swiped.
///
/// Open by construction (ADR-022), and it grew once the gesture stopped being
/// a pair: every one of these is something the note detail sheet could already
/// do, brought one gesture closer.
enum SwipeAction { none, delete, addTag, pin, remind, share, ask }

extension SwipeActionWire on SwipeAction {
  String get wireName => switch (this) {
    SwipeAction.none => 'none',
    SwipeAction.delete => 'delete',
    SwipeAction.addTag => 'add_tag',
    SwipeAction.pin => 'pin',
    SwipeAction.remind => 'remind',
    SwipeAction.share => 'share',
    SwipeAction.ask => 'ask',
  };

  static SwipeAction fromWire(String? value) => switch (value) {
    'none' => SwipeAction.none,
    'add_tag' => SwipeAction.addTag,
    'delete' => SwipeAction.delete,
    'pin' => SwipeAction.pin,
    'remind' => SwipeAction.remind,
    'share' => SwipeAction.share,
    'ask' => SwipeAction.ask,
    // An unknown stored value is not a reason to lose the gesture. It is
    // reachable in one direction only — a build that knew about an action this
    // one does not, which is a downgrade rather than an upgrade.
    _ => SwipeAction.delete,
  };
}

class NexPreferences extends ChangeNotifier {
  NexPreferences._(this._prefs, this._secureStorage);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  /// In-memory mirror of every provider's API key, hydrated once by [load]
  /// and kept in sync on every write.
  ///
  /// `configFor`/`aiProvider` are read synchronously from a dozen call
  /// sites — some inside `build()`, one in a field initialiser — so the
  /// secure-storage read that produces a key has to happen exactly once, up
  /// front, not on every read. Everything else a provider needs (base URL,
  /// model, which provider is active) is not a credential and stays in
  /// `_prefs`, read directly, the way it always was.
  final Map<String, String> _secureApiKeys = {};

  static const _kDeviceId = 'nex.device_id';
  static const _kSyncBaseUrl = 'sync.base_url';
  static const _kSyncBearerToken = 'sync.bearer_token';
  static const _kPendingFeedback = 'feedback.pending_message';

  static const _kOnboardingComplete = 'onboarding.complete';
  static const _kTourComplete = 'onboarding.tour_complete';

  static Future<NexPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateAiProviderStorage(prefs);
    // Nobody who already has a library gets walked through an introduction to
    // it. The store holding any key at all is exactly "this app has run
    // before": `load()` is the first thing bootstrap does, ahead of the device
    // id and every setting, so on a genuinely fresh install it is empty here.
    if (!prefs.containsKey(_kOnboardingComplete) &&
        prefs.getKeys().isNotEmpty) {
      await prefs.setBool(_kOnboardingComplete, true);
      // And the tour with it. Someone upgrading into this version has been
      // using these controls for months; pointing at them now would read as
      // the app having forgotten who they are.
      await prefs.setBool(_kTourComplete, true);
    }
    final preferences = NexPreferences._(prefs, const FlutterSecureStorage());
    await preferences._migrateAndHydrateApiKeys();
    return preferences;
  }

  /// Whether the first-run introduction has been through.
  ///
  /// The one preference that gates a whole screen rather than tuning one, so
  /// it is written exactly once, by the last page of that screen.
  bool get onboardingComplete => _prefs.getBool(_kOnboardingComplete) ?? false;

  Future<void> completeOnboarding() async {
    await _prefs.setBool(_kOnboardingComplete, true);
    notifyListeners();
  }

  /// Whether the terms for a downloadable model have been shown and agreed to.
  ///
  /// Keyed per model, not a single flag: accepting Gemma's terms says nothing
  /// about a different model under a different licence, and the app is
  /// expected to offer more than one eventually.
  ///
  /// Recorded because the licence requires the terms reach every recipient
  /// before distribution, and a record of that is what makes it verifiable
  /// rather than assumed — see 09-ai.md.
  bool acceptedModelLicense(String modelId) =>
      _prefs.getBool('ai.model.license.$modelId') ?? false;

  Future<void> acceptModelLicense(String modelId) async {
    await _prefs.setBool('ai.model.license.$modelId', true);
    notifyListeners();
  }

  /// Whether the walk-through over the timeline's own controls has been shown.
  ///
  /// Separate from [onboardingComplete] because they run at different moments
  /// and mean different things: onboarding asks four questions before anyone
  /// has seen the app, and this points at controls that only exist once the
  /// timeline is on screen.
  ///
  /// The same "this app has run before" rule applies as above — an existing
  /// install is not walked through a screen it has been using for months — so
  /// [load] marks it seen for anyone who already had preferences.
  bool get tourComplete => _prefs.getBool(_kTourComplete) ?? false;

  Future<void> completeTour() async {
    await _prefs.setBool(_kTourComplete, true);
    notifyListeners();
  }

  /// Moves each provider's key out of the plaintext slot [_migrateAiProviderStorage]
  /// left it in and into secure storage, then reads whatever is there —
  /// freshly migrated or already secure from an earlier launch — into
  /// [_secureApiKeys].
  ///
  /// A key was previously kept in `shared_preferences`: on Android that is an
  /// unencrypted XML file readable on a rooted device or through an ADB
  /// backup; on Windows, plaintext JSON. For a paid third-party credential
  /// that is a real cost to a user whose device is compromised, not a
  /// theoretical one.
  Future<void> _migrateAndHydrateApiKeys() async {
    for (final provider in AiProvider.values) {
      if (provider == AiProvider.none) continue;
      final key = 'ai.key.${provider.wireName}';
      final legacy = _prefs.getString(key);
      if (legacy != null && legacy.isNotEmpty) {
        await _secureStorage.write(key: key, value: legacy);
        await _prefs.remove(key);
      }
      final secured = await _secureStorage.read(key: key);
      if (secured != null) _secureApiKeys[provider.wireName] = secured;
    }
  }

  /// One-time move from the single `ai.key`/`ai.baseUrl`/`ai.model` slot to
  /// the per-provider keys `configFor` reads. Without it, switching to the
  /// namespaced scheme reset every already-configured provider's credentials
  /// back to empty on next launch.
  static Future<void> _migrateAiProviderStorage(SharedPreferences prefs) async {
    final oldKey = prefs.getString('ai.key');
    if (oldKey == null) return;
    final provider = AiProviderWire.fromWire(prefs.getString('ai.provider'));
    if (provider != AiProvider.none) {
      await prefs.setString('ai.key.${provider.wireName}', oldKey);
      final oldBaseUrl = prefs.getString('ai.baseUrl');
      if (oldBaseUrl != null) {
        await prefs.setString('ai.baseUrl.${provider.wireName}', oldBaseUrl);
      }
      final oldModel = prefs.getString('ai.model');
      if (oldModel != null) {
        await prefs.setString('ai.model.${provider.wireName}', oldModel);
      }
    }
    await prefs.remove('ai.key');
    await prefs.remove('ai.baseUrl');
    await prefs.remove('ai.model');
  }

  /// Stable, globally-unique device identity.
  ///
  /// Identity used to be derived from Platform.localHostname, which returns the
  /// constant "localhost" on Android and the renameable, non-unique machine
  /// name on Windows. The sync protocol treats device_id as the LWW tie-breaker
  /// and as the discriminator that decides whether tags are union-merged or
  /// replaced, so a shared identity silently destroyed tags.
  ///
  /// Generated once, persisted forever, never derived from the environment.
  Future<String> stableDeviceId() async {
    final existing = _prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = const Uuid().v4();
    await _prefs.setString(_kDeviceId, generated);
    return generated;
  }

  /// User-configured sync endpoint. Null until the device has been paired.
  ///
  /// There is deliberately no default: a hardcoded http://127.0.0.1:4000
  /// resolves to the device itself and is blocked as cleartext on Android 9+.
  String? get syncBaseUrl {
    final value = _prefs.getString(_kSyncBaseUrl);
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setSyncBaseUrl(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_kSyncBaseUrl);
    } else {
      await _prefs.setString(_kSyncBaseUrl, value);
    }
    notifyListeners();
  }

  /// Device token from `POST /auth/pair`. Null until the device is paired.
  ///
  /// Stored beside the endpoint because the sync API is no longer open: without
  /// it every push and pull is anonymous and comes back 401.
  String? get syncBearerToken {
    final value = _prefs.getString(_kSyncBearerToken);
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setSyncBearerToken(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_kSyncBearerToken);
    } else {
      await _prefs.setString(_kSyncBearerToken, value);
    }
    notifyListeners();
  }

  /// Feedback text that failed to send, held so it can be retried without the
  /// user re-typing it — see `FeedbackService.flushPending`.
  String? get pendingFeedback {
    final value = _prefs.getString(_kPendingFeedback);
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setPendingFeedback(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_kPendingFeedback);
    } else {
      await _prefs.setString(_kPendingFeedback, value);
    }
    notifyListeners();
  }

  SwipeAction get leadingAction =>
      SwipeActionWire.fromWire(_prefs.getString('swipe.leading') ?? 'add_tag');

  SwipeAction get trailingAction =>
      SwipeActionWire.fromWire(_prefs.getString('swipe.trailing') ?? 'delete');

  bool get comfortMode => _prefs.getBool('appearance.comfort') ?? false;

  /// The one accent colour a user actually picks — `#RRGGBB`, or null for
  /// the shipped default. The other three accent roles follow from it; see
  /// [NexAccentPalette].
  String? get accentSeed => _prefs.getString('appearance.accent_seed');

  /// A multiplier on top of the system's own text scale, not a replacement
  /// for it — someone who already runs a larger system font can still make
  /// Nex itself a little bigger or smaller on top of that. 1.0 is "as the
  /// device already asks for."
  double get uiScale => _prefs.getDouble('appearance.ui_scale') ?? 1.0;

  /// Whether Enter submits the note being typed on first capture, rather
  /// than starting a new line. Scoped to that one field on purpose — editing
  /// an existing note is a different moment, where a stray Enter should
  /// never end the session.
  bool get enterSubmitsCapture =>
      _prefs.getBool('capture.enter_submits') ?? true;

  bool get reduceMotion =>
      _prefs.getBool('accessibility.reduce_motion') ?? false;

  bool get haptics => _prefs.getBool('accessibility.haptics') ?? true;

  bool get cloudAiOptIn => _prefs.getBool('ai.cloud_opt_in') ?? false;

  /// What the app calls you, if you told it.
  ///
  /// Decoration and nothing else: it never leaves the device, is never sent
  /// with a sync or an AI request, and an empty value is stored as absent so
  /// callers only ever have to check for null.
  String? get displayName {
    final value = _prefs.getString('profile.name')?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// [displayName] cut to its first two words, for the places that render it
  /// inside a line of running text.
  ///
  /// Someone who types their full name gets it back in full on the profile
  /// row, where there is room for it, and gets "Saeed Karimi" in the timeline
  /// greeting, where a third and fourth word push the line onto a second row
  /// and knock the headline below it out of place.
  String? get shortDisplayName {
    final value = displayName;
    if (value == null) return null;
    final words = value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).join(' ');
  }

  Locale? get locale {
    final code = _prefs.getString('appearance.locale');
    return code == null || code == 'system' ? null : Locale(code);
  }

  ThemeMode get themeMode => switch (_prefs.getString('appearance.theme')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  AiCapabilities get aiCapabilities => AiCapabilities(
    transcription: _prefs.getBool('ai.transcription') ?? true,
    ocr: _prefs.getBool('ai.ocr') ?? true,
    tagSuggestions: _prefs.getBool('ai.tags') ?? true,
    semanticSearch: _prefs.getBool('ai.semantic') ?? true,
    summarization: _prefs.getBool('ai.summary') ?? true,
    relatedNotes: _prefs.getBool('ai.related') ?? true,
  );

  /// Personal-assistant tier (09-ai.md — Free vs. Paid Boundary, ADR-030).
  /// No payment processor exists yet, so this defaults to `free` and nothing
  /// in the app currently offers a way to change it — it exists so the
  /// gating hook (`GatedToolExecutor`) has somewhere real to read from.
  AiEntitlement get aiEntitlement => AiEntitlement.values.firstWhere(
    (e) => e.name == _prefs.getString('ai.entitlement'),
    orElse: () => AiEntitlement.free,
  );

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }

  Future<void> setComfortMode(bool value) =>
      _setBool('appearance.comfort', value);

  /// Null clears the setting back to the shipped default rather than storing
  /// an empty string — [accentSeed] only ever has to check for null.
  Future<void> setAccentSeed(String? value) async {
    if (value == null) {
      await _prefs.remove('appearance.accent_seed');
    } else {
      await _prefs.setString('appearance.accent_seed', value);
    }
    notifyListeners();
  }

  Future<void> setUiScale(double value) async {
    await _prefs.setDouble('appearance.ui_scale', value);
    notifyListeners();
  }

  Future<void> setEnterSubmitsCapture(bool value) =>
      _setBool('capture.enter_submits', value);

  Future<void> setReduceMotion(bool value) =>
      _setBool('accessibility.reduce_motion', value);

  Future<void> setHaptics(bool value) =>
      _setBool('accessibility.haptics', value);

  Future<void> setCloudAiOptIn(bool value) =>
      _setBool('ai.cloud_opt_in', value);

  Future<void> setAiEntitlement(AiEntitlement value) async {
    await _prefs.setString('ai.entitlement', value.name);
    notifyListeners();
  }

  Future<void> setDisplayName(String? value) async {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      await _prefs.remove('profile.name');
    } else {
      // A name longer than this is not a name, and the app bar has to hold it.
      await _prefs.setString(
        'profile.name',
        trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed,
      );
    }
    notifyListeners();
  }

  Future<void> setLocale(String value) async {
    await _prefs.setString('appearance.locale', value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    await _prefs.setString('appearance.theme', value.name);
    notifyListeners();
  }

  Future<void> setAiCapabilities(AiCapabilities value) async {
    await _prefs.setBool('ai.transcription', value.transcription);
    await _prefs.setBool('ai.ocr', value.ocr);
    await _prefs.setBool('ai.tags', value.tagSuggestions);
    await _prefs.setBool('ai.semantic', value.semanticSearch);
    await _prefs.setBool('ai.summary', value.summarization);
    await _prefs.setBool('ai.related', value.relatedNotes);
    notifyListeners();
  }

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

  /* ----------------------------------------------------------------- update */

  /// Whether the app looks for a new release on its own.
  ///
  /// On by default. Nex ships outside any store, so without this a user only
  /// learns about a release by going to look for one.
  bool get autoUpdateCheck => _prefs.getBool('update.auto') ?? true;

  Future<void> setAutoUpdateCheck(bool value) async {
    await _prefs.setBool('update.auto', value);
    notifyListeners();
  }

  DateTime? get lastUpdateCheck {
    final millis = _prefs.getInt('update.lastCheck');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> setLastUpdateCheck(DateTime value) async {
    await _prefs.setInt('update.lastCheck', value.millisecondsSinceEpoch);
    // Deliberately silent: the timestamp is bookkeeping, and rebuilding the
    // whole settings tree because a background check finished is noise.
  }

  /* ------------------------------------------------------------ AI provider */

  /// The master switch for everything in the intelligence layer.
  ///
  /// Off until the user turns it on and accepts what that means. The product
  /// promise is that Nex works fully offline; the intelligence layer is the one
  /// part that can send a note somewhere else, so it does not start enabled and
  /// the individual capability switches do nothing while this is off.
  bool get aiEnabled => _prefs.getBool('ai.enabled') ?? false;

  Future<void> setAiEnabled(bool value) async {
    await _prefs.setBool('ai.enabled', value);
    notifyListeners();
  }

  /// The capabilities actually in force: all off while the master switch is.
  AiCapabilities get effectiveAiCapabilities =>
      aiEnabled ? aiCapabilities : AiCapabilities.allOff;

  // The key/baseUrl/model are namespaced per provider rather than kept in one
  // shared slot: a single slot meant switching from, say, Claude to OpenAI
  // left Claude's key sitting in the OpenAI field, since there was only ever
  // one to overwrite. Each provider now keeps its own, so switching back to
  // one configured earlier restores what was saved for it.
  //
  // Only the key lives in secure storage — see [_secureApiKeys]. baseUrl and
  // model are not credentials, and keeping them in plain `_prefs` is what
  // lets every other getter here stay a synchronous read against one store.
  AiProviderConfig get aiProvider =>
      configFor(AiProviderWire.fromWire(_prefs.getString('ai.provider')));

  /// What is stored for [provider] specifically, whether or not it is the
  /// active one — how the provider screen fills its fields in when the user
  /// is only looking at (not yet saving) a different provider.
  AiProviderConfig configFor(AiProvider provider) => AiProviderConfig(
    provider: provider,
    apiKey: _secureApiKeys[provider.wireName] ?? '',
    baseUrl: _prefs.getString('ai.baseUrl.${provider.wireName}') ?? '',
    model: _prefs.getString('ai.model.${provider.wireName}') ?? '',
  );

  /// Which language the model answers in — independent of [locale].
  ///
  /// Not folded into [AiProviderConfig]: that is per-provider storage, and
  /// this is one global choice. Putting it there would have meant writing the
  /// same value under every provider's namespace and picking a winner when
  /// they disagreed.
  AiOutputLanguage get aiOutputLanguage =>
      AiOutputLanguage.fromWire(_prefs.getString('ai.outputLanguage'));

  Future<void> setAiOutputLanguage(AiOutputLanguage value) async {
    await _prefs.setString('ai.outputLanguage', value.wireName);
    // The two cached AI strings on the timeline were written in the old
    // language; leaving them would show the setting as having done nothing
    // until tomorrow.
    await _prefs.remove('ai.daySummary.text');
    await _prefs.remove('ai.daySummary.date');
    await _prefs.remove('ai.headline.text');
    await _prefs.remove('ai.headline.date');
    notifyListeners();
  }

  Future<void> setAiProvider(AiProviderConfig config) async {
    final wireName = config.provider.wireName;
    final key = 'ai.key.$wireName';
    await _prefs.setString('ai.provider', wireName);
    if (config.apiKey.isEmpty) {
      await _secureStorage.delete(key: key);
      _secureApiKeys.remove(wireName);
    } else {
      await _secureStorage.write(key: key, value: config.apiKey);
      _secureApiKeys[wireName] = config.apiKey;
    }
    await _prefs.setString('ai.baseUrl.$wireName', config.baseUrl);
    await _prefs.setString('ai.model.$wireName', config.model);
    notifyListeners();
  }

  /* ------------------------------------------------------------- Assistant */

  /// Saved assistant conversations.
  ///
  /// Reached through here rather than constructed alongside this because it
  /// is backed by the same preference store and needs nothing else — hanging
  /// it off the object that already owns that store is one dependency to
  /// thread through the widget tree instead of two. It is still its own
  /// [ChangeNotifier]: the conversation list rebuilds when a thread is saved
  /// or deleted, and nothing else in the app should rebuild for that.
  late final ChatHistory chatHistory = ChatHistory(_prefs);

  /// How far the assistant may wander from the plainest answer.
  AiCreativity get aiCreativity =>
      AiCreativity.fromWire(_prefs.getString('ai.creativity'));

  Future<void> setAiCreativity(AiCreativity value) async {
    await _prefs.setString('ai.creativity', value.wireName);
    notifyListeners();
  }

  /// How long its answers are allowed to be.
  AiAnswerLength get aiAnswerLength =>
      AiAnswerLength.fromWire(_prefs.getString('ai.answerLength'));

  Future<void> setAiAnswerLength(AiAnswerLength value) async {
    await _prefs.setString('ai.answerLength', value.wireName);
    notifyListeners();
  }

  /// Whether the assistant stays inside the user's notes and this app.
  ///
  /// Defaults to true, and the default is the point: this is a notes app's
  /// assistant, and the first time someone opens it they should find
  /// something that knows their notes rather than a general chatbot that
  /// happens to live here.
  bool get aiNotesOnly => _prefs.getBool('ai.notesOnly') ?? true;

  Future<void> setAiNotesOnly(bool value) async {
    await _prefs.setBool('ai.notesOnly', value);
    notifyListeners();
  }

  /// A standing instruction for the assistant, in the user's own words.
  ///
  /// Empty by default and empty when cleared — never null, so every caller
  /// can trim and test it the same way. Capped at [aiInstructionMaxLength]
  /// because it is prepended to every single request: a long one is paid for
  /// in tokens on each message, and the models this app is usually pointed at
  /// have small context windows to spend.
  ///
  /// Stays on the device apart from the requests it shapes — it is not synced
  /// and not part of a backup's settings, the same as the API key beside it.
  static const aiInstructionMaxLength = 300;

  String get aiInstruction => _prefs.getString('ai.instruction') ?? '';

  Future<void> setAiInstruction(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove('ai.instruction');
    } else {
      await _prefs.setString(
        'ai.instruction',
        trimmed.length <= aiInstructionMaxLength
            ? trimmed
            : trimmed.substring(0, aiInstructionMaxLength),
      );
    }
    notifyListeners();
  }

  /// How many recent notes are sent with each question.
  ///
  /// A privacy setting before it is a quality one. Every one of these leaves
  /// the device and reaches whichever provider is configured, so the amount
  /// is the user's to choose — and zero is a real choice, not a broken one:
  /// the assistant still answers about the app itself.
  int get aiNotesContextCount {
    final stored = _prefs.getInt('ai.notesContext') ?? 20;
    return aiNotesContextChoices.contains(stored) ? stored : 20;
  }

  Future<void> setAiNotesContextCount(int value) async {
    await _prefs.setInt('ai.notesContext', value);
    notifyListeners();
  }

  /// The offered sizes.
  ///
  /// Bounded rather than free-typed, and the ceiling is a real one. Reading
  /// *everything* sounds like the strictly better answer and is not: the model
  /// has to read the whole prompt before it writes a word, and on the
  /// on-device model that cost is the visible one — the same lag a long
  /// translation has. It grows with every note, on every question, including
  /// the short ones.
  ///
  /// Attention does not improve with length either. Past a few dozen notes a
  /// model is likelier to answer from the wrong one, not the right one.
  ///
  /// So the big sizes are offered and labelled as slow rather than withheld.
  /// The answer that actually scales is to search first and send only what
  /// matches, which is its own piece of work and not this setting.
  static const aiNotesContextChoices = [0, 10, 20, 50, 100, 200];

  /// Sizes worth warning about before they are chosen.
  static bool aiNotesContextIsSlow(int count) => count >= 100;

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

  /* ------------------------------------------------- Timeline date groups */

  /// Date groups the timeline is showing folded away.
  ///
  /// Stored by key rather than by index: "Last week" is a different set of
  /// notes tomorrow than it is today, and an index would fold whichever group
  /// happened to land in that position.
  Set<String> get collapsedTimelineGroups =>
      (_prefs.getStringList('timeline.collapsed') ?? const []).toSet();

  Future<void> setCollapsedTimelineGroups(Set<String> keys) async {
    await _prefs.setStringList('timeline.collapsed', keys.toList()..sort());
    notifyListeners();
  }

  List<String> get savedSearches =>
      _prefs.getStringList('search.saved') ?? const [];

  static const maxSavedSearches = 12;

  Future<void> saveSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final updated = <String>[
      trimmed,
      for (final saved in savedSearches)
        if (saved != trimmed) saved,
    ];
    await _prefs.setStringList(
      'search.saved',
      updated.take(maxSavedSearches).toList(),
    );
    notifyListeners();
  }

  Future<void> removeSavedSearch(String query) async {
    final remaining = [
      for (final saved in savedSearches)
        if (saved != query) saved,
    ];
    await _prefs.setStringList('search.saved', remaining);
    notifyListeners();
  }

  /* --------------------------------------------------------- AI day summary */

  /// The timeline's daily AI recap, cached against the date it was written
  /// for — see `_TimelineScreenState._loadAiSummary`. Generating it is a real
  /// network call, so a cold launch that already has today's text shows it
  /// immediately instead of re-asking the provider on every open.
  ///
  /// No [notifyListeners] here: this cache is read by the one screen that
  /// writes it, on its own schedule, not something the rest of the app
  /// reacts to.
  String? get aiDaySummaryText => _prefs.getString('ai.daySummary.text');
  String? get aiDaySummaryDate => _prefs.getString('ai.daySummary.date');

  Future<void> setAiDaySummary({
    required String text,
    required String dateKey,
  }) async {
    await _prefs.setString('ai.daySummary.text', text);
    await _prefs.setString('ai.daySummary.date', dateKey);
  }

  /// The key a recap is filed under: the local calendar day it describes.
  static String daySummaryDateKey(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  /// The recap only if it is today's.
  ///
  /// The daily notification is scheduled while the app is open and arrives
  /// while it is not, so whatever it says was written down beforehand. That
  /// makes the stale case worth spelling out: a summary of yesterday
  /// delivered as this morning's is worse than the app admitting it has
  /// nothing yet.
  String? get todaysRecap {
    final text = aiDaySummaryText;
    if (text == null || text.isEmpty) return null;
    return aiDaySummaryDate == daySummaryDateKey(DateTime.now()) ? text : null;
  }

  /// The timeline's one-line headline, cached the same way and for the same
  /// reason as the recap above. Tapping the line asks for a new one, which is
  /// what makes this a cache rather than a daily lock.
  String? get aiHeadlineText => _prefs.getString('ai.headline.text');
  String? get aiHeadlineDate => _prefs.getString('ai.headline.date');

  /// Which language the cached line was written in.
  ///
  /// The headline is joined onto the greeting as one sentence, and the
  /// greeting follows the script of the user's own name — so a name changed
  /// from Persian to Latin (or back) has to throw the cached line away, not
  /// glue yesterday's Persian half onto today's English greeting.
  String? get aiHeadlineLang => _prefs.getString('ai.headline.lang');

  Future<void> setAiHeadline({
    required String text,
    required String dateKey,
    String? lang,
  }) async {
    await _prefs.setString('ai.headline.text', text);
    await _prefs.setString('ai.headline.date', dateKey);
    if (lang == null) {
      await _prefs.remove('ai.headline.lang');
    } else {
      await _prefs.setString('ai.headline.lang', lang);
    }
  }
}
