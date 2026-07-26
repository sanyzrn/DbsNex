import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fixed swipe action set (ADR-022) — not an extensible framework.
enum SwipeAction {
  delete,
  addTag;

  String get wireName => switch (this) {
        SwipeAction.delete => 'delete',
        SwipeAction.addTag => 'add_tag',
      };

  static SwipeAction fromWire(String value) => switch (value) {
        'add_tag' => SwipeAction.addTag,
        _ => SwipeAction.delete,
      };

  String get label => switch (this) {
        SwipeAction.delete => 'Delete',
        SwipeAction.addTag => 'Add Tag',
      };
}

/// Device-local preferences (not synced in v1.x — ADR-022).
class NexPreferences extends ChangeNotifier {
  NexPreferences._(this._prefs);

  final SharedPreferences _prefs;

  static const _kLeading = 'swipe.leading';
  static const _kTrailing = 'swipe.trailing';
  static const _kComfort = 'appearance.comfort_mode';
  static const _kThemeMode = 'appearance.theme_mode';
  static const _kAiTranscription = 'ai.transcription';
  static const _kAiOcr = 'ai.ocr';
  static const _kAiTags = 'ai.tag_suggestions';
  static const _kAiSemantic = 'ai.semantic_search';
  static const _kAiSummary = 'ai.summarization';
  static const _kAiRelated = 'ai.related_notes';
  static const _kAiCloud = 'ai.cloud_opt_in';

  static Future<NexPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NexPreferences._(prefs);
  }

  /// Defaults: leading = Add Tag, trailing = Delete (FR-2.6).
  SwipeAction get leadingAction =>
      SwipeAction.fromWire(_prefs.getString(_kLeading) ?? 'add_tag');

  SwipeAction get trailingAction =>
      SwipeAction.fromWire(_prefs.getString(_kTrailing) ?? 'delete');

  bool get comfortMode => _prefs.getBool(_kComfort) ?? false;

  /// Light / Dark / System (default System) — mockup Appearance control.
  ThemeMode get themeMode {
    switch (_prefs.getString(_kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Cloud AI is opt-in per 09-ai.md (default off — on-device only).
  bool get cloudAiOptIn => _prefs.getBool(_kAiCloud) ?? false;

  AiCapabilities get aiCapabilities => AiCapabilities(
        transcription: _prefs.getBool(_kAiTranscription) ?? true,
        ocr: _prefs.getBool(_kAiOcr) ?? true,
        tagSuggestions: _prefs.getBool(_kAiTags) ?? true,
        semanticSearch: _prefs.getBool(_kAiSemantic) ?? true,
        summarization: _prefs.getBool(_kAiSummary) ?? true,
        relatedNotes: _prefs.getBool(_kAiRelated) ?? true,
      );

  Future<void> setComfortMode(bool value) async {
    await _prefs.setBool(_kComfort, value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final wire = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(_kThemeMode, wire);
    notifyListeners();
  }

  Future<void> setCloudAiOptIn(bool value) async {
    await _prefs.setBool(_kAiCloud, value);
    notifyListeners();
  }

  Future<void> setAiCapabilities(AiCapabilities value) async {
    await _prefs.setBool(_kAiTranscription, value.transcription);
    await _prefs.setBool(_kAiOcr, value.ocr);
    await _prefs.setBool(_kAiTags, value.tagSuggestions);
    await _prefs.setBool(_kAiSemantic, value.semanticSearch);
    await _prefs.setBool(_kAiSummary, value.summarization);
    await _prefs.setBool(_kAiRelated, value.relatedNotes);
    notifyListeners();
  }

  Future<void> swapSwipeMapping() async {
    final leading = leadingAction;
    final trailing = trailingAction;
    await _prefs.setString(_kLeading, trailing.wireName);
    await _prefs.setString(_kTrailing, leading.wireName);
    notifyListeners();
  }

  SwipeAction actionFor({required bool isLeading}) =>
      isLeading ? leadingAction : trailingAction;
}
