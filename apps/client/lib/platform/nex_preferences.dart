import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SwipeAction { delete, addTag }

extension SwipeActionWire on SwipeAction {
  String get wireName => this == SwipeAction.delete ? 'delete' : 'add_tag';
  static SwipeAction fromWire(String value) =>
      value == 'add_tag' ? SwipeAction.addTag : SwipeAction.delete;
}

class NexPreferences extends ChangeNotifier {
  NexPreferences._(this._prefs);
  final SharedPreferences _prefs;

  static Future<NexPreferences> load() async =>
      NexPreferences._(await SharedPreferences.getInstance());

  SwipeAction get leadingAction =>
      SwipeActionWire.fromWire(_prefs.getString('swipe.leading') ?? 'add_tag');
  SwipeAction get trailingAction =>
      SwipeActionWire.fromWire(_prefs.getString('swipe.trailing') ?? 'delete');
  bool get comfortMode => _prefs.getBool('appearance.comfort') ?? false;
  bool get reduceMotion => _prefs.getBool('accessibility.reduce_motion') ?? false;
  bool get haptics => _prefs.getBool('accessibility.haptics') ?? true;
  bool get quietAnniversary => _prefs.getBool('timeline.quiet_anniversary') ?? true;
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

  Future<void> setComfortMode(bool value) => _setBool('appearance.comfort', value);
  Future<void> setReduceMotion(bool value) => _setBool('accessibility.reduce_motion', value);
  Future<void> setHaptics(bool value) => _setBool('accessibility.haptics', value);
  Future<void> setQuietAnniversary(bool value) => _setBool('timeline.quiet_anniversary', value);
  Future<void> setCloudAiOptIn(bool value) => _setBool('ai.cloud_opt_in', value);

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

  SwipeAction actionFor({required bool isLeading}) =>
      isLeading ? leadingAction : trailingAction;
}