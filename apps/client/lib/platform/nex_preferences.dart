import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'package:nex_ai/cloud.dart';
import 'chat_history.dart';
import 'editor_drafts.dart';
import 'hold_menu.dart';
import 'vault_store.dart';
import 'package:uuid/uuid.dart';

part 'preferences/ai_preferences.dart';
part 'preferences/appearance_preferences.dart';
part 'preferences/backup_folder_preferences.dart';
part 'preferences/brief_preferences.dart';
part 'preferences/home_preferences.dart';
part 'preferences/library_preferences.dart';
part 'preferences/profile_preferences.dart';
part 'preferences/security_preferences.dart';
part 'preferences/service_preferences.dart';

/// When the app lock puts itself back on.
///
/// The lock used to re-arm the instant the app left the screen, which is the
/// safe default and, for someone switching to a browser to copy a link and
/// coming straight back, five fingerprints a minute. These are the three
/// answers that actually differ: at once, after a while, or never on its own.
enum AppLockTiming { immediately, after, manual }

extension AppLockTimingWire on AppLockTiming {
  String get wireName => name;

  static AppLockTiming fromWire(String? value) =>
      AppLockTiming.values.firstWhere(
        (timing) => timing.name == value,
        // The behaviour that shipped, for a device that has never seen this
        // setting: a lock nobody configured should be the strict one.
        orElse: () => AppLockTiming.immediately,
      );
}

/// How many colours a picker remembers between visits.
///
/// Eight is one row on a phone. A history that wraps to a second row stops
/// being a history and becomes a palette, which is what the shipped swatches
/// already are.
const nexRecentColorLimit = 8;

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

/// Why a copy into the backup folder did not land (W1.6).
enum NexBackupFolderFailure {
  /// The recovery code is not in secure storage.
  code,

  /// Nex no longer has access to the folder.
  access,

  /// The backup itself could not be made.
  backup,

  /// The folder's app refused the file.
  write,
}

/// What every preference domain reads and writes through.
///
/// [NexPreferences] is one object to its callers; its members live in one
/// mixin per domain under `preferences/` (W4.2), each on this base.
abstract class _PreferencesStore extends ChangeNotifier {
  _PreferencesStore(this._prefs, this._secureStorage);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  EditorDrafts? editorDrafts;

  DateTime? _millis(String key) {
    final ms = _prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

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
  bool secureStorageUnavailable = false;

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }

  Future<void> _setBoundedText(String key, String value, int maxLength) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(
        key,
        trimmed.length <= maxLength ? trimmed : trimmed.substring(0, maxLength),
      );
    }
    notifyListeners();
  }
}

