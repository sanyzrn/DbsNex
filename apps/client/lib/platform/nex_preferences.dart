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

  static Future<NexPreferences> load() async =>
      NexPreferences._(await SharedPreferences.getInstance());

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

  bool get reduceMotion => _prefs.getBool('accessibility.reduce_motion') ?? false;

  bool get haptics => _prefs.getBool('accessibility.haptics') ?? true;

  bool get quietAnniversary =>
      _prefs.getBool('timeline.quiet_anniversary') ?? true;

  bool get cloudAiOptIn => _prefs.getBool('ai.cloud_opt_in') ?? false;

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

  Future<void> setHaptics(bool value) => _setBool('accessibility.haptics', value);

  Future<void> setQuietAnniversary(bool value) =>
      _setBool('timeline.quiet_anniversary', value);

  Future<void> setCloudAiOptIn(bool value) =>
      _setBool('ai.cloud_opt_in', value);

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

  Future<void> swapSwipeMapping() async {
    final old = leadingAction;
    await _prefs.setString('swipe.leading', trailingAction.wireName);
    await _prefs.setString('swipe.trailing', old.wireName);
    notifyListeners();
  }

  /// Assigns one edge directly.
  ///
  /// The two edges must always differ, so choosing an action for one edge
  /// hands the other edge whatever it displaced. With exactly two actions that
  /// is indistinguishable from a swap; the point is that the *control* is a
  /// choice per edge, which is what a third action would need — and adding one
  /// then means extending [SwipeAction] and this method, not rewriting the UI.
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

  /* ------------------------------------------------------------ AI provider */

  // Stored in shared_preferences, which is not encrypted. On Android the file
  // lives in the app's private data directory, so it is out of reach of other
  // apps but readable on a rooted or backed-up device. Documented rather than
  // hidden — the alternative is a secure-storage plugin, and pretending a
  // plaintext preference is a secret would be worse than saying so.
  AiProviderConfig get aiProvider => AiProviderConfig(
        provider: AiProviderWire.fromWire(_prefs.getString('ai.provider')),
        apiKey: _prefs.getString('ai.key') ?? '',
        baseUrl: _prefs.getString('ai.baseUrl') ?? '',
        model: _prefs.getString('ai.model') ?? '',
      );

  Future<void> setAiProvider(AiProviderConfig config) async {
    await _prefs.setString('ai.provider', config.provider.wireName);
    await _prefs.setString('ai.key', config.apiKey);
    await _prefs.setString('ai.baseUrl', config.baseUrl);
    await _prefs.setString('ai.model', config.model);
    notifyListeners();
  }
}
