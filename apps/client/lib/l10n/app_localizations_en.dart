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
  String get emptyAi =>
      'It can also read what you capture — voice becomes text, photos give up their words, tags get suggested. A provider in Settings adds summaries and search.';

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
  String get deleteBackup => 'Delete backup';

  @override
  String get deleteBackupBody =>
      'This local backup file will be deleted. It cannot be undone.';

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
  String get pin => 'Pin';

  @override
  String get unpin => 'Unpin';

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
      'Each edge is set on its own. Tap a row to pick what that swipe does, or turn it off.';

  @override
  String get revealInFolder => 'Copy file path';

  @override
  String get trash => 'Trash';

  @override
  String get trashRetention =>
      'Items here are removed permanently after 30 days.';

  @override
  String get deleteForever => 'Delete permanently';

  @override
  String get deleteForeverBody =>
      'This note will be gone for good. It cannot be undone.';

  @override
  String get emptyTrash => 'Empty trash';

  @override
  String get open => 'Open';

  @override
  String get cannotOpen => 'No app on this device can open this file.';

  @override
  String get sourceCode => 'Source code';

  @override
  String get capabilities => 'What Nex does';

  @override
  String get capabilityCapture =>
      'Text, voice, photo and file capture with no save button';

  @override
  String get capabilitySearch =>
      'Full-text, tag, date and type search that runs on this device';

  @override
  String get capabilityOffline =>
      'Every core flow works with no network at all';

  @override
  String get capabilityExport =>
      'Export everything as JSON, Markdown and the original media';

  @override
  String get version => 'Version';

  @override
  String emptyTrashBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes will be gone for good. It cannot be undone.',
      one: '1 note will be gone for good. It cannot be undone.',
    );
    return '$_temp0';
  }

  @override
  String get checkForUpdate => 'Check for update';

  @override
  String get checkingForUpdate => 'Looking for a newer release…';

  @override
  String get upToDate => 'You have the latest version.';

  @override
  String get downloadAndInstall => 'Download and install';

  @override
  String get downloading => 'Downloading…';

  @override
  String get readyToInstall => 'Downloaded. Ready to install.';

  @override
  String get install => 'Install';

  @override
  String get updateInstallNotice =>
      'Android will ask you to confirm the install. Your notes are not touched.';

  @override
  String get updateDownloadFailed =>
      'The download did not finish. Check your connection and try again.';

  @override
  String get updateNoSpace =>
      'There is not enough free space to download the update.';

  @override
  String get updateCheckFailed =>
      'Could not reach the update server. Check your connection and try again.';

  @override
  String get installBlocked =>
      'The installer did not open. Allow Nex to install unknown apps in your device settings, then try again.';

  @override
  String installedVersion(String version) {
    return 'Installed version $version';
  }

  @override
  String updateAvailable(String version) {
    return 'Version $version is available';
  }

  @override
  String get autoUpdateCheck => 'Check automatically';

  @override
  String get autoUpdateCheckHint =>
      'Once a day, quietly. A new release shows up as a dot here — never a notification.';

  @override
  String get updateReady => 'Downloaded and ready to install';

  @override
  String get yourName => 'Your name';

  @override
  String get yourNameHint => 'Only used to greet you, only on this device.';

  @override
  String get yourNamePlaceholder => 'Leave empty for no greeting';

  @override
  String greetingMorning(String name) {
    return 'Good morning, $name';
  }

  @override
  String greetingAfternoon(String name) {
    return 'Good afternoon, $name';
  }

  @override
  String greetingEvening(String name) {
    return 'Good evening, $name';
  }

  @override
  String greetingNight(String name) {
    return 'Still up, $name?';
  }

  @override
  String get updateDownloadedToast => 'Update downloaded — ready to install';

  @override
  String greetingMorningB(String name) {
    return 'Fresh page, $name';
  }

  @override
  String greetingMorningC(String name) {
    return 'The day is new, $name';
  }

  @override
  String greetingAfternoonB(String name) {
    return 'Halfway there, $name';
  }

  @override
  String greetingAfternoonC(String name) {
    return 'What have you got, $name?';
  }

  @override
  String greetingEveningB(String name) {
    return 'Winding down, $name';
  }

  @override
  String greetingEveningC(String name) {
    return 'The quiet hours, $name';
  }

  @override
  String greetingNightB(String name) {
    return 'Hello, night owl $name';
  }

  @override
  String greetingNightC(String name) {
    return 'The world\'s asleep, $name';
  }

  @override
  String get exportTitle => 'Taking it with you';

  @override
  String get exportExplained =>
      'Writes every note into one zip: the full data as JSON, a readable Markdown file per note, and every photo, recording and attachment. Nothing is left behind and nothing is uploaded — the file is handed to you.';

  @override
  String get exportAndShare => 'Export and share';

  @override
  String get importTitle => 'Import';

  @override
  String get importExplained =>
      'Reads a Nex export back into this library. Notes already here are left untouched, so importing the same file twice changes nothing.';

  @override
  String get chooseFile => 'Choose a file';

  @override
  String importDone(int added, int skipped) {
    String _temp0 = intl.Intl.pluralLogic(
      added,
      locale: localeName,
      other: '$added notes added',
      one: '1 note added',
      zero: 'Nothing new to add',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skipped,
      locale: localeName,
      other: '$skipped already here',
      one: '1 already here',
      zero: '',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get importFailed =>
      'That file could not be read as a Nex export. Your notes were not changed.';

  @override
  String get localBackupsTitle => 'Backups on this device';

  @override
  String get localBackupsExplained =>
      'Once a day, Nex copies its database into its own folder — the text, tags and dates, not the photos, recordings or attachments those notes point to. It is protection against a bad restore or a corrupted file, on this device. For a copy that includes the media, or to move to another device, export.';

  @override
  String get backupNow => 'Back up now';

  @override
  String get backupDone => 'Backed up';

  @override
  String get syncNotConfigured =>
      'No server is set up. Sync is optional — Nex works entirely offline without it.';

  @override
  String get syncServer => 'Sync server';

  @override
  String get syncServerHint => 'https://…';

  @override
  String get syncToken => 'Device token';

  @override
  String get aiShow => 'See what Nex made of this';

  @override
  String aiReady(String what) {
    return '$what ready';
  }

  @override
  String get aiSection => 'What Nex read';

  @override
  String get aiNothingYet =>
      'Nothing yet. Nex reads a note in the background after it is captured.';

  @override
  String get hide => 'Hide';

  @override
  String get catchUpTitle => 'The notes you already have';

  @override
  String get catchUpBody =>
      'Nex reads a note in the background right after it is captured — which means everything captured before this was switched on has never been read. This works through that backlog, oldest requests first, a batch at a time.';

  @override
  String get catchUpAction => 'Catch up';

  @override
  String catchUpDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes read',
      one: '1 note read',
      zero: 'Nothing left to read',
    );
    return '$_temp0';
  }

  @override
  String noteOfType(String type) {
    return '$type note';
  }

  @override
  String tagListLabel(String tags) {
    return 'Tags: $tags';
  }

  @override
  String get accentColorLabel => 'Accent color';

  @override
  String get captureFailedPermission =>
      'Nex was not allowed to use the camera or your photos. You can grant it in your device settings.';

  @override
  String get captureFailedStorage =>
      'There is no room left on this device for the file. Your existing notes were not changed.';

  @override
  String get captureFailedUnreadable =>
      'That file could not be read. If it lives in a cloud folder, open it once so the device has a copy.';

  @override
  String get retry => 'Try again';

  @override
  String get cropPhotoTitle => 'Crop photo';

  @override
  String get cropConfirm => 'Use photo';

  @override
  String get cropCancel => 'Discard photo';

  @override
  String get tagColor => 'Tag color';

  @override
  String get customColor => 'Custom';

  @override
  String get saturation => 'Saturation';

  @override
  String get brightness => 'Brightness';

  @override
  String get noColor => 'No color';

  @override
  String get color => 'Color';

  @override
  String get aiProvider => 'AI provider';

  @override
  String get aiProviderIntro =>
      'Choose where the intelligence features send their requests. Without a provider they run on this device only, which covers tag hints but not summaries.';

  @override
  String get apiKey => 'API key';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get model => 'Model';

  @override
  String get testConnection => 'Test connection';

  @override
  String get aiProviderNoneSubtitle => 'Runs on this device. No key needed.';

  @override
  String get aiProviderSaved => 'Provider saved.';

  @override
  String get aiKeyStorage =>
      'The key is stored on this device in the app\'s private settings. It is not encrypted, and it is never sent anywhere except to the provider you chose.';

  @override
  String get aiCapabilityNote =>
      'Tag suggestions and summaries work with every provider. Semantic search needs an OpenAI-compatible one. Speech-to-text and image text stay on-device for now.';

  @override
  String connectionOk(String model) {
    return 'Connected. Model $model answered.';
  }

  @override
  String get swipeNone => 'Nothing';

  @override
  String get intelligenceOff => 'Off';

  @override
  String get intelligenceMasterSubtitle =>
      'Let a provider read your notes to transcribe, summarise and suggest tags.';

  @override
  String get intelligenceOffBody =>
      'Everything stays on this device. Nothing is sent anywhere, and no note leaves the app.';

  @override
  String get intelligenceConsentTitle => 'Turn on intelligence?';

  @override
  String get intelligenceConsentBody =>
      'Nex works fully offline. Turning this on is the one exception: the notes covered by the capabilities you enable are sent to the provider you choose, so it can answer.\n\nNothing is sent until you also choose a provider and enter its key. You can turn this off again at any time, and nothing already saved is affected.';

  @override
  String get intelligenceConsentAccept => 'Turn on';

  @override
  String get intelligenceQuietNote =>
      'Results are worked out quietly in the background and kept with the note. Nothing interrupts you — a summary or a suggested tag appears only when you open the note and ask for it.';

  @override
  String get automatic => 'Worked out automatically';

  @override
  String get notSupportedByProvider => 'The provider you chose cannot do this';

  @override
  String get transcriptionSubtitle => 'Turn a voice note into searchable text';

  @override
  String get ocrSubtitle => 'Read the words in a photo';

  @override
  String get summarizationSubtitle => 'Condense a long note into one line';

  @override
  String get tagSuggestionsSubtitle =>
      'Propose tags — never applies them for you';

  @override
  String get semanticSearchSubtitle => 'Find notes by meaning, not just words';

  @override
  String get relatedNotesSubtitle =>
      'Show other notes that touch on the same thing';

  @override
  String get intelligenceOpen => 'Transcription, summaries, tags';
}
