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
  String get searchHint => 'Search notes…';

  @override
  String get searchStart => 'Start typing to find a capture.';

  @override
  String get settings => 'Settings';

  @override
  String get voice => 'Voice';

  @override
  String get camera => 'Camera';

  @override
  String get gallery => 'Gallery';

  @override
  String get photo => 'Photo';

  @override
  String get file => 'File';

  @override
  String get text => 'Text';

  @override
  String get filters => 'Filters';

  @override
  String filtersCount(int count) {
    return 'Filters ($count)';
  }

  @override
  String get date => 'Date';

  @override
  String get clear => 'Clear';

  @override
  String resultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
      zero: 'No results',
    );
    return '$_temp0';
  }

  @override
  String nothingMatches(String query) {
    return 'Nothing matches “$query”.';
  }

  @override
  String get closestThing => 'The closest thing you wrote:';

  @override
  String get nothingClose => 'Nothing close either.';

  @override
  String get emptyPromise => 'Anything you put here is kept.';

  @override
  String get emptySupport => 'Nothing else is asked.';

  @override
  String get emptyType => 'type';

  @override
  String get emptySpeak => 'speak';

  @override
  String get emptyPhotograph => 'photograph';

  @override
  String get emptyNoSave => 'There is no Save button.';

  @override
  String get delete => 'Delete';

  @override
  String get addTag => 'Add tag';

  @override
  String get noteDeleted => 'Note deleted';

  @override
  String get undo => 'Undo';

  @override
  String get cancel => 'Cancel';

  @override
  String get restore => 'Restore';

  @override
  String get rename => 'Rename';

  @override
  String get merge => 'Merge';

  @override
  String get tags => 'Tags';

  @override
  String get tagActions => 'Tag actions';

  @override
  String noteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
      zero: 'No notes',
    );
    return '$_temp0';
  }

  @override
  String get renameTag => 'Rename tag';

  @override
  String get deleteTag => 'Delete tag?';

  @override
  String get deleteTagBody =>
      'This removes the tag from notes. It never deletes the notes themselves.';

  @override
  String get recentlyDeleted => 'Recently Deleted';

  @override
  String get recentlyDeletedEmpty => 'Nothing recently deleted.';

  @override
  String get appearance => 'Appearance';

  @override
  String get language => 'Language';

  @override
  String get accessibility => 'Accessibility';

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get haptics => 'Capture haptics';

  @override
  String get quietAnniversary => 'Show the quiet anniversary line';

  @override
  String get intelligence => 'Intelligence';

  @override
  String get intelligenceLocal =>
      'Runs on this device unless Cloud AI is enabled.';

  @override
  String get about => 'About Nex';

  @override
  String get localFirstTitle => 'Stored locally';

  @override
  String localFirstBody(String path) {
    return 'Your notes are stored on this device at $path';
  }

  @override
  String get copyPath => 'Copy data path';

  @override
  String get silenceTitle => 'Silence is a feature';

  @override
  String get silenceBody =>
      'Nex never sends notifications, badges, reminders, or engagement prompts.';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacyBody =>
      'Core capture and search do not collect or transmit your notes.';

  @override
  String get openSourceLicenses => 'Open-source licences';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get comfortMode => 'Comfort Mode';

  @override
  String get comfortModeSubtitle =>
      'Lower contrast and warmer colors, independent of Light or Dark';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePersian => 'Persian';

  @override
  String get quietAnniversarySubtitle =>
      'Only inside Nex. Never a notification or badge.';

  @override
  String get storage => 'Storage';

  @override
  String storageUsed(String size) {
    return '$size used locally';
  }

  @override
  String get stopRecording => 'Stop recording';

  @override
  String recordingElapsed(String elapsed) {
    return 'Recording, $elapsed';
  }

  @override
  String get discard => 'Discard';

  @override
  String get captureFailed =>
      'Capture could not be stored. Your existing notes were not changed.';

  @override
  String oneYearAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'One year ago · $count captures',
      one: 'One year ago · 1 capture',
    );
    return '$_temp0';
  }

  @override
  String get noteNotFound => 'Note not found';

  @override
  String get mediaUnavailable => 'This media file is unavailable.';

  @override
  String get copy => 'Copy';

  @override
  String get share => 'Share';

  @override
  String get swipeActions => 'Swipe actions';

  @override
  String get swapSwipeMapping => 'Swap start and end actions';

  @override
  String get transcription => 'Transcription';

  @override
  String get ocr => 'OCR';

  @override
  String get tagSuggestions => 'Tag suggestions';

  @override
  String get semanticSearch => 'Semantic search';

  @override
  String get summarization => 'Summarization';

  @override
  String get relatedNotes => 'Related notes';

  @override
  String get cloudAi => 'Cloud AI (opt-in)';

  @override
  String get cloudAiSubtitle =>
      'Off by default. Core capture always works without it.';

  @override
  String get sync => 'Sync';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncComplete => 'Sync complete';

  @override
  String get export => 'Export';

  @override
  String exportedTo(String path) {
    return 'Exported to $path';
  }

  @override
  String get restoreBackup => 'Restore backup';

  @override
  String get restoreBody =>
      'Replace the local database with the newest verified backup?';

  @override
  String backupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count backups',
      one: '1 backup',
      zero: 'No backups',
    );
    return '$_temp0';
  }

  @override
  String get operationFailed =>
      'The operation failed. Your existing notes were not changed.';

  @override
  String noteType(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'text': 'Text',
      'voice': 'Voice',
      'photo': 'Photo',
      'file': 'File',
      'other': 'Note',
    });
    return '$_temp0';
  }

  @override
  String get addAction => 'Add';

  @override
  String get all => 'All';

  @override
  String get swipeLeading => 'Swipe from the leading edge';

  @override
  String get swipeTrailing => 'Swipe from the trailing edge';

  @override
  String get noTagsYet => 'No tags yet';

  @override
  String get madeBy => 'Made by';

  @override
  String get website => 'Website';

  @override
  String get edit => 'Edit';

  @override
  String get save => 'Save';

  @override
  String get editNote => 'Edit note';

  @override
  String get caption => 'Caption';

  @override
  String get captionHint => 'Optional description…';

  @override
  String get addCaption => 'Add caption';

  @override
  String get editCaption => 'Edit caption';

  @override
  String get noCaption => 'No caption';

  @override
  String get tagName => 'Tag name';

  @override
  String get tag => 'Tag';

  @override
  String get summary => 'Summary';

  @override
  String get summarize => 'Summarize';

  @override
  String get suggestedTags => 'Suggested tags';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get transcript => 'Transcript';

  @override
  String get voiceSearchHint => 'Searchable by tag/date only';

  @override
  String voiceDuration(int seconds) {
    return 'Voice · ${seconds}s';
  }

  @override
  String get tapToExpand => 'Tap the image to view it full screen';

  @override
  String similarity(String score) {
    return 'Similarity $score';
  }

  @override
  String get moreOptions => 'More options';

  @override
  String get copied => 'Copied';

  @override
  String get nothingToCopy => 'This note has no text to copy';

  @override
  String get details => 'Details';

  @override
  String get created => 'Created';

  @override
  String get updated => 'Updated';

  @override
  String get size => 'Size';

  @override
  String get createTag => 'New tag';

  @override
  String get libraryTitle => 'Library';

  @override
  String get dataAndBackup => 'Data & backup';

  @override
  String get libraryOpenFailed =>
      'Nex could not open your local library. Your files were not changed.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get opening => 'Nex is opening';

  @override
  String get swipeActionsHint =>
      'These two actions are the whole set. Tap a row to swap which edge does which.';

  @override
  String get revealInFolder => 'Copy file path';
}
