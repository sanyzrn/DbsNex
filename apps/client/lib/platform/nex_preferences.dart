import 'package:flutter/foundation.dart';
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

  Future<void> setComfortMode(bool value) async {
    await _prefs.setBool(_kComfort, value);
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
