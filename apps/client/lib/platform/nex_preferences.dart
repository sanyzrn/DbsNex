import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_provider.dart';
import 'package:uuid/uuid.dart';

/// The actions a swipe edge can be bound to.
///
/// `none` is a real choice, not an absence: a user who wants one gesture and
/// not two needs a way to say so. ADR-022 originally fixed this at exactly two
/// and called the set deliberately closed; the set is open now, and adding to
/// it means adding an entry here and a case in the resolver — nothing else.
enum SwipeAction { none, delete, addTag }

extension SwipeActionWire on SwipeAction {
  String get wireName => switch (this) {
    SwipeAction.none => 'none',
    SwipeAction.delete => 'delete',
    SwipeAction.addTag => 'add_tag',
  };

  static SwipeAction fromWire(String? value) => switch (value) {
    'none' => SwipeAction.none,
    'add_tag' => SwipeAction.addTag,
    'delete' => SwipeAction.delete,
    // An unknown stored value is not a reason to lose the gesture.
    _ => SwipeAction.delete,
  };
}

class NexPreferences extends ChangeNotifier {
  NexPreferences._(this._prefs);

  final SharedPreferences _prefs;

  static const _kDeviceId = 'nex.device_id';
  static const _kSyncBaseUrl = 'sync.base_url';
  static const _kSyncBearerToken = 'sync.bearer_token';

  static Future<NexPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateAiProviderStorage(prefs);
    return NexPreferences._(prefs);
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

  SwipeAction get leadingAction =>
      SwipeActionWire.fromWire(_prefs.getString('swipe.leading') ?? 'add_tag');

  SwipeAction get trailingAction =>
      SwipeActionWire.fromWire(_prefs.getString('swipe.trailing') ?? 'delete');

  bool get comfortMode => _prefs.getBool('appearance.comfort') ?? false;

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

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }

  Future<void> setComfortMode(bool value) =>
      _setBool('appearance.comfort', value);

  Future<void> setReduceMotion(bool value) =>
      _setBool('accessibility.reduce_motion', value);

  Future<void> setHaptics(bool value) =>
      _setBool('accessibility.haptics', value);

  Future<void> setCloudAiOptIn(bool value) =>
      _setBool('ai.cloud_opt_in', value);

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

  // Stored in shared_preferences, which is not encrypted. On Android the file
  // lives in the app's private data directory, so it is out of reach of other
  // apps but readable on a rooted or backed-up device. Documented rather than
  // hidden — the alternative is a secure-storage plugin, and pretending a
  // plaintext preference is a secret would be worse than saying so.
  //
  // The key/baseUrl/model are namespaced per provider rather than kept in one
  // shared slot: a single slot meant switching from, say, Claude to OpenAI
  // left Claude's key sitting in the OpenAI field, since there was only ever
  // one to overwrite. Each provider now keeps its own, so switching back to
  // one configured earlier restores what was saved for it.
  AiProviderConfig get aiProvider =>
      configFor(AiProviderWire.fromWire(_prefs.getString('ai.provider')));

  /// What is stored for [provider] specifically, whether or not it is the
  /// active one — how the provider screen fills its fields in when the user
  /// is only looking at (not yet saving) a different provider.
  AiProviderConfig configFor(AiProvider provider) => AiProviderConfig(
    provider: provider,
    apiKey: _prefs.getString('ai.key.${provider.wireName}') ?? '',
    baseUrl: _prefs.getString('ai.baseUrl.${provider.wireName}') ?? '',
    model: _prefs.getString('ai.model.${provider.wireName}') ?? '',
  );

  Future<void> setAiProvider(AiProviderConfig config) async {
    await _prefs.setString('ai.provider', config.provider.wireName);
    await _prefs.setString('ai.key.${config.provider.wireName}', config.apiKey);
    await _prefs.setString(
      'ai.baseUrl.${config.provider.wireName}',
      config.baseUrl,
    );
    await _prefs.setString(
      'ai.model.${config.provider.wireName}',
      config.model,
    );
    notifyListeners();
  }
}
