// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Nex';

  @override
  String get capture => 'Capture';

  @override
  String get captureHint => 'Capture…';

  @override
  String get search => 'Search';

  @override
  String get settings => 'Settings';

  @override
  String get text => 'Text';

  @override
  String get voice => 'Voice';

  @override
  String get photo => 'Photo';

  @override
  String get file => 'File';

  @override
  String get sync => 'Sync';

  @override
  String get syncSubtitle => 'Push pending notes and pull remote changes';

  @override
  String get syncNow => 'Sync now';

  @override
  String syncOk(int pushed, int pulled) {
    return 'Synced — pushed $pushed, pulled $pulled';
  }

  @override
  String get syncFailed => 'Sync failed';

  @override
  String get emptyTimeline => 'Tap + to capture';

  @override
  String get export => 'Export';

  @override
  String get exportSubtitle => 'JSON + Markdown + media archive';

  @override
  String get restore => 'Restore';

  @override
  String get restoreSubtitle => 'Recover from latest automatic backup';

  @override
  String get restoreConfirmTitle => 'Restore backup?';

  @override
  String get restoreConfirmBody =>
      'This replaces the current local database with the latest automatic backup.';

  @override
  String get cancel => 'Cancel';

  @override
  String get addTag => 'Add Tag';

  @override
  String get delete => 'Delete';

  @override
  String get noteDeleted => 'Note deleted';

  @override
  String get undo => 'Undo';

  @override
  String get swipeActions => 'Swipe actions';

  @override
  String swipeSummary(String leading, String trailing) {
    return 'Left: $leading · Right: $trailing';
  }

  @override
  String get swapSwipeMapping => 'Swap left / right actions';

  @override
  String get appearance => 'Appearance';

  @override
  String get comfortMode => 'Comfort Mode';

  @override
  String get comfortModeSubtitle =>
      'Lower contrast, warmer colors — independent of Light/Dark';

  @override
  String get recording => 'Recording…';

  @override
  String get discard => 'Discard';

  @override
  String get micPermission => 'Microphone permission required';

  @override
  String get gallerySwitch => 'No photo captured. Switch to gallery?';

  @override
  String get gallery => 'Gallery';

  @override
  String get searchHint => 'Search notes…';

  @override
  String get date => 'Date';

  @override
  String get clear => 'Clear';

  @override
  String get voiceSearchHint => 'Voice notes: searchable by tag/date only';

  @override
  String get tag => 'Tag';

  @override
  String get add => 'Add';

  @override
  String get searchableByTagDateOnly => 'Searchable by tag/date only';

  @override
  String get widgetLabel => 'Quick Capture';

  @override
  String get widgetDescription => 'Open Nex directly into text capture';
}
