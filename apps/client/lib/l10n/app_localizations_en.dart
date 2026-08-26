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
  String get captureHint => 'What\'s on your mind?';

  @override
  String get layoutTitle => 'Home layout';

  @override
  String get layoutSubtitle => 'What sits above your notes.';

  @override
  String get layoutGreeting => 'Greeting';

  @override
  String get layoutDaySummary => 'Smart daily summary';

  @override
  String get layoutSearchField => 'Search box';

  @override
  String get layoutTagRow => 'Tag row';

  @override
  String chatAboutGroup(String label, int count) {
    return 'About $label · $count notes';
  }

  @override
  String get groupActions => 'Group actions';

  @override
  String get groupAsk => 'Ask about these';

  @override
  String get groupDelete => 'Delete this group';

  @override
  String groupDeleteBody(int count) {
    return '$count notes move to Trash. You can put them back from Library → Trash.';
  }

  @override
  String groupDeleted(int count) {
    return '$count notes deleted';
  }

  @override
  String get assistantVoiceGroup => 'How it talks';

  @override
  String get assistantReachGroup => 'What it can see';

  @override
  String get storageModels => 'Offline model';

  @override
  String get storageImages => 'Photos';

  @override
  String get storageAudio => 'Recordings';

  @override
  String get storageBackups => 'Backups';

  @override
  String get storageNotes => 'Notes and index';

  @override
  String get storageOther => 'Other files';

  @override
  String get storageEmpty => 'Nothing stored yet.';

  @override
  String get remindRepeat => 'Repeat';

  @override
  String get remindRepeatOnce => 'Once';

  @override
  String get remindRepeatDaily => 'Every day';

  @override
  String get remindRepeatWeekly => 'Every week';

  @override
  String remindRepeatingAt(String when, String repeat) {
    return '$when · $repeat';
  }

  @override
  String get nudgeNotScheduled =>
      'The daily note was turned on, but this phone would not take the alarm.';

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
  String get semanticMatches =>
      'Nothing shares those words, but these are about the same thing:';

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
  String get timelineGroupPinned => 'Pinned';

  @override
  String get timelineGroupToday => 'Today';

  @override
  String get timelineGroupYesterday => 'Yesterday';

  @override
  String get timelineGroupWeek => 'Last week';

  @override
  String get timelineGroupMonth => 'Last month';

  @override
  String get timelineGroupOlder => 'Older';

  @override
  String timelineGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
    );
    return '$_temp0';
  }

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
  String get recentlyDeletedEmpty => 'Nothing recently deleted.';

  @override
  String get appearance => 'Appearance';

  @override
  String get language => 'Language';

  @override
  String get accessibility => 'Accessibility';

  @override
  String get haptics => 'Capture haptics';

  @override
  String get intelligence => 'Intelligence';

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
  String get shareDiagnostics => 'Share diagnostics';

  @override
  String get shareDiagnosticsBody =>
      'A local log of the last few crashes, in case something breaks. Nothing is sent anywhere unless you choose to share it here.';

  @override
  String get noDiagnosticsYet => 'Nothing to share yet';

  @override
  String get openSourceLicenses => 'Open-source licences';

  @override
  String get theme => 'Theme';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get comfortMode => 'Comfort Mode';

  @override
  String get accentColorSetting => 'Accent color';

  @override
  String get accentColorSettingSubtitle =>
      'Recolors the caret, focus rings, and active states everywhere';

  @override
  String get accentColorPickerTitle => 'Accent color';

  @override
  String get uiScale => 'Text & UI size';

  @override
  String get uiScaleSmall => 'Small';

  @override
  String get uiScaleDefault => 'Default';

  @override
  String get uiScaleLarge => 'Large';

  @override
  String get uiScaleLarger => 'Larger';

  @override
  String get enterSubmitsCapture => 'Enter saves the note';

  @override
  String get enterSubmitsCaptureSubtitle =>
      'Off starts a new line instead. Shift+Enter always starts a new line either way.';

  @override
  String get languageSystem => 'System';

  @override
  String get storage => 'Storage';

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
      'checklist': 'Checklist',
      'link': 'Link',
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
  String get sendFeedback => 'Send feedback';

  @override
  String get sendFeedbackSubtitle => 'Tell us what\'s working, or what isn\'t';

  @override
  String get feedbackHint => 'What\'s on your mind?';

  @override
  String get feedbackSend => 'Send';

  @override
  String get feedbackSent => 'Feedback sent — thank you';

  @override
  String get feedbackQueuedOffline =>
      'No connection — this will send once you\'re back online';

  @override
  String get feedbackFailed => 'Couldn\'t send that';

  @override
  String get feedbackUnavailable =>
      'Feedback isn\'t available in this build yet';

  @override
  String get feedbackOpenIssueInstead => 'Open a GitHub issue instead';

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
  String get changelogTitle => 'Changelog';

  @override
  String get changelogLatestHeading => 'Latest changes';

  @override
  String changelogVersionHeading(String version) {
    return 'Version $version';
  }

  @override
  String get changelogEmpty => 'Changelog unavailable.';

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
  String get timeNow => 'now';

  @override
  String timeMinutesAgo(int count) {
    return '${count}m';
  }

  @override
  String timeHoursAgo(int count) {
    return '${count}h';
  }

  @override
  String timeDaysAgo(int count) {
    return '${count}d';
  }

  @override
  String timeWeeksAgo(int count) {
    return '${count}w';
  }

  @override
  String timeMonthsAgo(int count) {
    return '${count}mo';
  }

  @override
  String timeYearsAgo(int count) {
    return '${count}y';
  }

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
  String get cropRotate => 'Rotate';

  @override
  String get cropAnnotate => 'Draw or add text';

  @override
  String get cropCancel => 'Discard photo';

  @override
  String get annotateTitle => 'Draw or add text';

  @override
  String get annotateDraw => 'Draw';

  @override
  String get annotateText => 'Text';

  @override
  String get annotateTextHint => 'Type something…';

  @override
  String get annotateUndo => 'Undo';

  @override
  String get annotateClear => 'Clear all';

  @override
  String get annotateDone => 'Done';

  @override
  String get annotateTapToPlaceText =>
      'Tap anywhere on the photo to place text';

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
  String get aiProviderNoneSubtitleLocal =>
      'Answers on this phone, from the model you downloaded.';

  @override
  String get aiProviderLocalNote =>
      'The model on your phone writes and reads text, so it covers the assistant, the daily recap and translation. It cannot hear a recording or read a photo — those still need a provider.';

  @override
  String get aiProviderNoneSubtitle => 'Runs on this device. No key needed.';

  @override
  String get aiProviderSaved => 'Provider saved.';

  @override
  String get aiKeyStorage =>
      'The key is kept in this device\'s own secure storage, not in the app\'s ordinary settings, and it is never sent anywhere except to the provider you chose.';

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
  String get chat => 'Chat';

  @override
  String get chatSubtitle => 'Ask Nex\'s built-in assistant';

  @override
  String get chatUnavailable =>
      'Local chat isn\'t available on this build yet.';

  @override
  String get chatEmptyHint =>
      'Ask anything — Nex answers on this device, with no internet needed.';

  @override
  String get chatInputHint => 'Message…';

  @override
  String get chatSendTooltip => 'Send';

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

  @override
  String get aiDaySummaryTitle => 'Daily Digest';

  @override
  String get aiDaySummarySemanticLabel => 'Today\'s summary';

  @override
  String get aiDaySummaryEmpty => 'Nothing to sum up yet.';

  @override
  String get aiDaySummaryRefresh => 'Write a new summary';

  @override
  String get aiDaySummaryCollapse => 'Hide the summary';

  @override
  String get aiDaySummaryExpand => 'Show the summary';

  @override
  String get aiHeadlineRefresh => 'Tap for a new line';

  @override
  String get aiOutputLanguage => 'AI output language';

  @override
  String get aiOutputLanguageSubtitle =>
      'The language summaries and suggestions come back in';

  @override
  String get aiOutputLanguageAuto => 'Match my notes';

  @override
  String get aiOutputLanguageEnglish => 'English';

  @override
  String get aiOutputLanguagePersian => 'Persian';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingStart => 'Start using Nex';

  @override
  String get onboardingWelcomeTitle => 'Somewhere to put it down';

  @override
  String get onboardingWelcomeBody =>
      'Anything you put in Nex is kept. Nothing else is asked of you — no account, no inbox to clear, nothing to keep up with.';

  @override
  String get onboardingCaptureTitle => 'There is no Save button';

  @override
  String get onboardingCaptureBody =>
      'Type it, say it, or photograph it. A note is yours the moment you make it, and it goes to the top of one list — no folders to file it into first.';

  @override
  String get onboardingIntelligenceTitle => 'It can read what you capture';

  @override
  String get onboardingIntelligenceBody =>
      'Voice becomes text, photos give up their words, and tags suggest themselves. This part is off until you add a provider in Settings — everything else works without it.';

  @override
  String get onboardingSilenceTitle => 'It will never interrupt you';

  @override
  String get onboardingSilenceBody =>
      'No notifications, no badges, no reminders, no streaks. Your notes stay on this device unless you set up syncing yourself.';

  @override
  String get onboardingSetupTitle => 'A few quick choices';

  @override
  String get onboardingSetupBody =>
      'All of these live in Settings afterwards, and none of them are permanent.';

  @override
  String get onboardingNameRequired => 'Nex needs something to call you.';

  @override
  String get checklist => 'Checklist';

  @override
  String get link => 'Link';

  @override
  String get checklistHint => 'An item, one per line';

  @override
  String get linkHint => 'Paste a link';

  @override
  String get linkNotValid => 'That does not look like a link.';

  @override
  String get openLink => 'Open link';

  @override
  String checklistProgress(int done, int total) {
    return '$done of $total';
  }

  @override
  String get chatGreeting => 'How can I help you today?';

  @override
  String get chatHint => 'Enter a prompt here';

  @override
  String get foreignImportTitle => 'Import notes';

  @override
  String get foreignImportSubtitle =>
      'From Google Keep, or any folder of .md and .txt files';

  @override
  String get foreignImportWorking => 'Reading your export…';

  @override
  String foreignImportDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes imported.',
      one: '1 note imported.',
      zero: 'No notes found in that file.',
    );
    return '$_temp0';
  }

  @override
  String get foreignImportUnreadable =>
      'Nex could not read that file. Pick the .zip you downloaded, or a .json, .md or .txt file.';

  @override
  String get localModelPause => 'Pause';

  @override
  String get localModelResume => 'Resume';

  @override
  String get localModelStop => 'Stop';

  @override
  String localModelPaused(String done, String total) {
    return 'Paused · $done of $total';
  }

  @override
  String localModelBytes(String done, String total) {
    return '$done of $total';
  }

  @override
  String get localModelLoading => 'Starting the model up…';

  @override
  String get localModelStopTitle => 'Stop the download?';

  @override
  String get localModelStopBody =>
      'What has downloaded so far is thrown away, and starting again begins from the beginning. Pause keeps it instead.';

  @override
  String get localModelManageInstalled => 'Downloaded and ready on this phone';

  @override
  String get localModelManageMissing =>
      'Not downloaded yet — the assistant needs it to work offline';

  @override
  String get localModelLoadFailed =>
      'The model is downloaded but would not start on this phone.';

  @override
  String get localModelLoadFailedDetail => 'What the runtime reported:';

  @override
  String get localModelTitle => 'On-device model';

  @override
  String get localModelSubtitle =>
      'Chat with no internet, once the model is downloaded';

  @override
  String get localModelExplained =>
      'Nex can run a language model on this phone, so chat works with no internet and nothing you type leaves the device. It is a large download and it stays on your phone until you remove it.';

  @override
  String localModelDownload(String size) {
    return 'Download · $size GB';
  }

  @override
  String get localModelDownloading => 'Downloading…';

  @override
  String localModelDownloadingPart(int index, int count) {
    return 'Downloading part $index of $count';
  }

  @override
  String get localModelJoining =>
      'Putting the pieces together and checking them…';

  @override
  String get localModelKeepOpen =>
      'You can leave this screen — the download keeps going. Closing the app stops it, and it picks up where it left off.';

  @override
  String get localModelReady => 'The model is ready. Chat works offline now.';

  @override
  String get localModelFailed =>
      'That download did not finish. Try again — it carries on from where it stopped.';

  @override
  String localModelInstalled(String size) {
    return 'Installed · $size GB on this phone';
  }

  @override
  String get localModelDelete => 'Remove the model';

  @override
  String get localModelDeleteTitle => 'Remove the model?';

  @override
  String get localModelDeleteBody =>
      'Offline chat stops working until you download it again. Your notes are not affected.';

  @override
  String get localModelDeleted => 'The model was removed.';

  @override
  String get localModelLicenseTitle => 'Before you download';

  @override
  String get localModelLicenseRead => 'Read the full terms';

  @override
  String get localModelLicenseAccept => 'I have read and accept these terms';

  @override
  String get localModelBlockedPlatform =>
      'On-device chat runs on Android and iPhone. This build cannot use it.';

  @override
  String get localModelBlockedArchitecture =>
      'This phone\'s processor is not one the model runs on. It needs a 64-bit ARM device.';

  @override
  String localModelBlockedStorage(String size) {
    return 'There is not enough free space. The download needs about $size GB free while it installs.';
  }

  @override
  String get localModelBlockedUnpublished =>
      'No model is available to download in this version yet.';

  @override
  String get tourNext => 'Next';

  @override
  String get tourDone => 'Got it';

  @override
  String get tourSkip => 'Skip';

  @override
  String get tourCaptureTitle => 'Everything starts here';

  @override
  String get tourCaptureBody =>
      'Tap to write a note, or record, photograph and attach one. Hold it to ask the assistant instead.';

  @override
  String get tourSearchTitle => 'Find anything';

  @override
  String get tourSearchBody =>
      'Search by word, or by what a note meant. Try tag:work or type:link to narrow it down.';

  @override
  String get tourLibraryTitle => 'Tags and deleted notes';

  @override
  String get tourLibraryBody =>
      'Your tags live here, and so does anything you deleted — for a while.';

  @override
  String get tourSettingsTitle => 'Make it yours';

  @override
  String get tourSettingsBody =>
      'Your name, theme, language, backups, and the AI provider that writes your summaries.';

  @override
  String get tourCardsTitle => 'One more thing';

  @override
  String get tourCardsBody =>
      'Swipe a note from either edge for its quick actions. Each edge is yours to set in Settings.';

  @override
  String get translate => 'Translate';

  @override
  String get translateTo => 'Into';

  @override
  String get translateWorking => 'Translating…';

  @override
  String get translateFailed => 'The translation did not come back.';

  @override
  String get translateSaveAsNote => 'Keep as a note';

  @override
  String get translateSaved => 'Saved as a new note.';

  @override
  String get chatSpeak => 'Speak';

  @override
  String get chatTranscribing => 'Reading your recording…';

  @override
  String get chatTranscribeFailed => 'Nothing came back from that recording.';

  @override
  String get chatSend => 'Send';

  @override
  String get chatFailed =>
      'No answer came back. Check the provider in Settings, or try again.';

  @override
  String get chatPromptSummarise => 'Summarise what I captured this week';

  @override
  String get chatPromptPlan => 'Turn my notes into a to-do list';

  @override
  String get chatPromptIdeas => 'Suggest what I might be forgetting';

  @override
  String get assistantActionDone => 'Done.';

  @override
  String get assistantActionFailed => 'That didn\'t work.';

  @override
  String get assistantConfirmCreate => 'Save this as a new note?';

  @override
  String get assistantConfirmEdit => 'Replace this note\'s text?';

  @override
  String get assistantConfirmDelete => 'Move this note to Recently Deleted?';

  @override
  String get assistantConfirmTags => 'Change this note\'s tags?';

  @override
  String get assistantApply => 'Do it';

  @override
  String chatAboutNote(String note) {
    return 'About: $note';
  }

  @override
  String get chatHistory => 'Conversations';

  @override
  String get chatHistoryEmpty => 'No saved conversations yet.';

  @override
  String get chatNewConversation => 'New conversation';

  @override
  String get chatClearHistory => 'Delete all conversations';

  @override
  String get assistant => 'Assistant';

  @override
  String get assistantSubtitle =>
      'Creativity, answer length, and what it can see';

  @override
  String get assistantCreativity => 'Creativity';

  @override
  String get assistantCreativityPrecise => 'Precise';

  @override
  String get assistantCreativityBalanced => 'Balanced';

  @override
  String get assistantCreativityInventive => 'Inventive';

  @override
  String get assistantLength => 'Answer length';

  @override
  String get assistantLengthBrief => 'Brief';

  @override
  String get assistantLengthStandard => 'Standard';

  @override
  String get assistantLengthFull => 'Full';

  @override
  String get assistantScope => 'Stay in my notes';

  @override
  String get assistantScopeSubtitle =>
      'Off, it will answer anything — including things it is bad at.';

  @override
  String get assistantInstruction => 'How it should answer';

  @override
  String get assistantInstructionHint => 'Answer with a bit of humour';

  @override
  String get assistantInstructionSubtitle =>
      'Your own note to the assistant, sent with every question. It changes the tone, not what it is allowed to do.';

  @override
  String get assistantContext => 'Notes it can see';

  @override
  String get assistantContextSlow =>
      'Sending 100 notes or more makes every question slower — the model reads all of them before it answers. On the on-device model it is very noticeable.';

  @override
  String get assistantContextNone => 'None';

  @override
  String assistantContextCount(int count) {
    return 'Last $count';
  }

  @override
  String get askAboutNote => 'Ask';

  @override
  String get saveSearch => 'Save this search';

  @override
  String get savedSearches => 'Saved';

  @override
  String get assistantConfirmMerge => 'Combine these notes into one?';

  @override
  String get assistantConfirmChecklist => 'Turn this into a checklist?';

  @override
  String get assistantConfirmCheck => 'Tick this item off?';

  @override
  String get assistantConfirmSetting => 'Change this setting?';

  @override
  String get remind => 'Remind';

  @override
  String get remindLater => 'In an hour';

  @override
  String get remindEvening => 'This evening';

  @override
  String get remindTomorrow => 'Tomorrow morning';

  @override
  String get remindNextWeek => 'Next week';

  @override
  String get remindPick => 'Pick a time…';

  @override
  String get remindClear => 'Remove reminder';

  @override
  String get nudgeTitle => 'Daily nudge';

  @override
  String get nudgeSubtitle => 'One notification a day, at a time you choose';

  @override
  String get nudgeTime => 'Time';

  @override
  String get notifications => 'Notifications';

  @override
  String nudgeGreetingMorning(String name) {
    return 'Good morning, $name';
  }

  @override
  String nudgeGreetingDay(String name) {
    return 'Hello, $name';
  }

  @override
  String get nudgeGreetingPlain => 'Nex';

  @override
  String get nudgeNothing =>
      'A clear page. Nex is here when something comes up.';

  @override
  String get localModelLicenseGloss =>
      'In short: the model is Google\'s, it comes with its own terms, and downloading it means accepting them.';

  @override
  String get notificationTest => 'Send a test notification';

  @override
  String get notificationTestHint => 'One now, and one in ten seconds';

  @override
  String get notificationTestSent => 'Sent — one now, one in ten seconds';

  @override
  String notificationTestFailed(String error) {
    return 'Could not send it — $error';
  }

  @override
  String timeMinutesShort(int count) {
    return '${count}m';
  }

  @override
  String timeHoursShort(int count) {
    return '${count}h';
  }

  @override
  String timeDaysShort(int count) {
    return '${count}d';
  }

  @override
  String get remindOverdue => 'Overdue';

  @override
  String remindWhenToday(String time) {
    return 'Today at $time';
  }

  @override
  String remindWhenTomorrow(String time) {
    return 'Tomorrow at $time';
  }

  @override
  String remindWhenOn(String date, String time) {
    return '$date at $time';
  }

  @override
  String remindCurrent(String when) {
    return 'Set for $when';
  }

  @override
  String get remindChange => 'Change reminder';

  @override
  String get swipeNoneHint => 'This edge does nothing';

  @override
  String get swipeDeleteHint => 'Move the note to Recently Deleted';

  @override
  String get swipeAddTagHint => 'Pick a tag for the note';

  @override
  String get swipePinHint => 'Keep the note at the top of the timeline';

  @override
  String get swipeRemindHint => 'Choose when it should come back';

  @override
  String get swipeShareHint => 'Send the note to another app';

  @override
  String get swipeAskHint => 'Open the assistant on this note';

  @override
  String get swipeLeadingEdge => 'Swipe from the left';

  @override
  String get swipeTrailingEdge => 'Swipe from the right';

  @override
  String get markdownTooLarge =>
      'Too large to show here — open it in another app.';

  @override
  String markdownUnreadable(String error) {
    return 'This file could not be read — $error';
  }

  @override
  String remindSetIn(String when) {
    return 'Reminder set — $when from now';
  }

  @override
  String remindInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String remindInHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String remindInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get remindNotScheduled =>
      'That time was saved on the note, but this phone would not take the alarm.';

  @override
  String get remindSet => 'Reminder set';

  @override
  String get remindDenied => 'Nex needs permission to send notifications.';
}