class NexPreferences extends _PreferencesStore
    with
        _AiPreferences,
        _BriefPreferences,
        _HomePreferences,
        _AppearancePreferences,
        _SecurityPreferences,
        _ProfilePreferences,
        _LibraryPreferences,
        _ServicePreferences,
        _BackupFolderPreferences {
  NexPreferences._(super.prefs, super.secureStorage);

  // Device identity and absolute paths belong to the receiving installation.
  static bool _portablePreference(String key) =>
      key != _kDeviceId &&
      key != 'profile.photo' &&
      key != 'sponsor.image_path' &&
      key != _kSyncBearerToken &&
      !key.startsWith('ai.key.') &&
      !key.startsWith('restore.') &&
      // A folder grant belongs to the phone that was given it.
      !key.startsWith('backup_folder.');

  Map<String, dynamic> backupSettings() {
    if (secureStorageUnavailable) {
      throw StateError('Secure storage unavailable');
    }
    return {
      'version': 1,
      'preferences': {
        for (final key in _prefs.getKeys())
          if (_portablePreference(key)) key: _prefs.get(key),
      },
      'credentials': Map<String, String>.from(_secureApiKeys),
    };
  }

  static void validateBackupSettings(Map<String, dynamic> value) {
    if (value.containsKey('vault')) {
      VaultSnapshot.fromJson(Map<String, dynamic>.from(value['vault'] as Map));
    }
    if (value['version'] != 1 ||
        value['preferences'] is! Map ||
        value['credentials'] is! Map) {
      throw const FormatException('Invalid settings backup');
    }
    for (final entry in (value['preferences'] as Map).entries) {
      final v = entry.value;
      if (entry.key is! String ||
          !(v is String ||
              v is bool ||
              v is num ||
              v is List && v.every((e) => e is String))) {
        throw const FormatException('Invalid preference value');
      }
    }
    final keys = {
      for (final provider in AiProvider.values) provider.wireName,
      _kSecureSyncToken,
    };
    for (final entry in (value['credentials'] as Map).entries) {
      if (!keys.contains(entry.key) || entry.value is! String) {
        throw const FormatException('Invalid credential');
      }
    }
  }

  static const _restoreRecoveryKey = 'nex.full_restore.recovery';
  Future<void> beginRestoreRecovery(
    String library, {
    bool includeVault = false,
  }) async {
    final settings = backupSettings();
    if (includeVault) settings['vault'] = await VaultStore().backup();
    final value = jsonEncode({'library': library, 'settings': settings});
    await _secureStorage.write(key: _restoreRecoveryKey, value: value);
    if (await _secureStorage.read(key: _restoreRecoveryKey) != value) {
      throw StateError('Cannot protect current settings');
    }
    if (!await _prefs.setBool('restore.in_progress', true)) {
      throw StateError('Cannot protect restore state');
    }
  }

  Future<Map<String, dynamic>?> pendingRestoreRecovery() async {
    if (_prefs.getBool('restore.in_progress') != true) return null;
    final value = await _secureStorage.read(key: _restoreRecoveryKey);
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  Future<void> finishRestoreRecovery() async {
    await _secureStorage.delete(key: _restoreRecoveryKey);
    await _prefs.remove('restore.in_progress');
  }

  Future<void> restoreSettings(Map<String, dynamic> value) async {
    validateBackupSettings(value);
    // Older/library-only backups must never clear or modify a newer vault.
    if (value.containsKey('vault')) {
      await VaultStore().restore(
        Map<String, dynamic>.from(value['vault'] as Map),
      );
    }
    // Verify secure writes before changing ordinary preferences.
    final credentials = Map<String, String>.from(value['credentials'] as Map);
    for (final entry in credentials.entries) {
      final key = entry.key == _kSecureSyncToken
          ? entry.key
          : 'ai.key.${entry.key}';
      await _secureStorage.write(key: key, value: entry.value);
      if (await _secureStorage.read(key: key) != entry.value) {
        throw StateError('Credential restore failed');
      }
    }
    for (final provider in AiProvider.values) {
      if (!credentials.containsKey(provider.wireName)) {
        await _secureStorage.delete(key: 'ai.key.${provider.wireName}');
      }
    }
    if (!credentials.containsKey(_kSecureSyncToken)) {
      await _secureStorage.delete(key: _kSecureSyncToken);
    }
    final prefs = Map<String, dynamic>.from(value['preferences'] as Map);
    for (final key in _prefs.getKeys().toList()) {
      if (_portablePreference(key) && !prefs.containsKey(key)) {
        if (!await _prefs.remove(key)) {
          throw StateError('Preference restore failed');
        }
      }
    }
    for (final entry in prefs.entries) {
      if (!_portablePreference(entry.key)) continue;
      final v = entry.value;
      final bool saved;
      if (v is String) {
        saved = await _prefs.setString(entry.key, v);
      } else if (v is bool) {
        saved = await _prefs.setBool(entry.key, v);
      } else if (v is int) {
        saved = await _prefs.setInt(entry.key, v);
      } else if (v is double) {
        saved = await _prefs.setDouble(entry.key, v);
      } else {
        saved = await _prefs.setStringList(
          entry.key,
          List<String>.from(v as List),
        );
      }
      if (!saved) throw StateError('Preference restore failed');
    }
    _secureApiKeys
      ..clear()
      ..addAll(credentials);
    _expandedNoteIds
      ..clear()
      ..addAll(_prefs.getStringList('timeline.expanded') ?? []);
    // Rehydrate derived caches through the mandatory application restart.
    await _writeProfileMirror();
  }

  static const _kDeviceId = 'nex.device_id';
  static const _kSyncBaseUrl = 'sync.base_url';
  static const _kSyncBearerToken = 'sync.bearer_token';
  static const _kPendingFeedback = 'feedback.pending_message';

  static const _kOnboardingComplete = 'onboarding.complete';
  static const _kTourComplete = 'onboarding.tour_complete';

  static Future<NexPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateAiProviderStorage(prefs);
    await _migrateSponsorDismissals(prefs);
    await _migrateWidgetTag(prefs);
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
    final preferences = NexPreferences._(
      prefs,
      // resetOnError off. The plugin's default is on, and it means that one
      // failed decryption — a keystore hiccup after a system update, a lock
      // screen change, a restored backup — silently deletes the entry, or
      // every entry, in this store: API keys, the sync token, the restore
      // recovery key. A key that cannot be read today is still there to be
      // read tomorrow; a deleted one is gone, and the user finds out only
      // when the assistant stops answering. The vault's store made the same
      // choice for the same reason. Only the error behaviour changes: the
      // store's name and encryption are the plugin defaults, so every key
      // saved before this still reads.
      const FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false)),
    );
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

  /// Whether the system "Alarms & reminders" screen has already been shown
  /// once for exact-alarm permission.
  ///
  /// That screen is intrusive — it leaves the app — so it is shown once per
  /// install, at the moment a first reminder is set, and never again for
  /// someone who declined. The OS's own toggle in Settings remains the way
  /// back; this flag only decides whether *Nex* sends anyone there a second
  /// time uninvited.
  static const _kExactAlarmsAsked = 'reminders.exact_alarms_asked';

  bool get remindersExactAlarmsAsked =>
      _prefs.getBool(_kExactAlarmsAsked) ?? false;

  Future<void> markRemindersExactAlarmsAsked() async {
    await _prefs.setBool(_kExactAlarmsAsked, true);
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
  bool get captureHoldHintSeen =>
      _prefs.getBool('home.capture_hold_hint_seen') ?? tourComplete;
  Future<void> dismissCaptureHoldHint() =>
      _setBool('home.capture_hold_hint_seen', true);

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
      await _hydrateCredential(key, key, provider.wireName);
    }
    await _hydrateCredential(
      _kSecureSyncToken,
      _kSyncBearerToken,
      _kSecureSyncToken,
    );
  }

  Future<void> _hydrateCredential(
    String key,
    String legacyKey,
    String cacheKey,
  ) async {
    try {
      final legacy = _prefs.getString(legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _secureStorage.write(key: key, value: legacy);
        if (await _secureStorage.read(key: key) != legacy) {
          secureStorageUnavailable = true;
          return;
        }
        await _prefs.remove(legacyKey);
      }
      final secured = await _secureStorage.read(key: key);
      if (secured != null) _secureApiKeys[cacheKey] = secured;
    } catch (_) {
      // A transferred/unavailable keystore must not block the local library.
      // Retain legacy credentials until a future successful migration.
      secureStorageUnavailable = true;
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

  /// One-time move from the widget's single tag filter to the set of them.
  static Future<void> _migrateWidgetTag(SharedPreferences prefs) async {
    final id = prefs.getString('widget.tag_id');
    if (id == null) return;
    if (!prefs.containsKey('widget.tags')) {
      await prefs.setString(
        'widget.tags',
        jsonEncode({id: prefs.getString('widget.tag_name') ?? ''}),
      );
    }
    await prefs.remove('widget.tag_id');
    await prefs.remove('widget.tag_name');
  }

  /// One-time move from the permanent list of dismissed card ids to the dated
  /// map [sponsorDismissals] reads.
  ///
  /// Stamped with now rather than dropped: someone who hid a card yesterday
  /// under the old rules should get one more cool-off out of it, not find it
  /// back in their timeline because they installed an update.
  static Future<void> _migrateSponsorDismissals(SharedPreferences prefs) async {
    final legacy = prefs.getStringList('sponsor.dismissed');
    if (legacy == null) return;
    if (legacy.isNotEmpty && !prefs.containsKey('sponsor.dismissed_at')) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(
        'sponsor.dismissed_at',
        jsonEncode({for (final id in legacy) id: now}),
      );
    }
    await prefs.remove('sponsor.dismissed');
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
  ///
  /// The token is a bearer credential: whoever holds it can read and write the
  /// library on the server. It lives in secure storage (Android Keystore /
  /// Windows DPAPI) for the same reason the provider API keys moved there, and
  /// a legacy plaintext value is migrated and verified during load.
  static const _kSecureSyncToken = 'sync.secure.bearer_token';
  String? get syncBearerToken => _secureApiKeys[_kSecureSyncToken];

  Future<void> setSyncBearerToken(String? value) async {
    if (value == null || value.isEmpty) {
      await _secureStorage.delete(key: _kSecureSyncToken);
      _secureApiKeys.remove(_kSecureSyncToken);
      await _prefs.remove(_kSyncBearerToken);
    } else {
      await _secureStorage.write(key: _kSecureSyncToken, value: value);
      _secureApiKeys[_kSecureSyncToken] = value;
      await _prefs.remove(_kSyncBearerToken);
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

  static const aiUserNameMaxLength = 40;
  static const aiUserIntroductionMaxLength = 500;

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

  /// The brief the user described in their own words, under
  /// [NexBriefStyle.custom].
  ///
  /// Capped like the assistant's for the same reason and kept on the device
  /// the same way. Separate from it because they answer different questions:
  /// one is how to talk, the other is what to say.
  static const briefInstructionMaxLength = 300;

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

  static const maxSavedSearches = 12;

  /// The key a recap is filed under: the local calendar day it describes.
  static String daySummaryDateKey(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';
}
