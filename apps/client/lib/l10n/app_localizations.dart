import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Nex'**
  String get appTitle;

  /// No description provided for @capture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get capture;

  /// No description provided for @captureHint.
  ///
  /// In en, this message translates to:
  /// **'Capture…'**
  String get captureHint;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search notes…'**
  String get searchHint;

  /// No description provided for @searchStart.
  ///
  /// In en, this message translates to:
  /// **'Start typing to find a capture.'**
  String get searchStart;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @filtersCount.
  ///
  /// In en, this message translates to:
  /// **'Filters ({count})'**
  String filtersCount(int count);

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @resultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No results} =1{1 result} other{{count} results}}'**
  String resultCount(int count);

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches “{query}”.'**
  String nothingMatches(String query);

  /// No description provided for @closestThing.
  ///
  /// In en, this message translates to:
  /// **'The closest thing you wrote:'**
  String get closestThing;

  /// No description provided for @nothingClose.
  ///
  /// In en, this message translates to:
  /// **'Nothing close either.'**
  String get nothingClose;

  /// No description provided for @emptyPromise.
  ///
  /// In en, this message translates to:
  /// **'Anything you put here is kept.'**
  String get emptyPromise;

  /// No description provided for @emptySupport.
  ///
  /// In en, this message translates to:
  /// **'Nothing else is asked.'**
  String get emptySupport;

  /// No description provided for @emptyType.
  ///
  /// In en, this message translates to:
  /// **'type'**
  String get emptyType;

  /// No description provided for @emptySpeak.
  ///
  /// In en, this message translates to:
  /// **'speak'**
  String get emptySpeak;

  /// No description provided for @emptyPhotograph.
  ///
  /// In en, this message translates to:
  /// **'photograph'**
  String get emptyPhotograph;

  /// No description provided for @emptyNoSave.
  ///
  /// In en, this message translates to:
  /// **'There is no Save button.'**
  String get emptyNoSave;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get addTag;

  /// No description provided for @noteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Note deleted'**
  String get noteDeleted;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @merge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get merge;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @tagActions.
  ///
  /// In en, this message translates to:
  /// **'Tag actions'**
  String get tagActions;

  /// No description provided for @noteCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No notes} =1{1 note} other{{count} notes}}'**
  String noteCount(int count);

  /// No description provided for @renameTag.
  ///
  /// In en, this message translates to:
  /// **'Rename tag'**
  String get renameTag;

  /// No description provided for @deleteTag.
  ///
  /// In en, this message translates to:
  /// **'Delete tag?'**
  String get deleteTag;

  /// No description provided for @deleteTagBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the tag from notes. It never deletes the notes themselves.'**
  String get deleteTagBody;

  /// No description provided for @recentlyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Recently Deleted'**
  String get recentlyDeleted;

  /// No description provided for @recentlyDeletedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing recently deleted.'**
  String get recentlyDeletedEmpty;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @accessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibility;

  /// No description provided for @reduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reduceMotion;

  /// No description provided for @haptics.
  ///
  /// In en, this message translates to:
  /// **'Capture haptics'**
  String get haptics;

  /// No description provided for @quietAnniversary.
  ///
  /// In en, this message translates to:
  /// **'One year ago'**
  String get quietAnniversary;

  /// No description provided for @intelligence.
  ///
  /// In en, this message translates to:
  /// **'Intelligence'**
  String get intelligence;

  /// No description provided for @intelligenceLocal.
  ///
  /// In en, this message translates to:
  /// **'Runs on this device unless Cloud AI is enabled.'**
  String get intelligenceLocal;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About Nex'**
  String get about;

  /// No description provided for @localFirstTitle.
  ///
  /// In en, this message translates to:
  /// **'Stored locally'**
  String get localFirstTitle;

  /// No description provided for @localFirstBody.
  ///
  /// In en, this message translates to:
  /// **'Your notes are stored on this device at {path}'**
  String localFirstBody(String path);

  /// No description provided for @copyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy data path'**
  String get copyPath;

  /// No description provided for @silenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Silence is a feature'**
  String get silenceTitle;

  /// No description provided for @silenceBody.
  ///
  /// In en, this message translates to:
  /// **'Nex never sends notifications, badges, reminders, or engagement prompts.'**
  String get silenceBody;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacyBody.
  ///
  /// In en, this message translates to:
  /// **'Core capture and search do not collect or transmit your notes.'**
  String get privacyBody;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get openSourceLicenses;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @comfortMode.
  ///
  /// In en, this message translates to:
  /// **'Comfort Mode'**
  String get comfortMode;

  /// No description provided for @comfortModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lower contrast and warmer colors, independent of Light or Dark'**
  String get comfortModeSubtitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languagePersian.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get languagePersian;

  /// No description provided for @quietAnniversarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'When you captured something on this day last year, one small line says so at the top of the timeline. Inside Nex only — never a notification.'**
  String get quietAnniversarySubtitle;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @storageUsed.
  ///
  /// In en, this message translates to:
  /// **'{size} used locally'**
  String storageUsed(String size);

  /// No description provided for @stopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get stopRecording;

  /// No description provided for @recordingElapsed.
  ///
  /// In en, this message translates to:
  /// **'Recording, {elapsed}'**
  String recordingElapsed(String elapsed);

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @captureFailed.
  ///
  /// In en, this message translates to:
  /// **'Capture could not be stored. Your existing notes were not changed.'**
  String get captureFailed;

  /// No description provided for @oneYearAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One year ago · 1 capture} other{One year ago · {count} captures}}'**
  String oneYearAgo(int count);

  /// No description provided for @noteNotFound.
  ///
  /// In en, this message translates to:
  /// **'Note not found'**
  String get noteNotFound;

  /// No description provided for @mediaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This media file is unavailable.'**
  String get mediaUnavailable;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @swipeActions.
  ///
  /// In en, this message translates to:
  /// **'Swipe actions'**
  String get swipeActions;

  /// No description provided for @transcription.
  ///
  /// In en, this message translates to:
  /// **'Transcription'**
  String get transcription;

  /// No description provided for @ocr.
  ///
  /// In en, this message translates to:
  /// **'OCR'**
  String get ocr;

  /// No description provided for @tagSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Tag suggestions'**
  String get tagSuggestions;

  /// No description provided for @semanticSearch.
  ///
  /// In en, this message translates to:
  /// **'Semantic search'**
  String get semanticSearch;

  /// No description provided for @summarization.
  ///
  /// In en, this message translates to:
  /// **'Summarization'**
  String get summarization;

  /// No description provided for @relatedNotes.
  ///
  /// In en, this message translates to:
  /// **'Related notes'**
  String get relatedNotes;

  /// No description provided for @cloudAi.
  ///
  /// In en, this message translates to:
  /// **'Cloud AI (opt-in)'**
  String get cloudAi;

  /// No description provided for @cloudAiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Off by default. Core capture always works without it.'**
  String get cloudAiSubtitle;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncComplete.
  ///
  /// In en, this message translates to:
  /// **'Sync complete'**
  String get syncComplete;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String exportedTo(String path);

  /// No description provided for @restoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get restoreBackup;

  /// No description provided for @restoreBody.
  ///
  /// In en, this message translates to:
  /// **'Replace the local database with the newest verified backup?'**
  String get restoreBody;

  /// No description provided for @backupCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No backups} =1{1 backup} other{{count} backups}}'**
  String backupCount(int count);

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'The operation failed. Your existing notes were not changed.'**
  String get operationFailed;

  /// No description provided for @noteType.
  ///
  /// In en, this message translates to:
  /// **'{type, select, text{Text} voice{Voice} photo{Photo} file{File} other{Note}}'**
  String noteType(String type);

  /// Confirm button on the inline add-tag dialog
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAction;

  /// Filter chip that clears the content-type filter
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// Swipe-action mapping row in Settings
  ///
  /// In en, this message translates to:
  /// **'Swipe from the leading edge'**
  String get swipeLeading;

  /// Swipe-action mapping row in Settings
  ///
  /// In en, this message translates to:
  /// **'Swipe from the trailing edge'**
  String get swipeTrailing;

  /// Empty state in the tag manager
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get noTagsYet;

  /// About screen attribution
  ///
  /// In en, this message translates to:
  /// **'Made by'**
  String get madeBy;

  /// About screen attribution
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// Detail sheet action: edit a text note's body
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Confirm button on the edit and caption dialogs
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Title of the edit-note dialog
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get editNote;

  /// Caption section heading in the detail sheet
  ///
  /// In en, this message translates to:
  /// **'Caption'**
  String get caption;

  /// Placeholder in the caption field
  ///
  /// In en, this message translates to:
  /// **'Optional description…'**
  String get captionHint;

  /// Button shown when a media note has no caption yet
  ///
  /// In en, this message translates to:
  /// **'Add caption'**
  String get addCaption;

  /// Button shown when a media note already has a caption
  ///
  /// In en, this message translates to:
  /// **'Edit caption'**
  String get editCaption;

  /// Placeholder text where a caption would appear
  ///
  /// In en, this message translates to:
  /// **'No caption'**
  String get noCaption;

  /// Placeholder in the tag-name field
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get tagName;

  /// Short label on the chip that opens the add-tag dialog
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tag;

  /// Summary section heading in the detail sheet
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// Detail sheet action that requests an on-demand summary
  ///
  /// In en, this message translates to:
  /// **'Summarize'**
  String get summarize;

  /// Heading above dismissible AI tag suggestions
  ///
  /// In en, this message translates to:
  /// **'Suggested tags'**
  String get suggestedTags;

  /// Dismisses the tag suggestions
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Heading above a voice note's transcript
  ///
  /// In en, this message translates to:
  /// **'Transcript'**
  String get transcript;

  /// FR-4.6 — voice notes are not keyword-searchable in v1
  ///
  /// In en, this message translates to:
  /// **'Searchable by tag/date only'**
  String get voiceSearchHint;

  /// Voice note header in the detail sheet
  ///
  /// In en, this message translates to:
  /// **'Voice · {seconds}s'**
  String voiceDuration(int seconds);

  /// Hint under a photo in the detail sheet
  ///
  /// In en, this message translates to:
  /// **'Tap the image to view it full screen'**
  String get tapToExpand;

  /// Subtitle of a related-note row
  ///
  /// In en, this message translates to:
  /// **'Similarity {score}'**
  String similarity(String score);

  /// Opens the detail sheet's overflow menu
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// Toast after copying a note's text
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// Toast when a note has no copyable text
  ///
  /// In en, this message translates to:
  /// **'This note has no text to copy'**
  String get nothingToCopy;

  /// Opens the note's metadata panel
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// Metadata row label
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get created;

  /// Metadata row label
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get updated;

  /// Metadata row label for a media file's size
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// Title of the create-tag dialog in the tag manager
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get createTag;

  /// Settings group: tags, recently deleted, storage
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// Settings group: sync, export, restore
  ///
  /// In en, this message translates to:
  /// **'Data & backup'**
  String get dataAndBackup;

  /// Shown when the database fails to open at startup
  ///
  /// In en, this message translates to:
  /// **'Nex could not open your local library. Your files were not changed.'**
  String get libraryOpenFailed;

  /// Retries startup after a failed library open
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// Screen-reader label for the startup splash
  ///
  /// In en, this message translates to:
  /// **'Nex is opening'**
  String get opening;

  /// Explains that each swipe edge is configured independently
  ///
  /// In en, this message translates to:
  /// **'Each edge is set on its own. Tap a row to pick what that swipe does, or turn it off.'**
  String get swipeActionsHint;

  /// Copies a media note's file path to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy file path'**
  String get revealInFolder;

  /// Screen title for soft-deleted notes
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// Retention notice at the top of the trash
  ///
  /// In en, this message translates to:
  /// **'Items here are removed permanently after 30 days.'**
  String get trashRetention;

  /// Hard-deletes one trashed note
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deleteForever;

  /// Confirmation body for a permanent delete
  ///
  /// In en, this message translates to:
  /// **'This note will be gone for good. It cannot be undone.'**
  String get deleteForeverBody;

  /// Hard-deletes every trashed note
  ///
  /// In en, this message translates to:
  /// **'Empty trash'**
  String get emptyTrash;

  /// Opens a media note with the system's default app
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// Shown when the OS has no handler for the file
  ///
  /// In en, this message translates to:
  /// **'No app on this device can open this file.'**
  String get cannotOpen;

  /// About screen row linking to the repository
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get sourceCode;

  /// About screen section heading
  ///
  /// In en, this message translates to:
  /// **'What Nex does'**
  String get capabilities;

  /// About screen bullet
  ///
  /// In en, this message translates to:
  /// **'Text, voice, photo and file capture with no save button'**
  String get capabilityCapture;

  /// About screen bullet
  ///
  /// In en, this message translates to:
  /// **'Full-text, tag, date and type search that runs on this device'**
  String get capabilitySearch;

  /// About screen bullet
  ///
  /// In en, this message translates to:
  /// **'Every core flow works with no network at all'**
  String get capabilityOffline;

  /// About screen bullet
  ///
  /// In en, this message translates to:
  /// **'Export everything as JSON, Markdown and the original media'**
  String get capabilityExport;

  /// About screen row label
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// Confirmation body for emptying the trash
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note will be gone for good. It cannot be undone.} other{{count} notes will be gone for good. It cannot be undone.}}'**
  String emptyTrashBody(int count);

  /// Settings row and update sheet title
  ///
  /// In en, this message translates to:
  /// **'Check for update'**
  String get checkForUpdate;

  /// Update sheet, while the check runs
  ///
  /// In en, this message translates to:
  /// **'Looking for a newer release…'**
  String get checkingForUpdate;

  /// Update sheet, nothing newer exists
  ///
  /// In en, this message translates to:
  /// **'You have the latest version.'**
  String get upToDate;

  /// Starts the update download
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get downloadAndInstall;

  /// Update sheet, during the download
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloading;

  /// Update sheet, download finished
  ///
  /// In en, this message translates to:
  /// **'Downloaded. Ready to install.'**
  String get readyToInstall;

  /// Hands the downloaded package to the system installer
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// Sets expectations before the system installer appears
  ///
  /// In en, this message translates to:
  /// **'Android will ask you to confirm the install. Your notes are not touched.'**
  String get updateInstallNotice;

  /// Update sheet, the check did not complete
  ///
  /// In en, this message translates to:
  /// **'Could not reach the update server. Check your connection and try again.'**
  String get updateCheckFailed;

  /// Shown when handing the package to the installer fails
  ///
  /// In en, this message translates to:
  /// **'The installer did not open. Allow Nex to install unknown apps in your device settings, then try again.'**
  String get installBlocked;

  /// Update sheet subtitle
  ///
  /// In en, this message translates to:
  /// **'Installed version {version}'**
  String installedVersion(String version);

  /// Update sheet headline when a newer release exists
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available'**
  String updateAvailable(String version);

  /// Settings toggle for the daily background update check
  ///
  /// In en, this message translates to:
  /// **'Check automatically'**
  String get autoUpdateCheck;

  /// Explains what the automatic update check does
  ///
  /// In en, this message translates to:
  /// **'Once a day, quietly. A new release shows up as a dot here — never a notification.'**
  String get autoUpdateCheckHint;

  /// Settings subtitle when the installer is already on disk
  ///
  /// In en, this message translates to:
  /// **'Downloaded and ready to install'**
  String get updateReady;

  /// Settings row that stores the name the app greets you by
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// Reassurance under the name row
  ///
  /// In en, this message translates to:
  /// **'Only used to greet you, only on this device.'**
  String get yourNameHint;

  /// Placeholder in the name field
  ///
  /// In en, this message translates to:
  /// **'Leave empty for no greeting'**
  String get yourNamePlaceholder;

  /// Timeline title before noon
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name}'**
  String greetingMorning(String name);

  /// Timeline title in the afternoon
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, {name}'**
  String greetingAfternoon(String name);

  /// Timeline title in the evening
  ///
  /// In en, this message translates to:
  /// **'Good evening, {name}'**
  String greetingEvening(String name);

  /// Timeline title late at night
  ///
  /// In en, this message translates to:
  /// **'Still up, {name}?'**
  String greetingNight(String name);

  /// Toast raised when a background update download completes
  ///
  /// In en, this message translates to:
  /// **'Update downloaded — ready to install'**
  String get updateDownloadedToast;

  /// Second morning greeting variant
  ///
  /// In en, this message translates to:
  /// **'Fresh page, {name}'**
  String greetingMorningB(String name);

  /// Third morning greeting variant
  ///
  /// In en, this message translates to:
  /// **'The day is new, {name}'**
  String greetingMorningC(String name);

  /// Second afternoon greeting variant
  ///
  /// In en, this message translates to:
  /// **'Halfway there, {name}'**
  String greetingAfternoonB(String name);

  /// Third afternoon greeting variant
  ///
  /// In en, this message translates to:
  /// **'What have you got, {name}?'**
  String greetingAfternoonC(String name);

  /// Second evening greeting variant
  ///
  /// In en, this message translates to:
  /// **'Winding down, {name}'**
  String greetingEveningB(String name);

  /// Third evening greeting variant
  ///
  /// In en, this message translates to:
  /// **'The quiet hours, {name}'**
  String greetingEveningC(String name);

  /// Second late-night greeting variant
  ///
  /// In en, this message translates to:
  /// **'Hello, night owl {name}'**
  String greetingNightB(String name);

  /// Third late-night greeting variant
  ///
  /// In en, this message translates to:
  /// **'The world\'s asleep, {name}'**
  String greetingNightC(String name);

  /// Heading above export and import
  ///
  /// In en, this message translates to:
  /// **'Taking it with you'**
  String get exportTitle;

  /// Says what an export actually contains
  ///
  /// In en, this message translates to:
  /// **'Writes every note into one zip: the full data as JSON, a readable Markdown file per note, and every photo, recording and attachment. Nothing is left behind and nothing is uploaded — the file is handed to you.'**
  String get exportExplained;

  /// Button that builds the archive and opens the share sheet
  ///
  /// In en, this message translates to:
  /// **'Export and share'**
  String get exportAndShare;

  /// Reads an export archive back in
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importTitle;

  /// Says that import is additive and safe to repeat
  ///
  /// In en, this message translates to:
  /// **'Reads a Nex export back into this library. Notes already here are left untouched, so importing the same file twice changes nothing.'**
  String get importExplained;

  /// Opens the file picker for import
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get chooseFile;

  /// Result of an import
  ///
  /// In en, this message translates to:
  /// **'{added, plural, =0{Nothing new to add} =1{1 note added} other{{added} notes added}} · {skipped, plural, =0{} =1{1 already here} other{{skipped} already here}}'**
  String importDone(int added, int skipped);

  /// Import error
  ///
  /// In en, this message translates to:
  /// **'That file could not be read as a Nex export. Your notes were not changed.'**
  String get importFailed;

  /// Heading above the local backup list
  ///
  /// In en, this message translates to:
  /// **'Backups on this device'**
  String get localBackupsTitle;

  /// Says what local backups are and are not for
  ///
  /// In en, this message translates to:
  /// **'Once a day, Nex copies its database into its own folder. It is protection against a bad restore or a corrupted file — not against a lost phone. For that, export.'**
  String get localBackupsExplained;

  /// Takes a backup outside the daily schedule
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNow;

  /// Confirmation after a manual backup
  ///
  /// In en, this message translates to:
  /// **'Backed up'**
  String get backupDone;

  /// Explains why Sync now does nothing
  ///
  /// In en, this message translates to:
  /// **'No server is set up. Sync is optional — Nex works entirely offline without it.'**
  String get syncNotConfigured;

  /// Row that holds the sync endpoint
  ///
  /// In en, this message translates to:
  /// **'Sync server'**
  String get syncServer;

  /// Placeholder in the sync endpoint field
  ///
  /// In en, this message translates to:
  /// **'https://…'**
  String get syncServerHint;

  /// Row that holds the sync bearer token
  ///
  /// In en, this message translates to:
  /// **'Device token'**
  String get syncToken;

  /// Reveals the intelligence panel when nothing is derived yet
  ///
  /// In en, this message translates to:
  /// **'See what Nex made of this'**
  String get aiShow;

  /// Reveals the intelligence panel, naming what it holds
  ///
  /// In en, this message translates to:
  /// **'{what} ready'**
  String aiReady(String what);

  /// Heading of the revealed intelligence panel
  ///
  /// In en, this message translates to:
  /// **'What Nex read'**
  String get aiSection;

  /// Shown when the intelligence panel has nothing to show
  ///
  /// In en, this message translates to:
  /// **'Nothing yet. Nex reads a note in the background after it is captured.'**
  String get aiNothingYet;

  /// Collapses the intelligence panel
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// Heading above the backfill control
  ///
  /// In en, this message translates to:
  /// **'The notes you already have'**
  String get catchUpTitle;

  /// Explains what the backfill does and why it is needed
  ///
  /// In en, this message translates to:
  /// **'Nex reads a note in the background right after it is captured — which means everything captured before this was switched on has never been read. This works through that backlog, oldest requests first, a batch at a time.'**
  String get catchUpBody;

  /// Starts a backfill pass
  ///
  /// In en, this message translates to:
  /// **'Catch up'**
  String get catchUpAction;

  /// Result of a backfill pass
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing left to read} =1{1 note read} other{{count} notes read}}'**
  String catchUpDone(int count);

  /// Screen-reader label naming a note's type
  ///
  /// In en, this message translates to:
  /// **'{type} note'**
  String noteOfType(String type);

  /// Screen-reader label listing a note's tags
  ///
  /// In en, this message translates to:
  /// **'Tags: {tags}'**
  String tagListLabel(String tags);

  /// Screen-reader label for a tag's colour swatch
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColorLabel;

  /// Capture failed because the OS refused access
  ///
  /// In en, this message translates to:
  /// **'Nex was not allowed to use the camera or your photos. You can grant it in your device settings.'**
  String get captureFailedPermission;

  /// Capture failed because the device is out of space
  ///
  /// In en, this message translates to:
  /// **'There is no room left on this device for the file. Your existing notes were not changed.'**
  String get captureFailedStorage;

  /// Capture failed because the picked file could not be read
  ///
  /// In en, this message translates to:
  /// **'That file could not be read. If it lives in a cloud folder, open it once so the device has a copy.'**
  String get captureFailedUnreadable;

  /// Action on a failure message that repeats what failed
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// Title of the tag color picker
  ///
  /// In en, this message translates to:
  /// **'Tag color'**
  String get tagColor;

  /// Heading above the free color sliders
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customColor;

  /// Color picker slider label
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get saturation;

  /// Color picker slider label
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightness;

  /// The tag carries no accent
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get noColor;

  /// Tag manager menu entry that opens the color picker
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// Screen title and dropdown label
  ///
  /// In en, this message translates to:
  /// **'AI provider'**
  String get aiProvider;

  /// Explains what the screen is for
  ///
  /// In en, this message translates to:
  /// **'Choose where the intelligence features send their requests. Without a provider they run on this device only, which covers tag hints but not summaries.'**
  String get aiProviderIntro;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKey;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrl;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// Button that verifies the configuration
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get testConnection;

  /// Second line on the "no provider" row of the provider list
  ///
  /// In en, this message translates to:
  /// **'Runs on this device. No key needed.'**
  String get aiProviderNoneSubtitle;

  /// Confirmation shown after the AI provider settings are stored
  ///
  /// In en, this message translates to:
  /// **'Provider saved.'**
  String get aiProviderSaved;

  /// Honest note about how the key is kept
  ///
  /// In en, this message translates to:
  /// **'The key is stored on this device in the app\'s private settings. It is not encrypted, and it is never sent anywhere except to the provider you chose.'**
  String get aiKeyStorage;

  /// What each capability can actually reach
  ///
  /// In en, this message translates to:
  /// **'Tag suggestions and summaries work with every provider. Semantic search needs an OpenAI-compatible one. Speech-to-text and image text stay on-device for now.'**
  String get aiCapabilityNote;

  /// Successful connection test
  ///
  /// In en, this message translates to:
  /// **'Connected. Model {model} answered.'**
  String connectionOk(String model);

  /// Swipe edge bound to no action at all
  ///
  /// In en, this message translates to:
  /// **'Nothing'**
  String get swipeNone;

  /// Settings row subtitle when the AI master switch is off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get intelligenceOff;

  /// The master switch's own explanation
  ///
  /// In en, this message translates to:
  /// **'Let a provider read your notes to transcribe, summarise and suggest tags.'**
  String get intelligenceMasterSubtitle;

  /// Shown while the master switch is off
  ///
  /// In en, this message translates to:
  /// **'Everything stays on this device. Nothing is sent anywhere, and no note leaves the app.'**
  String get intelligenceOffBody;

  /// Consent dialog title
  ///
  /// In en, this message translates to:
  /// **'Turn on intelligence?'**
  String get intelligenceConsentTitle;

  /// Consent dialog body
  ///
  /// In en, this message translates to:
  /// **'Nex works fully offline. Turning this on is the one exception: the notes covered by the capabilities you enable are sent to the provider you choose, so it can answer.\n\nNothing is sent until you also choose a provider and enter its key. You can turn this off again at any time, and nothing already saved is affected.'**
  String get intelligenceConsentBody;

  /// Consent dialog confirm
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get intelligenceConsentAccept;

  /// Explains the quiet, on-demand behaviour
  ///
  /// In en, this message translates to:
  /// **'Results are worked out quietly in the background and kept with the note. Nothing interrupts you — a summary or a suggested tag appears only when you open the note and ask for it.'**
  String get intelligenceQuietNote;

  /// Heading above the capability switches
  ///
  /// In en, this message translates to:
  /// **'Worked out automatically'**
  String get automatic;

  /// Capability unavailable for the selected provider
  ///
  /// In en, this message translates to:
  /// **'The provider you chose cannot do this'**
  String get notSupportedByProvider;

  /// Capability explanation
  ///
  /// In en, this message translates to:
  /// **'Turn a voice note into searchable text'**
  String get transcriptionSubtitle;

  /// Capability explanation
  ///
  /// In en, this message translates to:
  /// **'Read the words in a photo'**
  String get ocrSubtitle;

  /// Capability explanation
  ///
  /// In en, this message translates to:
  /// **'Condense a long note into one line'**
  String get summarizationSubtitle;

  /// Capability explanation
  ///
  /// In en, this message translates to:
  /// **'Propose tags — never applies them for you'**
  String get tagSuggestionsSubtitle;

  /// Capability explanation
  ///
  /// In en, this message translates to:
  /// **'Find notes by meaning, not just words'**
  String get semanticSearchSubtitle;

  /// Capability explanation
  ///
  /// In en, this message translates to:
  /// **'Show other notes that touch on the same thing'**
  String get relatedNotesSubtitle;

  /// Settings row that opens the intelligence screen
  ///
  /// In en, this message translates to:
  /// **'Transcription, summaries, tags'**
  String get intelligenceOpen;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
