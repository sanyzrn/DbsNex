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

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @calendarPersian.
  ///
  /// In en, this message translates to:
  /// **'Solar Hijri'**
  String get calendarPersian;

  /// No description provided for @calendarGregorian.
  ///
  /// In en, this message translates to:
  /// **'Gregorian'**
  String get calendarGregorian;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @chatNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the service. Check your connection and try again.'**
  String get chatNetworkError;

  /// No description provided for @chatTimeout.
  ///
  /// In en, this message translates to:
  /// **'The service took too long to respond. Your message is kept; try again.'**
  String get chatTimeout;

  /// No description provided for @chatAuthError.
  ///
  /// In en, this message translates to:
  /// **'The service rejected access. Check your API key and account permissions.'**
  String get chatAuthError;

  /// No description provided for @chatRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The service limit was reached. Wait a little and try again.'**
  String get chatRateLimited;

  /// No description provided for @chatServiceError.
  ///
  /// In en, this message translates to:
  /// **'The service is temporarily unavailable. Try again later.'**
  String get chatServiceError;

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
  /// **'What\'s on your mind?'**
  String get captureHint;

  /// No description provided for @layoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Home layout'**
  String get layoutTitle;

  /// No description provided for @layoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What sits above your notes.'**
  String get layoutSubtitle;

  /// No description provided for @layoutGreeting.
  ///
  /// In en, this message translates to:
  /// **'Greeting'**
  String get layoutGreeting;

  /// No description provided for @layoutDaySummary.
  ///
  /// In en, this message translates to:
  /// **'Smart daily summary'**
  String get layoutDaySummary;

  /// No description provided for @layoutSearchField.
  ///
  /// In en, this message translates to:
  /// **'Search box'**
  String get layoutSearchField;

  /// No description provided for @layoutTagRow.
  ///
  /// In en, this message translates to:
  /// **'Tag row'**
  String get layoutTagRow;

  /// No description provided for @chatAboutGroup.
  ///
  /// In en, this message translates to:
  /// **'About {label} · {count} notes'**
  String chatAboutGroup(String label, int count);

  /// No description provided for @groupActions.
  ///
  /// In en, this message translates to:
  /// **'Group actions'**
  String get groupActions;

  /// No description provided for @groupAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask about these'**
  String get groupAsk;

  /// No description provided for @groupDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete this group'**
  String get groupDelete;

  /// No description provided for @groupDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'{count} notes move to Trash. You can put them back from Library → Trash.'**
  String groupDeleteBody(int count);

  /// No description provided for @groupDeleted.
  ///
  /// In en, this message translates to:
  /// **'{count} notes deleted'**
  String groupDeleted(int count);

  /// No description provided for @assistantVoiceGroup.
  ///
  /// In en, this message translates to:
  /// **'How it talks'**
  String get assistantVoiceGroup;

  /// No description provided for @assistantReachGroup.
  ///
  /// In en, this message translates to:
  /// **'What it can see'**
  String get assistantReachGroup;

  /// Says that the assistant's name and introduction reach the AI provider
  ///
  /// In en, this message translates to:
  /// **'Included with your messages to the provider you choose.'**
  String get assistantAboutYouNote;

  /// No description provided for @assistantAboutYouGroup.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get assistantAboutYouGroup;

  /// No description provided for @assistantProfileIntro.
  ///
  /// In en, this message translates to:
  /// **'Give the assistant a little context about you, then choose the voice that feels right. These details are sent only with assistant questions.'**
  String get assistantProfileIntro;

  /// No description provided for @assistantCallMe.
  ///
  /// In en, this message translates to:
  /// **'What should it call you?'**
  String get assistantCallMe;

  /// No description provided for @assistantCallMeHint.
  ///
  /// In en, this message translates to:
  /// **'Your preferred name'**
  String get assistantCallMeHint;

  /// No description provided for @assistantAboutMe.
  ///
  /// In en, this message translates to:
  /// **'A short introduction'**
  String get assistantAboutMe;

  /// No description provided for @assistantAboutMeHint.
  ///
  /// In en, this message translates to:
  /// **'What should the assistant know about you?'**
  String get assistantAboutMeHint;

  /// No description provided for @assistantResponseStyle.
  ///
  /// In en, this message translates to:
  /// **'Response style'**
  String get assistantResponseStyle;

  /// No description provided for @assistantStyleNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural'**
  String get assistantStyleNatural;

  /// No description provided for @assistantStyleFriendly.
  ///
  /// In en, this message translates to:
  /// **'Friendly'**
  String get assistantStyleFriendly;

  /// No description provided for @assistantStyleFormal.
  ///
  /// In en, this message translates to:
  /// **'Formal'**
  String get assistantStyleFormal;

  /// No description provided for @assistantStyleSerious.
  ///
  /// In en, this message translates to:
  /// **'Serious'**
  String get assistantStyleSerious;

  /// No description provided for @assistantStyleRomantic.
  ///
  /// In en, this message translates to:
  /// **'Romantic'**
  String get assistantStyleRomantic;

  /// No description provided for @assistantStyleCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get assistantStyleCustom;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileOpenHint.
  ///
  /// In en, this message translates to:
  /// **'Photo, name, birthday, and bio'**
  String get profileOpenHint;

  /// No description provided for @profileChangePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change profile photo'**
  String get profileChangePhoto;

  /// No description provided for @profileRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get profileRemovePhoto;

  /// No description provided for @profilePhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'The profile photo could not be saved.'**
  String get profilePhotoFailed;

  /// No description provided for @profileBirthday.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get profileBirthday;

  /// No description provided for @profileBirthdayEmpty.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get profileBirthdayEmpty;

  /// No description provided for @profileBio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get profileBio;

  /// No description provided for @profileBioHint.
  ///
  /// In en, this message translates to:
  /// **'A few words about you'**
  String get profileBioHint;

  /// No description provided for @securityTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securityTitle;

  /// No description provided for @securityAppLock.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get securityAppLock;

  /// No description provided for @securityOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get securityOff;

  /// No description provided for @securityDevicePasscode.
  ///
  /// In en, this message translates to:
  /// **'Device passcode'**
  String get securityDevicePasscode;

  /// No description provided for @securityDevicePasscodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock Nex with your phone or computer passcode, PIN, or pattern.'**
  String get securityDevicePasscodeSubtitle;

  /// No description provided for @securityBiometric.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint or biometrics'**
  String get securityBiometric;

  /// No description provided for @securityBiometricSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Require an enrolled fingerprint, face, or Windows Hello instead of passcode fallback.'**
  String get securityBiometricSubtitle;

  /// No description provided for @securityLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Authentication is handled by your device. Nex never receives or stores your passcode or biometric data.'**
  String get securityLocalOnly;

  /// No description provided for @securityScreenshotBlocked.
  ///
  /// In en, this message translates to:
  /// **'While the lock is on, Nex is also hidden from the recent-apps screen and screenshots of it are blocked.'**
  String get securityScreenshotBlocked;

  /// Small label at the top of the sponsor card, saying what it is
  ///
  /// In en, this message translates to:
  /// **'SPONSORED'**
  String get sponsorLabel;

  /// Tooltip of the sponsor card's dismiss button
  ///
  /// In en, this message translates to:
  /// **'Hide this'**
  String get sponsorDismiss;

  /// Settings row that opens the OS notification-channel screen for reminders
  ///
  /// In en, this message translates to:
  /// **'Reminder sound'**
  String get notificationSoundReminders;

  /// Settings row that opens the OS notification-channel screen for the daily digest
  ///
  /// In en, this message translates to:
  /// **'Daily digest sound'**
  String get notificationSoundDaily;

  /// Explains that the sound choice lives in the OS settings
  ///
  /// In en, this message translates to:
  /// **'Sound, vibration and importance, in Android settings'**
  String get notificationSoundSubtitle;

  /// Shown when the OS notification settings could not be opened
  ///
  /// In en, this message translates to:
  /// **'This phone has no screen for that.'**
  String get notificationSoundUnavailable;

  /// Title of the widget settings screen and its row in Settings
  ///
  /// In en, this message translates to:
  /// **'Home screen widget'**
  String get widgetSettingsTitle;

  /// Settings row subtitle for the widget screen
  ///
  /// In en, this message translates to:
  /// **'What the widget shows'**
  String get widgetSettingsSubtitle;

  /// Explains what the widget settings do
  ///
  /// In en, this message translates to:
  /// **'By default the widget shows the top of your timeline. These narrow it down.'**
  String get widgetSettingsIntro;

  /// Heading above the note-type filter chips
  ///
  /// In en, this message translates to:
  /// **'Kinds of note'**
  String get widgetSettingsKinds;

  /// Chip that clears the note-type filter
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get widgetSettingsEverything;

  /// Heading above the tag filter chips
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get widgetSettingsTag;

  /// Chip that clears the tag filter
  ///
  /// In en, this message translates to:
  /// **'Any tag'**
  String get widgetSettingsAnyTag;

  /// Shown in place of the tag chips when the library has no tags
  ///
  /// In en, this message translates to:
  /// **'No tags yet.'**
  String get widgetSettingsNoTags;

  /// Explains the bounded scan the filtered widget does
  ///
  /// In en, this message translates to:
  /// **'With a filter on, the widget shows matches from your most recent notes rather than searching the whole library.'**
  String get widgetSettingsScanNote;

  /// Switch that floats pinned notes to the top of the widget
  ///
  /// In en, this message translates to:
  /// **'Pinned notes first'**
  String get widgetSettingsPinnedFirst;

  /// Explains both sides of the pinned-first switch
  ///
  /// In en, this message translates to:
  /// **'On, pinned notes sit at the top the way they do in Nex. Off, they stay wherever their own date puts them, as though they were not pinned.'**
  String get widgetSettingsPinnedFirstHint;

  /// Switch that lets the widget keep showing notes while the app lock is closed
  ///
  /// In en, this message translates to:
  /// **'Show notes while Nex is locked'**
  String get widgetSettingsWhenLocked;

  /// Explains both sides of the show-while-locked switch
  ///
  /// In en, this message translates to:
  /// **'Off, the widget empties itself whenever the lock closes. On, your notes stay on the home screen, where anyone holding the phone can read them.'**
  String get widgetSettingsWhenLockedHint;

  /// Tooltip of the lock button on the timeline
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get securityLockNow;

  /// Security row that chooses when the app lock re-arms
  ///
  /// In en, this message translates to:
  /// **'Lock when'**
  String get securityLockWhen;

  /// App lock re-arms the moment the app is backgrounded
  ///
  /// In en, this message translates to:
  /// **'As soon as I leave'**
  String get securityLockImmediately;

  /// Explains the immediate lock timing
  ///
  /// In en, this message translates to:
  /// **'Every time Nex goes to the background'**
  String get securityLockImmediatelyHint;

  /// App lock re-arms only after a delay
  ///
  /// In en, this message translates to:
  /// **'After a while'**
  String get securityLockAfterTitle;

  /// Summary of the delayed lock timing on the security row
  ///
  /// In en, this message translates to:
  /// **'After {delay}'**
  String securityLockAfter(String delay);

  /// Explains the delayed lock timing
  ///
  /// In en, this message translates to:
  /// **'A quick trip to another app will not ask again'**
  String get securityLockAfterHint;

  /// App lock re-arms only on the explicit lock button
  ///
  /// In en, this message translates to:
  /// **'Only when I ask'**
  String get securityLockManual;

  /// Explains the manual lock timing
  ///
  /// In en, this message translates to:
  /// **'Nex stays open until you tap the lock'**
  String get securityLockManualHint;

  /// A lock delay under a minute
  ///
  /// In en, this message translates to:
  /// **'{count} seconds'**
  String securityLockSeconds(int count);

  /// A lock delay in minutes
  ///
  /// In en, this message translates to:
  /// **'{count} minutes'**
  String securityLockMinutes(int count);

  /// A lock delay in hours
  ///
  /// In en, this message translates to:
  /// **'{count} hour'**
  String securityLockHours(int count);

  /// No description provided for @securityPasscodeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Set up a device passcode, PIN, or pattern first.'**
  String get securityPasscodeUnavailable;

  /// No description provided for @securityBiometricUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No enrolled fingerprint or other biometric was found.'**
  String get securityBiometricUnavailable;

  /// No description provided for @securityAuthenticateReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock Nex to protect your notes'**
  String get securityAuthenticateReason;

  /// No description provided for @securityLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Nex is locked'**
  String get securityLockedTitle;

  /// No description provided for @securityLockedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Authenticate with your device to open your notes.'**
  String get securityLockedSubtitle;

  /// No description provided for @securityUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get securityUnlock;

  /// No description provided for @pinLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You can pin up to 5 notes'**
  String get pinLimitReached;

  /// No description provided for @storageModels.
  ///
  /// In en, this message translates to:
  /// **'Offline model'**
  String get storageModels;

  /// No description provided for @storageImages.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get storageImages;

  /// No description provided for @storageAudio.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get storageAudio;

  /// No description provided for @storageBackups.
  ///
  /// In en, this message translates to:
  /// **'Backups'**
  String get storageBackups;

  /// No description provided for @storageNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes and index'**
  String get storageNotes;

  /// No description provided for @storageOther.
  ///
  /// In en, this message translates to:
  /// **'Other files'**
  String get storageOther;

  /// No description provided for @storageEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing stored yet.'**
  String get storageEmpty;

  /// No description provided for @remindRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get remindRepeat;

  /// No description provided for @remindRepeatOnce.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get remindRepeatOnce;

  /// No description provided for @remindRepeatDaily.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get remindRepeatDaily;

  /// No description provided for @remindRepeatWeekly.
  ///
  /// In en, this message translates to:
  /// **'Every week'**
  String get remindRepeatWeekly;

  /// No description provided for @remindRepeatingAt.
  ///
  /// In en, this message translates to:
  /// **'{when} · {repeat}'**
  String remindRepeatingAt(String when, String repeat);

  /// No description provided for @nudgeNotScheduled.
  ///
  /// In en, this message translates to:
  /// **'The daily note was turned on, but this phone would not take the alarm.'**
  String get nudgeNotScheduled;

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

  /// No description provided for @semanticMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing shares those words, but these are about the same thing:'**
  String get semanticMatches;

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

  /// No description provided for @emptyAi.
  ///
  /// In en, this message translates to:
  /// **'It can also read what you capture — voice becomes text, photos give up their words, tags get suggested. A provider in Settings adds summaries and search.'**
  String get emptyAi;

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

  /// Timeline section for the pinned note
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get timelineGroupPinned;

  /// Timeline section for today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get timelineGroupToday;

  /// Timeline section for yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get timelineGroupYesterday;

  /// Timeline section for the past seven days
  ///
  /// In en, this message translates to:
  /// **'Last week'**
  String get timelineGroupWeek;

  /// Timeline section for the past month
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get timelineGroupMonth;

  /// Timeline section for everything before that
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get timelineGroupOlder;

  /// How many notes a collapsed section holds
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note} other{{count} notes}}'**
  String timelineGroupCount(int count);

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

  /// No description provided for @haptics.
  ///
  /// In en, this message translates to:
  /// **'Capture haptics'**
  String get haptics;

  /// No description provided for @intelligence.
  ///
  /// In en, this message translates to:
  /// **'Intelligence'**
  String get intelligence;

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
  /// **'Nex sends only the reminders and download notices you request. No engagement prompts or streaks.'**
  String get silenceBody;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @privacyBody.
  ///
  /// In en, this message translates to:
  /// **'Core capture and search do not collect or transmit your notes.'**
  String get privacyBody;

  /// No description provided for @shareDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Share diagnostics'**
  String get shareDiagnostics;

  /// No description provided for @shareDiagnosticsBody.
  ///
  /// In en, this message translates to:
  /// **'A local log of the last few crashes, in case something breaks. Nothing is sent anywhere unless you choose to share it here.'**
  String get shareDiagnosticsBody;

  /// No description provided for @noDiagnosticsYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing to share yet'**
  String get noDiagnosticsYet;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get openSourceLicenses;

  /// Settings row that opens the light/dark/system picker
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

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

  /// No description provided for @liquidGlass.
  ///
  /// In en, this message translates to:
  /// **'Liquid Glass'**
  String get liquidGlass;

  /// No description provided for @liquidGlassSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adaptive translucent controls with real background blur'**
  String get liquidGlassSubtitle;

  /// No description provided for @backgroundStyle.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get backgroundStyle;

  /// No description provided for @backgroundStyleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Minimal built-in patterns tuned for both light and dark themes'**
  String get backgroundStyleSubtitle;

  /// No description provided for @backgroundPlain.
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get backgroundPlain;

  /// No description provided for @backgroundAurora.
  ///
  /// In en, this message translates to:
  /// **'Aurora'**
  String get backgroundAurora;

  /// No description provided for @backgroundRipple.
  ///
  /// In en, this message translates to:
  /// **'Ripple'**
  String get backgroundRipple;

  /// No description provided for @backgroundWeave.
  ///
  /// In en, this message translates to:
  /// **'Weave'**
  String get backgroundWeave;

  /// Background preset: a sparse dot grid
  ///
  /// In en, this message translates to:
  /// **'Dots'**
  String get backgroundDots;

  /// Background preset: one accent wash rising off the bottom edge
  ///
  /// In en, this message translates to:
  /// **'Dusk'**
  String get backgroundDusk;

  /// Background preset: contour lines
  ///
  /// In en, this message translates to:
  /// **'Topography'**
  String get backgroundTopography;

  /// Background preset: wide diagonal bands of colour
  ///
  /// In en, this message translates to:
  /// **'Prism'**
  String get backgroundPrism;

  /// Settings row that opens the accent-colour picker
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColorSetting;

  /// Subtitle explaining what the accent colour affects
  ///
  /// In en, this message translates to:
  /// **'Recolors the caret, focus rings, and active states everywhere'**
  String get accentColorSettingSubtitle;

  /// Heading of the sheet used to pick the app's accent colour
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColorPickerTitle;

  /// No description provided for @uiScale.
  ///
  /// In en, this message translates to:
  /// **'Text & UI size'**
  String get uiScale;

  /// No description provided for @uiScaleSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get uiScaleSmall;

  /// No description provided for @uiScaleDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get uiScaleDefault;

  /// No description provided for @uiScaleLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get uiScaleLarge;

  /// No description provided for @uiScaleLarger.
  ///
  /// In en, this message translates to:
  /// **'Larger'**
  String get uiScaleLarger;

  /// No description provided for @enterSubmitsCapture.
  ///
  /// In en, this message translates to:
  /// **'Enter saves the note'**
  String get enterSubmitsCapture;

  /// No description provided for @enterSubmitsCaptureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Off starts a new line instead. Shift+Enter always starts a new line either way.'**
  String get enterSubmitsCaptureSubtitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

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

  /// No description provided for @saveToDevice.
  ///
  /// In en, this message translates to:
  /// **'Save to device'**
  String get saveToDevice;

  /// No description provided for @savedToDevice.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedToDevice;

  /// No description provided for @saveToDeviceFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the file'**
  String get saveToDeviceFailed;

  /// No description provided for @renameFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename file'**
  String get renameFileTitle;

  /// No description provided for @fileNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get fileNameEmpty;

  /// No description provided for @fileNameForbidden.
  ///
  /// In en, this message translates to:
  /// **'A name can\'t contain \\ / : * ? \" < > |'**
  String get fileNameForbidden;

  /// No description provided for @fileNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'That name is too long'**
  String get fileNameTooLong;

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
  /// **'Replace this library with the selected backup? A safety copy of the current library will be kept on this device before restoration.'**
  String get restoreBody;

  /// No description provided for @deleteBackup.
  ///
  /// In en, this message translates to:
  /// **'Delete backup'**
  String get deleteBackup;

  /// No description provided for @deleteBackupBody.
  ///
  /// In en, this message translates to:
  /// **'This local backup file will be deleted. It cannot be undone.'**
  String get deleteBackupBody;

  /// No description provided for @backupCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No backups} =1{1 backup} other{{count} backups}}'**
  String backupCount(int count);

  /// Banner when a sync attempt throws; the reason follows in brackets
  ///
  /// In en, this message translates to:
  /// **'Sync failed. Nothing on this device was changed.'**
  String get syncFailed;

  /// Banner when writing a local backup fails
  ///
  /// In en, this message translates to:
  /// **'The backup could not be written. Your notes were not changed.'**
  String get backupFailed;

  /// Banner when writing an export archive fails
  ///
  /// In en, this message translates to:
  /// **'The export could not be written. Your notes were not changed.'**
  String get exportFailed;

  /// Shown after a restore or import when a sync server is configured
  ///
  /// In en, this message translates to:
  /// **'Restored notes stay on this device — sync will not upload them.'**
  String get restoredStaysLocal;

  /// Banner when re-generating the daily recap fails; the old text stays on screen
  ///
  /// In en, this message translates to:
  /// **'The recap could not be refreshed. The one below is the last one Nex made.'**
  String get recapRefreshFailed;

  /// No description provided for @shareSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to Nex.'**
  String get shareSaved;

  /// Shown when a shared or picked file is over the attachment size limit
  ///
  /// In en, this message translates to:
  /// **'Nex keeps notes, not large files. “{name}” is {size}, and attachments are limited to {limit}.'**
  String shareTooLarge(Object name, Object size, Object limit);

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'The operation failed. Your existing notes were not changed.'**
  String get operationFailed;

  /// No description provided for @noteType.
  ///
  /// In en, this message translates to:
  /// **'{type, select, text{Text} voice{Voice} photo{Photo} file{File} checklist{Checklist} link{Link} other{Note}}'**
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

  /// Timeline filter row: show only notes with a reminder still ahead of them
  ///
  /// In en, this message translates to:
  /// **'Has a reminder'**
  String get filterHasReminder;

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

  /// Tooltip of the editor button that grows the sheet to fill the screen
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get editorFullScreen;

  /// Tooltip of the editor button that shrinks the full-screen editor back to a sheet
  ///
  /// In en, this message translates to:
  /// **'Smaller'**
  String get editorSmaller;

  /// Heading above the row of AI editing actions
  ///
  /// In en, this message translates to:
  /// **'Edit with AI'**
  String get aiEditTools;

  /// AI action that adds headings and bold without changing the words
  ///
  /// In en, this message translates to:
  /// **'Auto style'**
  String get aiEditAutoStyle;

  /// AI action that corrects spelling, grammar and punctuation only
  ///
  /// In en, this message translates to:
  /// **'Fix writing'**
  String get aiEditFix;

  /// AI action that rewrites the note formally
  ///
  /// In en, this message translates to:
  /// **'Formal'**
  String get aiEditFormal;

  /// AI action that rewrites the note warmly and plainly
  ///
  /// In en, this message translates to:
  /// **'Friendly'**
  String get aiEditFriendly;

  /// AI action that rewrites the note in fewer words
  ///
  /// In en, this message translates to:
  /// **'Shorter'**
  String get aiEditConcise;

  /// AI action that rewrites the note in plain language
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get aiEditSimple;

  /// Label of the bar offering to undo an AI edit
  ///
  /// In en, this message translates to:
  /// **'Edited by AI'**
  String get aiEditApplied;

  /// Button that puts the text back the way it was before the AI edit
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get aiEditUndo;

  /// Banner shown when an AI edit fails
  ///
  /// In en, this message translates to:
  /// **'That edit did not come back. Your text is unchanged.'**
  String get aiEditFailed;

  /// Banner shown when an AI edit returns the same text
  ///
  /// In en, this message translates to:
  /// **'Nothing to change — it already reads well.'**
  String get aiEditUnchanged;

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

  /// Detail-sheet action that pins this note to the top of the timeline
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// Detail-sheet action that releases the pinned note
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

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

  /// Detail line under the startup failure message
  ///
  /// In en, this message translates to:
  /// **'What went wrong: {error}'**
  String libraryOpenDetail(String error);

  /// Offered on the startup failure screen, before the app can open
  ///
  /// In en, this message translates to:
  /// **'If you have a backup file, restoring it here may recover your library.'**
  String get restoreBackupHint;

  /// Shown when restoring a local backup does not complete
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// Screen-reader label for the small dot marking a pending update
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailableBadge;

  /// Tooltip for a sheet's close button
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeLabel;

  /// Shown when the timeline's first read fails
  ///
  /// In en, this message translates to:
  /// **'Your timeline could not be loaded.'**
  String get timelineLoadFailed;

  /// Trash row subtitle: when the note was deleted
  ///
  /// In en, this message translates to:
  /// **'Deleted {when}'**
  String deletedWhen(String when);

  /// Timeline body when a filter matches nothing
  ///
  /// In en, this message translates to:
  /// **'Notes are hiding behind your filters.'**
  String get filteredEmpty;

  /// Drops the filters that hid every note
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// Title of the search filter sheet
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get searchFilters;

  /// Drops every active search filter
  ///
  /// In en, this message translates to:
  /// **'Clear all ({count})'**
  String searchFiltersClear(int count);

  /// Filter section heading: tags
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get searchFilterTags;

  /// Filter section heading: note types
  ///
  /// In en, this message translates to:
  /// **'Types'**
  String get searchFilterTypes;

  /// Filter section heading: when the note was added
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get searchFilterDates;

  /// Date filter: no date restriction
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get searchFilterAnyTime;

  /// Date filter: added today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get searchFilterToday;

  /// Date filter: last seven days
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get searchFilterLast7Days;

  /// Date filter: last thirty days
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get searchFilterLast30Days;

  /// Hint shown in the filter sheet before any filter is active
  ///
  /// In en, this message translates to:
  /// **'Tap to combine. Filters apply as you go.'**
  String get searchFiltersHint;

  /// Count of active filters, shown in the filter sheet
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String searchFiltersActive(int count);

  /// Tooltip for the filter button beside the search field
  ///
  /// In en, this message translates to:
  /// **'Show filters'**
  String get showFilters;

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

  /// About screen row opening the feedback sheet
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get sendFeedback;

  /// About screen: subtitle under Send feedback
  ///
  /// In en, this message translates to:
  /// **'Tell us what\'s working, or what isn\'t'**
  String get sendFeedbackSubtitle;

  /// Feedback sheet: text field hint
  ///
  /// In en, this message translates to:
  /// **'What\'s on your mind?'**
  String get feedbackHint;

  /// Feedback sheet: submit button
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get feedbackSend;

  /// Toast shown once feedback is delivered
  ///
  /// In en, this message translates to:
  /// **'Feedback sent — thank you'**
  String get feedbackSent;

  /// Toast shown when feedback is saved to retry later
  ///
  /// In en, this message translates to:
  /// **'No connection — this will send once you\'re back online'**
  String get feedbackQueuedOffline;

  /// Feedback sheet: inline error when the server rejected the message
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send that'**
  String get feedbackFailed;

  /// Feedback sheet: inline notice when no feedback server is configured
  ///
  /// In en, this message translates to:
  /// **'Feedback isn\'t available in this build yet'**
  String get feedbackUnavailable;

  /// Feedback sheet: fallback link when sending isn't possible
  ///
  /// In en, this message translates to:
  /// **'Open a GitHub issue instead'**
  String get feedbackOpenIssueInstead;

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

  /// Update screen when the app was installed by Cafe Bazaar
  ///
  /// In en, this message translates to:
  /// **'Nex was installed from Cafe Bazaar, so its updates come from Cafe Bazaar too.'**
  String get updatesFromBazaar;

  /// Update screen when the app was installed by Myket
  ///
  /// In en, this message translates to:
  /// **'Nex was installed from Myket, so its updates come from Myket too.'**
  String get updatesFromMyket;

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

  /// Shown when the installer download fails for any reason
  ///
  /// In en, this message translates to:
  /// **'The download did not finish. Check your connection and try again.'**
  String get updateDownloadFailed;

  /// Shown when the device runs out of storage mid-download
  ///
  /// In en, this message translates to:
  /// **'There is not enough free space to download the update.'**
  String get updateNoSpace;

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

  /// Heading above the inline changelog panel on the update sheet, shown regardless of update status
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get changelogTitle;

  /// Heading above the current (not-yet-numbered) section of the changelog panel
  ///
  /// In en, this message translates to:
  /// **'Latest changes'**
  String get changelogLatestHeading;

  /// Heading above one past release's notes in the changelog panel
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String changelogVersionHeading(String version);

  /// Changelog panel when the bundled CHANGELOG.md has nothing to show
  ///
  /// In en, this message translates to:
  /// **'Changelog unavailable.'**
  String get changelogEmpty;

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
  /// **'Exports notes, tags and attachments as JSON and Markdown in a ZIP. To preserve reminders, commitments and assistant memory too, share a library backup below.'**
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
  /// **'Nex backs up the library on this device. Local copies share unchanged media to save space; the listed size excludes shared files. Use Share beside a backup to keep a complete copy elsewhere, safe from losing the device.'**
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

  /// Card timestamp: updated under a minute ago
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get timeNow;

  /// Card timestamp: updated N minutes ago
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String timeMinutesAgo(int count);

  /// Card timestamp: updated N hours ago
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String timeHoursAgo(int count);

  /// Card timestamp: updated N days ago
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String timeDaysAgo(int count);

  /// Card timestamp: updated N weeks ago
  ///
  /// In en, this message translates to:
  /// **'{count}w'**
  String timeWeeksAgo(int count);

  /// Card timestamp: updated N months ago
  ///
  /// In en, this message translates to:
  /// **'{count}mo'**
  String timeMonthsAgo(int count);

  /// Card timestamp: updated N years ago
  ///
  /// In en, this message translates to:
  /// **'{count}y'**
  String timeYearsAgo(int count);

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

  /// Title of the crop screen shown right after taking or picking a photo
  ///
  /// In en, this message translates to:
  /// **'Crop photo'**
  String get cropPhotoTitle;

  /// Confirms the crop and saves the photo
  ///
  /// In en, this message translates to:
  /// **'Use photo'**
  String get cropConfirm;

  /// Crop screen: rotates the photo 90° clockwise
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get cropRotate;

  /// No description provided for @cropFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get cropFree;

  /// No description provided for @cropReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get cropReset;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @editPhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be opened or saved.'**
  String get editPhotoFailed;

  /// Crop screen: opens the optional annotate step
  ///
  /// In en, this message translates to:
  /// **'Draw or add text'**
  String get cropAnnotate;

  /// Cancels the whole photo capture, not just the crop
  ///
  /// In en, this message translates to:
  /// **'Discard photo'**
  String get cropCancel;

  /// Title of the annotate screen, reached from the crop screen
  ///
  /// In en, this message translates to:
  /// **'Draw or add text'**
  String get annotateTitle;

  /// Annotate screen: switches to freehand drawing mode
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get annotateDraw;

  /// Annotate screen: switches to text-placement mode
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get annotateText;

  /// Annotate screen: placeholder in the text-entry dialog
  ///
  /// In en, this message translates to:
  /// **'Type something…'**
  String get annotateTextHint;

  /// Annotate screen: removes the last stroke or text label
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get annotateUndo;

  /// Annotate screen: removes every stroke and text label
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get annotateClear;

  /// Annotate screen: bakes the annotations into the photo and returns
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get annotateDone;

  /// Annotate screen: hint shown while in text-placement mode
  ///
  /// In en, this message translates to:
  /// **'Tap anywhere on the photo to place text'**
  String get annotateTapToPlaceText;

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
  /// **'Brightness'**
  String get brightness;

  /// The tag carries no accent
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get noColor;

  /// The colour picker's escape hatch when the thing being coloured always has one — choosing it restores the shipped accent
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultColor;

  /// Heading above the row of colours picked before
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get recentColors;

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

  /// That a weak cloud model gives weak results
  ///
  /// In en, this message translates to:
  /// **'How good the assistant, the summary and everything else are depends entirely on the model you choose. Larger models are more accurate; small or free ones are cheaper and faster, but weaker — they summarise poorly and follow instructions loosely.'**
  String get modelChoiceHint;

  /// Button that verifies the configuration
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get testConnection;

  /// Subtitle for the on-device option once a local model is installed.
  ///
  /// In en, this message translates to:
  /// **'Answers on this phone, from the model you downloaded.'**
  String get aiProviderNoneSubtitleLocal;

  /// Explains what the local model does and does not cover.
  ///
  /// In en, this message translates to:
  /// **'The model on your phone writes and reads text, so it covers the assistant, the daily recap and translation. It cannot hear a recording or read a photo — those still need a provider.'**
  String get aiProviderLocalNote;

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
  /// **'The key is kept in this device\'s own secure storage, not in the app\'s ordinary settings, and it is never sent anywhere except to the provider you chose.'**
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
  /// **'Everything stays on this device. No note is sent to any AI service, and no note leaves the app.'**
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

  /// Chat screen title and its Settings row title
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// Settings row subtitle for Chat
  ///
  /// In en, this message translates to:
  /// **'Ask Nex\'s built-in assistant'**
  String get chatSubtitle;

  /// Shown when no ChatAdapter is bound (Phase 1)
  ///
  /// In en, this message translates to:
  /// **'Local chat isn\'t available on this build yet.'**
  String get chatUnavailable;

  /// Shown above the message field before the first message
  ///
  /// In en, this message translates to:
  /// **'Ask anything — Nex answers on this device, with no internet needed.'**
  String get chatEmptyHint;

  /// Chat text field placeholder
  ///
  /// In en, this message translates to:
  /// **'Message…'**
  String get chatInputHint;

  /// Send button tooltip
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSendTooltip;

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

  /// Header of the AI day summary card on the timeline
  ///
  /// In en, this message translates to:
  /// **'Smart summary'**
  String get aiDaySummaryTitle;

  /// Screen-reader label for the AI-generated day summary panel on the timeline
  ///
  /// In en, this message translates to:
  /// **'Today\'s summary'**
  String get aiDaySummarySemanticLabel;

  /// Shown in the day summary card when no summary could be generated
  ///
  /// In en, this message translates to:
  /// **'Nothing to sum up yet.'**
  String get aiDaySummaryEmpty;

  /// Tooltip on the day summary card's refresh button
  ///
  /// In en, this message translates to:
  /// **'Write a new summary'**
  String get aiDaySummaryRefresh;

  /// Tooltip on the day summary card's chevron while the card is open
  ///
  /// In en, this message translates to:
  /// **'Hide the summary'**
  String get aiDaySummaryCollapse;

  /// Tooltip on the day summary card's chevron while the card is collapsed
  ///
  /// In en, this message translates to:
  /// **'Show the summary'**
  String get aiDaySummaryExpand;

  /// Screen-reader label for the tappable AI-generated headline at the top of the timeline
  ///
  /// In en, this message translates to:
  /// **'Hold for a new greeting'**
  String get aiHeadlineRefresh;

  /// Settings row choosing which language the AI writes in
  ///
  /// In en, this message translates to:
  /// **'AI output language'**
  String get aiOutputLanguage;

  /// Explanation under the AI output language setting
  ///
  /// In en, this message translates to:
  /// **'The language summaries and suggestions come back in'**
  String get aiOutputLanguageSubtitle;

  /// AI output language option: follow whatever language the note is written in
  ///
  /// In en, this message translates to:
  /// **'Match my notes'**
  String get aiOutputLanguageAuto;

  /// AI output language option: always English
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get aiOutputLanguageEnglish;

  /// AI output language option: always Persian
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get aiOutputLanguagePersian;

  /// Onboarding button that advances to the next page
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Onboarding button that jumps ahead to the setup page
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// Onboarding button that returns to the previous page
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// Onboarding button on the last page that finishes setup
  ///
  /// In en, this message translates to:
  /// **'Start using Nex'**
  String get onboardingStart;

  /// Onboarding page 1 heading
  ///
  /// In en, this message translates to:
  /// **'Somewhere to put it down'**
  String get onboardingWelcomeTitle;

  /// Onboarding page 1 body
  ///
  /// In en, this message translates to:
  /// **'Anything you put in Nex is kept. Nothing else is asked of you — no account, no inbox to clear, nothing to keep up with.'**
  String get onboardingWelcomeBody;

  /// Onboarding page 2 heading
  ///
  /// In en, this message translates to:
  /// **'There is no Save button'**
  String get onboardingCaptureTitle;

  /// Onboarding page 2 body
  ///
  /// In en, this message translates to:
  /// **'Type it, say it, or photograph it. A note is yours the moment you make it, and it goes to the top of one list — no folders to file it into first.'**
  String get onboardingCaptureBody;

  /// Onboarding page 3 heading
  ///
  /// In en, this message translates to:
  /// **'It can read what you capture'**
  String get onboardingIntelligenceTitle;

  /// Onboarding page 3 body
  ///
  /// In en, this message translates to:
  /// **'Voice becomes text, photos give up their words, and tags suggest themselves. This part is off until you add a provider in Settings — everything else works without it.'**
  String get onboardingIntelligenceBody;

  /// Onboarding page 4 heading
  ///
  /// In en, this message translates to:
  /// **'It will never interrupt you'**
  String get onboardingSilenceTitle;

  /// Onboarding page 4 body
  ///
  /// In en, this message translates to:
  /// **'Reminders are optional. No engagement prompts or streaks. Cloud AI and syncing send data only when you configure and use them.'**
  String get onboardingSilenceBody;

  /// Onboarding page 5 heading
  ///
  /// In en, this message translates to:
  /// **'A few quick choices'**
  String get onboardingSetupTitle;

  /// Onboarding page 5 body
  ///
  /// In en, this message translates to:
  /// **'All of these live in Settings afterwards, and none of them are permanent.'**
  String get onboardingSetupBody;

  /// Validation message under the required name field on the last onboarding page
  ///
  /// In en, this message translates to:
  /// **'Nex needs something to call you.'**
  String get onboardingNameRequired;

  /// Capture type: a list of tickable items
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get checklist;

  /// Capture type: a saved web address
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get link;

  /// Placeholder in the checklist capture field
  ///
  /// In en, this message translates to:
  /// **'An item, one per line'**
  String get checklistHint;

  /// Placeholder in the link capture field
  ///
  /// In en, this message translates to:
  /// **'Paste a link'**
  String get linkHint;

  /// Shown when pasted text cannot be read as a URL
  ///
  /// In en, this message translates to:
  /// **'That does not look like a link.'**
  String get linkNotValid;

  /// Action that opens a link note in the browser
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get openLink;

  /// How many checklist items are ticked
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String checklistProgress(int done, int total);

  /// What the assistant sheet says before anything is typed — a description of the box, not a greeting
  ///
  /// In en, this message translates to:
  /// **'Ask about your notes'**
  String get chatGreeting;

  /// Placeholder in the assistant's input field
  ///
  /// In en, this message translates to:
  /// **'Enter a prompt here'**
  String get chatHint;

  /// Settings row that imports another app's export
  ///
  /// In en, this message translates to:
  /// **'Import notes'**
  String get foreignImportTitle;

  /// Explains what the import row accepts
  ///
  /// In en, this message translates to:
  /// **'From Google Keep, or any folder of .md and .txt files'**
  String get foreignImportSubtitle;

  /// Shown while an import is running
  ///
  /// In en, this message translates to:
  /// **'Reading your export…'**
  String get foreignImportWorking;

  /// How many notes an import brought in
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No notes found in that file.} =1{1 note imported.} other{{count} notes imported.}}'**
  String foreignImportDone(int count);

  /// Shown when a picked file held nothing importable
  ///
  /// In en, this message translates to:
  /// **'Nex could not read that file. Pick the .zip you downloaded, or a .json, .md or .txt file.'**
  String get foreignImportUnreadable;

  /// Pauses the download, keeping what has arrived
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get localModelPause;

  /// Continues a paused download
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get localModelResume;

  /// Stops the download and discards what has arrived
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get localModelStop;

  /// Paused state with byte counts
  ///
  /// In en, this message translates to:
  /// **'Paused · {done} of {total}'**
  String localModelPaused(String done, String total);

  /// Downloaded so far against the whole model
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String localModelBytes(String done, String total);

  /// Shown while the runtime loads the weights
  ///
  /// In en, this message translates to:
  /// **'Starting the model up…'**
  String get localModelLoading;

  /// Confirm discarding a partial download
  ///
  /// In en, this message translates to:
  /// **'Stop the download?'**
  String get localModelStopTitle;

  /// Explains the cost of stopping rather than pausing
  ///
  /// In en, this message translates to:
  /// **'What has downloaded so far is thrown away, and starting again begins from the beginning. Pause keeps it instead.'**
  String get localModelStopBody;

  /// Model row state when installed
  ///
  /// In en, this message translates to:
  /// **'Downloaded and ready on this phone'**
  String get localModelManageInstalled;

  /// Model row state when not installed
  ///
  /// In en, this message translates to:
  /// **'Not downloaded yet — the assistant needs it to work offline'**
  String get localModelManageMissing;

  /// Shown when the runtime cannot load the weights
  ///
  /// In en, this message translates to:
  /// **'The model is downloaded but would not start on this phone.'**
  String get localModelLoadFailed;

  /// Label above the verbatim runtime error
  ///
  /// In en, this message translates to:
  /// **'What the runtime reported:'**
  String get localModelLoadFailedDetail;

  /// Screen for downloading the local AI model
  ///
  /// In en, this message translates to:
  /// **'On-device model'**
  String get localModelTitle;

  /// Settings row subtitle for the local model
  ///
  /// In en, this message translates to:
  /// **'Chat with no internet, once the model is downloaded'**
  String get localModelSubtitle;

  /// What the on-device model is
  ///
  /// In en, this message translates to:
  /// **'Nex can run a language model on this phone, so chat works with no internet and nothing you type leaves the device. It is a large download and it stays on your phone until you remove it.'**
  String get localModelExplained;

  /// That the on-device chat model is weaker than a cloud model
  ///
  /// In en, this message translates to:
  /// **'A model on the phone is small, and it never reaches the quality of a cloud model: it does well with simple requests, but with complex questions or many notes it can get things wrong or leave things out.'**
  String get localModelQualityCaveat;

  /// That the on-device model's speed depends on the phone
  ///
  /// In en, this message translates to:
  /// **'It runs on this phone\'s own processor, so how well it works depends on the phone. On an older or slower device the replies come slowly, and on one short of memory the model may not start at all.'**
  String get localModelDeviceCaveat;

  /// Button that starts the model download
  ///
  /// In en, this message translates to:
  /// **'Download · {size} GB'**
  String localModelDownload(String size);

  /// Generic download progress label
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get localModelDownloading;

  /// Which piece of the model is downloading
  ///
  /// In en, this message translates to:
  /// **'Downloading part {index} of {count}'**
  String localModelDownloadingPart(int index, int count);

  /// Shown while parts are joined and verified
  ///
  /// In en, this message translates to:
  /// **'Putting the pieces together and checking them…'**
  String get localModelJoining;

  /// What happens if the user navigates away
  ///
  /// In en, this message translates to:
  /// **'You can leave this screen — the download keeps going. Closing the app stops it, and it picks up where it left off.'**
  String get localModelKeepOpen;

  /// Install finished
  ///
  /// In en, this message translates to:
  /// **'The model is ready. Chat works offline now.'**
  String get localModelReady;

  /// Install failed and is resumable
  ///
  /// In en, this message translates to:
  /// **'That download did not finish. Try again — it carries on from where it stopped.'**
  String get localModelFailed;

  /// The model is present
  ///
  /// In en, this message translates to:
  /// **'Installed · {size} GB on this phone'**
  String localModelInstalled(String size);

  /// Button that deletes the model
  ///
  /// In en, this message translates to:
  /// **'Remove the model'**
  String get localModelDelete;

  /// Delete confirmation title
  ///
  /// In en, this message translates to:
  /// **'Remove the model?'**
  String get localModelDeleteTitle;

  /// Delete confirmation body
  ///
  /// In en, this message translates to:
  /// **'Offline chat stops working until you download it again. Your notes are not affected.'**
  String get localModelDeleteBody;

  /// Delete finished
  ///
  /// In en, this message translates to:
  /// **'The model was removed.'**
  String get localModelDeleted;

  /// Heading above the model licence
  ///
  /// In en, this message translates to:
  /// **'Before you download'**
  String get localModelLicenseTitle;

  /// Opens the model licence in a browser
  ///
  /// In en, this message translates to:
  /// **'Read the full terms'**
  String get localModelLicenseRead;

  /// Licence acceptance checkbox
  ///
  /// In en, this message translates to:
  /// **'I have read and accept these terms'**
  String get localModelLicenseAccept;

  /// Unsupported platform
  ///
  /// In en, this message translates to:
  /// **'On-device chat runs on Android and iPhone. This build cannot use it.'**
  String get localModelBlockedPlatform;

  /// Unsupported CPU architecture
  ///
  /// In en, this message translates to:
  /// **'This phone\'s processor is not one the model runs on. It needs a 64-bit ARM device.'**
  String get localModelBlockedArchitecture;

  /// Not enough storage
  ///
  /// In en, this message translates to:
  /// **'There is not enough free space. The download needs about {size} GB free while it installs.'**
  String localModelBlockedStorage(String size);

  /// Model not published yet
  ///
  /// In en, this message translates to:
  /// **'No model is available to download in this version yet.'**
  String get localModelBlockedUnpublished;

  /// Advances the first-run tour
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get tourNext;

  /// Finishes the first-run tour
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get tourDone;

  /// Leaves the first-run tour early
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get tourSkip;

  /// Tour step pointing at the capture button
  ///
  /// In en, this message translates to:
  /// **'Everything starts here'**
  String get tourCaptureTitle;

  /// Tour step body for the capture button
  ///
  /// In en, this message translates to:
  /// **'Tap to write a note, or record, photograph and attach one. Hold it to ask the assistant instead.'**
  String get tourCaptureBody;

  /// Tour step pointing at the search field
  ///
  /// In en, this message translates to:
  /// **'Find anything'**
  String get tourSearchTitle;

  /// Tour step body for the search field
  ///
  /// In en, this message translates to:
  /// **'Search by word, or by what a note meant. Try tag:work or type:link to narrow it down.'**
  String get tourSearchBody;

  /// Tour step pointing at the library button
  ///
  /// In en, this message translates to:
  /// **'Tags and deleted notes'**
  String get tourLibraryTitle;

  /// Tour step body for the library button
  ///
  /// In en, this message translates to:
  /// **'Your tags live here, and so does anything you deleted — for a while.'**
  String get tourLibraryBody;

  /// Tour step pointing at the settings button
  ///
  /// In en, this message translates to:
  /// **'Make it yours'**
  String get tourSettingsTitle;

  /// Tour step body for the settings button
  ///
  /// In en, this message translates to:
  /// **'Your name, theme, language, backups, and the AI provider that writes your summaries.'**
  String get tourSettingsBody;

  /// Tour step about gestures on a note card
  ///
  /// In en, this message translates to:
  /// **'One more thing'**
  String get tourCardsTitle;

  /// Tour step body about gestures on a note card
  ///
  /// In en, this message translates to:
  /// **'Swipe a note from either edge for its quick actions. Each edge is yours to set in Settings.'**
  String get tourCardsBody;

  /// Note action that translates the note's text
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get translate;

  /// Label above the target-language picker
  ///
  /// In en, this message translates to:
  /// **'Into'**
  String get translateTo;

  /// Shown while a translation is in flight
  ///
  /// In en, this message translates to:
  /// **'Translating…'**
  String get translateWorking;

  /// Shown when a translation request failed or returned nothing
  ///
  /// In en, this message translates to:
  /// **'The translation did not come back.'**
  String get translateFailed;

  /// Button that saves the translation as a new note
  ///
  /// In en, this message translates to:
  /// **'Keep as a note'**
  String get translateSaveAsNote;

  /// Confirmation after a translation is kept
  ///
  /// In en, this message translates to:
  /// **'Saved as a new note.'**
  String get translateSaved;

  /// Tooltip on the chat's microphone button
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get chatSpeak;

  /// Shown while a chat recording is being turned into text
  ///
  /// In en, this message translates to:
  /// **'Reading your recording…'**
  String get chatTranscribing;

  /// Shown when a chat recording produced no text
  ///
  /// In en, this message translates to:
  /// **'Nothing came back from that recording.'**
  String get chatTranscribeFailed;

  /// Tooltip on the assistant's send button
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// Shown in the assistant thread when a reply does not arrive
  ///
  /// In en, this message translates to:
  /// **'No answer came back. Your message is kept; try again.'**
  String get chatFailed;

  /// Suggested opening prompt
  ///
  /// In en, this message translates to:
  /// **'Summarise what I captured this week'**
  String get chatPromptSummarise;

  /// Suggested opening prompt
  ///
  /// In en, this message translates to:
  /// **'Turn my notes into a to-do list'**
  String get chatPromptPlan;

  /// Suggested opening prompt
  ///
  /// In en, this message translates to:
  /// **'Suggest what I might be forgetting'**
  String get chatPromptIdeas;

  /// Shown after the assistant's confirmed action succeeds
  ///
  /// In en, this message translates to:
  /// **'Done.'**
  String get assistantActionDone;

  /// No description provided for @assistantActionPartlyDone.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} changes were made before one failed. Check the notes before asking again.'**
  String assistantActionPartlyDone(int done, int total);

  /// Shown when the assistant's confirmed action fails
  ///
  /// In en, this message translates to:
  /// **'That didn\'t work.'**
  String get assistantActionFailed;

  /// Confirmation for an assistant-proposed new note
  ///
  /// In en, this message translates to:
  /// **'Save this as a new note?'**
  String get assistantConfirmCreate;

  /// Confirmation for an assistant-proposed edit
  ///
  /// In en, this message translates to:
  /// **'Replace this note\'s text?'**
  String get assistantConfirmEdit;

  /// Confirmation for an assistant-proposed delete
  ///
  /// In en, this message translates to:
  /// **'Move this note to Recently Deleted?'**
  String get assistantConfirmDelete;

  /// Confirmation for an assistant-proposed tag change
  ///
  /// In en, this message translates to:
  /// **'Change this note\'s tags?'**
  String get assistantConfirmTags;

  /// Button that carries out the assistant's proposed action
  ///
  /// In en, this message translates to:
  /// **'Do it'**
  String get assistantApply;

  /// Header line when the chat is scoped to one note
  ///
  /// In en, this message translates to:
  /// **'About: {note}'**
  String chatAboutNote(String note);

  /// Title of the saved assistant conversations list
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get chatHistory;

  /// Empty state for the conversation list
  ///
  /// In en, this message translates to:
  /// **'No saved conversations yet.'**
  String get chatHistoryEmpty;

  /// Starts a fresh assistant conversation
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get chatNewConversation;

  /// No description provided for @chatClearHistoryBody.
  ///
  /// In en, this message translates to:
  /// **'Delete every conversation? They cannot be brought back; your notes are not touched.'**
  String get chatClearHistoryBody;

  /// Clears the assistant's saved history
  ///
  /// In en, this message translates to:
  /// **'Delete all conversations'**
  String get chatClearHistory;

  /// Settings row opening the assistant's own settings
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get assistant;

  /// Shown when the assistant button is tapped while no provider is configured to answer.
  ///
  /// In en, this message translates to:
  /// **'The assistant needs intelligence turned on.'**
  String get assistantNeedsIntelligence;

  /// Action on that notice: opens the intelligence settings.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get assistantTurnOnIntelligence;

  /// Subtitle of the assistant settings row
  ///
  /// In en, this message translates to:
  /// **'Your profile, response style, and what it can see'**
  String get assistantSubtitle;

  /// How far the assistant may wander from the plainest answer
  ///
  /// In en, this message translates to:
  /// **'Creativity'**
  String get assistantCreativity;

  /// Lowest creativity setting
  ///
  /// In en, this message translates to:
  /// **'Precise'**
  String get assistantCreativityPrecise;

  /// Middle creativity setting
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get assistantCreativityBalanced;

  /// Highest creativity setting
  ///
  /// In en, this message translates to:
  /// **'Inventive'**
  String get assistantCreativityInventive;

  /// How long the assistant's answers may be
  ///
  /// In en, this message translates to:
  /// **'Answer length'**
  String get assistantLength;

  /// Shortest answer length
  ///
  /// In en, this message translates to:
  /// **'Brief'**
  String get assistantLengthBrief;

  /// Middle answer length
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get assistantLengthStandard;

  /// Longest answer length
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get assistantLengthFull;

  /// Switch limiting the assistant to the notes and the app
  ///
  /// In en, this message translates to:
  /// **'Stay in my notes'**
  String get assistantScope;

  /// Explains the notes-only switch
  ///
  /// In en, this message translates to:
  /// **'Off, it will answer anything — including things it is bad at.'**
  String get assistantScopeSubtitle;

  /// Free-text standing instruction for the assistant
  ///
  /// In en, this message translates to:
  /// **'How it should answer'**
  String get assistantInstruction;

  /// Placeholder example for the assistant instruction field
  ///
  /// In en, this message translates to:
  /// **'Answer with a bit of humour'**
  String get assistantInstructionHint;

  /// Explains the assistant instruction field
  ///
  /// In en, this message translates to:
  /// **'Your own note to the assistant, sent with every question. It changes the tone, not what it is allowed to do.'**
  String get assistantInstructionSubtitle;

  /// How many recent notes are sent with each question
  ///
  /// In en, this message translates to:
  /// **'Notes it can see'**
  String get assistantContext;

  /// Warning under the assistant's context-size choice
  ///
  /// In en, this message translates to:
  /// **'Sending 100 notes or more makes every question slower — the model reads all of them before it answers. On the on-device model it is very noticeable.'**
  String get assistantContextSlow;

  /// Zero notes shared with the assistant
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get assistantContextNone;

  /// How many recent notes are shared
  ///
  /// In en, this message translates to:
  /// **'Last {count}'**
  String assistantContextCount(int count);

  /// Opens the assistant with this one note as its subject
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get askAboutNote;

  /// Keeps the current search for later
  ///
  /// In en, this message translates to:
  /// **'Save this search'**
  String get saveSearch;

  /// Heading above the list of kept searches
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedSearches;

  /// Confirmation for merging notes
  ///
  /// In en, this message translates to:
  /// **'Combine these notes into one?'**
  String get assistantConfirmMerge;

  /// Confirmation for the assistant adding notes to a thread, which it starts when there is none of that name
  ///
  /// In en, this message translates to:
  /// **'Add these notes to a thread?'**
  String get assistantConfirmThread;

  /// Confirmation for converting a note to a checklist
  ///
  /// In en, this message translates to:
  /// **'Turn this into a checklist?'**
  String get assistantConfirmChecklist;

  /// Confirmation for ticking a checklist item
  ///
  /// In en, this message translates to:
  /// **'Tick this item off?'**
  String get assistantConfirmCheck;

  /// The confirmation for the assistant removing the tick from a checklist item.
  ///
  /// In en, this message translates to:
  /// **'Untick this item?'**
  String get assistantConfirmUncheck;

  /// Confirmation for an assistant-proposed recurring item
  ///
  /// In en, this message translates to:
  /// **'Set up this recurring item?'**
  String get assistantConfirmCommitment;

  /// Confirmation for ticking a recurring item off
  ///
  /// In en, this message translates to:
  /// **'Mark this done and roll it forward?'**
  String get assistantConfirmCommitmentMet;

  /// Confirmation for deleting a recurring item
  ///
  /// In en, this message translates to:
  /// **'Remove this recurring item?'**
  String get assistantConfirmCommitmentDelete;

  /// Switch: whether a recurring item sends a notification
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get commitmentNotify;

  /// Notification switch, on
  ///
  /// In en, this message translates to:
  /// **'A notification when it falls due'**
  String get commitmentNotifyOn;

  /// Notification switch, off
  ///
  /// In en, this message translates to:
  /// **'Only in the digest and on this screen'**
  String get commitmentNotifyOff;

  /// Title of the recurring-obligations screen
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get commitmentsTitle;

  /// Settings row subtitle
  ///
  /// In en, this message translates to:
  /// **'Bills, renewals, medication — things that come back round'**
  String get commitmentsSubtitle;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'Nothing recurring yet.\nInsurance, rent, a tablet every eight hours.'**
  String get commitmentsEmpty;

  /// Add button
  ///
  /// In en, this message translates to:
  /// **'Add a recurring item'**
  String get commitmentAdd;

  /// Editor title
  ///
  /// In en, this message translates to:
  /// **'Edit recurring item'**
  String get commitmentEdit;

  /// Delete confirmation
  ///
  /// In en, this message translates to:
  /// **'Delete this recurring item?'**
  String get commitmentDeleteTitle;

  /// Mark-met button
  ///
  /// In en, this message translates to:
  /// **'Done — roll it forward'**
  String get commitmentMarkMet;

  /// Paused state
  ///
  /// In en, this message translates to:
  /// **'paused'**
  String get commitmentPaused;

  /// Title field label
  ///
  /// In en, this message translates to:
  /// **'What'**
  String get commitmentTitleLabel;

  /// Title field hint
  ///
  /// In en, this message translates to:
  /// **'Car insurance'**
  String get commitmentTitleHint;

  /// Cadence field label
  ///
  /// In en, this message translates to:
  /// **'How often'**
  String get commitmentEvery;

  /// Cadence count label
  ///
  /// In en, this message translates to:
  /// **'Every'**
  String get commitmentCount;

  /// Due date row
  ///
  /// In en, this message translates to:
  /// **'Next time'**
  String get commitmentNextDue;

  /// Lead time row
  ///
  /// In en, this message translates to:
  /// **'Tell me ahead of time'**
  String get commitmentLead;

  /// Lead time: follow the cadence
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get commitmentAuto;

  /// Lead time: zero
  ///
  /// In en, this message translates to:
  /// **'When it is due'**
  String get commitmentLeadNone;

  /// Waking window switch
  ///
  /// In en, this message translates to:
  /// **'Only during these hours'**
  String get commitmentWindow;

  /// Waking window off
  ///
  /// In en, this message translates to:
  /// **'Any hour, including while you sleep'**
  String get commitmentWindowOff;

  /// Window start
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get commitmentWindowFrom;

  /// Window end
  ///
  /// In en, this message translates to:
  /// **'Until'**
  String get commitmentWindowTo;

  /// How many times an hourly item has been done today
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} today'**
  String commitmentTally(int done, int total);

  /// Time until due
  ///
  /// In en, this message translates to:
  /// **'due in {span}'**
  String commitmentDueIn(String span);

  /// Time past due
  ///
  /// In en, this message translates to:
  /// **'{span} overdue'**
  String commitmentOverdue(String span);

  /// Lead time following the cadence
  ///
  /// In en, this message translates to:
  /// **'Automatic ({span})'**
  String commitmentLeadAuto(String span);

  /// Hourly cadence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{every hour} other{every {count} hours}}'**
  String cadenceHours(int count);

  /// Daily cadence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{every day} other{every {count} days}}'**
  String cadenceDays(int count);

  /// Weekly cadence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{every week} other{every {count} weeks}}'**
  String cadenceWeeks(int count);

  /// Monthly cadence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{every month} other{every {count} months}}'**
  String cadenceMonths(int count);

  /// Yearly cadence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{every year} other{every {count} years}}'**
  String cadenceYears(int count);

  /// A span in minutes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String spanMinutes(int count);

  /// A span in hours
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String spanHours(int count);

  /// A span in days
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String spanDays(int count);

  /// A span in months
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 month} other{{count} months}}'**
  String spanMonths(int count);

  /// Confirmation for an assistant-proposed settings change
  ///
  /// In en, this message translates to:
  /// **'Change this setting?'**
  String get assistantConfirmSetting;

  /// No description provided for @briefEnabled.
  ///
  /// In en, this message translates to:
  /// **'Show the smart summary'**
  String get briefEnabled;

  /// No description provided for @briefEnabledOn.
  ///
  /// In en, this message translates to:
  /// **'Written for you each day on the timeline.'**
  String get briefEnabledOn;

  /// No description provided for @briefEnabledOff.
  ///
  /// In en, this message translates to:
  /// **'Off: no summary is written and nothing is sent to a provider for it.'**
  String get briefEnabledOff;

  /// Title of the sheet that configures the card at the top of the timeline.
  ///
  /// In en, this message translates to:
  /// **'Smart summary'**
  String get briefTitle;

  /// Subtitle under the daily-brief sheet's title.
  ///
  /// In en, this message translates to:
  /// **'The card above your notes. You choose what it is for.'**
  String get briefSubtitle;

  /// Label above the five brief presets.
  ///
  /// In en, this message translates to:
  /// **'What it writes'**
  String get briefStyleLabel;

  /// Brief preset: the model writes the whole thing.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get briefStyleAssistant;

  /// What the assistant brief preset does.
  ///
  /// In en, this message translates to:
  /// **'The model reads your notes and writes the brief.'**
  String get briefStyleAssistantAbout;

  /// Brief preset: app states facts, model adds one line.
  ///
  /// In en, this message translates to:
  /// **'Facts, plus one observation'**
  String get briefStyleBlended;

  /// What the blended brief preset does.
  ///
  /// In en, this message translates to:
  /// **'Nex states what is due, exactly. The model adds the one thing only the whole set shows.'**
  String get briefStyleBlendedAbout;

  /// Brief preset: no model at all.
  ///
  /// In en, this message translates to:
  /// **'Plain report'**
  String get briefStyleReport;

  /// What the plain-report brief preset does.
  ///
  /// In en, this message translates to:
  /// **'What has slipped, what is due, what is half-done. Nothing is sent anywhere.'**
  String get briefStyleReportAbout;

  /// Brief preset: app states facts, model suggests a next step.
  ///
  /// In en, this message translates to:
  /// **'Planner'**
  String get briefStylePlanner;

  /// What the planner brief preset does.
  ///
  /// In en, this message translates to:
  /// **'The same facts, and one suggestion for what to do next — a suggestion only, nothing is changed.'**
  String get briefStylePlannerAbout;

  /// Brief preset: the user writes the instruction.
  ///
  /// In en, this message translates to:
  /// **'My own brief'**
  String get briefStyleCustom;

  /// What the custom brief preset does.
  ///
  /// In en, this message translates to:
  /// **'You describe what you want it to tell you.'**
  String get briefStyleCustomAbout;

  /// Note shown when the plain-report preset is selected.
  ///
  /// In en, this message translates to:
  /// **'Works with no provider, no key and no signal.'**
  String get briefOffline;

  /// Note shown when a preset that needs a model is selected while AI is off.
  ///
  /// In en, this message translates to:
  /// **'This one needs intelligence switched on. Plain report is the one that works without it.'**
  String get briefNeedsAi;

  /// Label for the custom brief instruction field.
  ///
  /// In en, this message translates to:
  /// **'What you want it to say'**
  String get briefInstructionLabel;

  /// Placeholder for the custom brief instruction field.
  ///
  /// In en, this message translates to:
  /// **'Only what is overdue. No greeting.'**
  String get briefInstructionHint;

  /// Note under the brief's language picker saying the setting is not the brief's alone.
  ///
  /// In en, this message translates to:
  /// **'One setting, shared: it is also what the assistant answers in and what transcriptions and summaries come back in.'**
  String get briefLanguageShared;

  /// Label above the brief's tone presets.
  ///
  /// In en, this message translates to:
  /// **'How it sounds'**
  String get briefToneLabel;

  /// Label above the brief's length presets.
  ///
  /// In en, this message translates to:
  /// **'How much of it'**
  String get briefLengthLabel;

  /// A brief line for something past its date.
  ///
  /// In en, this message translates to:
  /// **'{title} — {span} overdue'**
  String briefLineOverdue(String title, String span);

  /// A brief line for something falling due.
  ///
  /// In en, this message translates to:
  /// **'{title} — due in {span}'**
  String briefLineDue(String title, String span);

  /// A brief line for a checklist with items unticked.
  ///
  /// In en, this message translates to:
  /// **'{title} — {remaining} of {total} left'**
  String briefLineChecklist(String title, int remaining, int total);

  /// The paragraph under the title on the recurring sheet, explaining what a recurring item actually does.
  ///
  /// In en, this message translates to:
  /// **'Nex keeps the next date for each one, brings it up in the daily brief, and can send a notification before it falls due.'**
  String get commitmentsAbout;

  /// Heading above the recurring items whose date has passed.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get commitmentsOverdue;

  /// Heading above the recurring items still ahead of their date.
  ///
  /// In en, this message translates to:
  /// **'Coming up'**
  String get commitmentsComingUp;

  /// Heading above the recurring items that are paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get commitmentsRested;

  /// How many recurring items there are, shown beside the title.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recurring item} other{{count} recurring items}}'**
  String commitmentsCount(int count);

  /// Confirmation for an assistant-proposed reminder
  ///
  /// In en, this message translates to:
  /// **'Set this reminder?'**
  String get assistantConfirmRemind;

  /// Confirmation for clearing a reminder
  ///
  /// In en, this message translates to:
  /// **'Stop this note reminding you?'**
  String get assistantConfirmRemindClear;

  /// Confirmation for pinning a note
  ///
  /// In en, this message translates to:
  /// **'Pin this note to the top?'**
  String get assistantConfirmPin;

  /// Confirmation for unpinning a note
  ///
  /// In en, this message translates to:
  /// **'Unpin this note?'**
  String get assistantConfirmUnpin;

  /// Confirmation for setting a note's title
  ///
  /// In en, this message translates to:
  /// **'Give this note a title?'**
  String get assistantConfirmTitle;

  /// Confirmation for clearing a note's title
  ///
  /// In en, this message translates to:
  /// **'Remove this note\'s title?'**
  String get assistantConfirmTitleClear;

  /// Confirmation for restoring a deleted note
  ///
  /// In en, this message translates to:
  /// **'Bring this note back from Recently Deleted?'**
  String get assistantConfirmRestore;

  /// Confirmation for renaming a tag
  ///
  /// In en, this message translates to:
  /// **'Rename this tag everywhere it is used?'**
  String get assistantConfirmRenameTag;

  /// Confirmation for changing a tag's colour
  ///
  /// In en, this message translates to:
  /// **'Change this tag\'s colour?'**
  String get assistantConfirmTagColor;

  /// Note action that sets a reminder
  ///
  /// In en, this message translates to:
  /// **'Remind'**
  String get remind;

  /// Reminder in one hour
  ///
  /// In en, this message translates to:
  /// **'In an hour'**
  String get remindLater;

  /// Reminder at 8pm today
  ///
  /// In en, this message translates to:
  /// **'This evening'**
  String get remindEvening;

  /// Reminder at 9am tomorrow
  ///
  /// In en, this message translates to:
  /// **'Tomorrow morning'**
  String get remindTomorrow;

  /// Reminder in seven days
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get remindNextWeek;

  /// Opens a date and time picker
  ///
  /// In en, this message translates to:
  /// **'Pick a time…'**
  String get remindPick;

  /// Clears the note's reminder
  ///
  /// In en, this message translates to:
  /// **'Remove reminder'**
  String get remindClear;

  /// Title of the sheet that delivers the note being written at a later time
  ///
  /// In en, this message translates to:
  /// **'Schedule note'**
  String get scheduleTitle;

  /// No description provided for @scheduleInMonth.
  ///
  /// In en, this message translates to:
  /// **'In a month'**
  String get scheduleInMonth;

  /// No description provided for @scheduleInYear.
  ///
  /// In en, this message translates to:
  /// **'In a year'**
  String get scheduleInYear;

  /// No description provided for @scheduleActionToday.
  ///
  /// In en, this message translates to:
  /// **'Arrives today at {time}'**
  String scheduleActionToday(String time);

  /// No description provided for @scheduleActionTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Arrives tomorrow at {time}'**
  String scheduleActionTomorrow(String time);

  /// No description provided for @scheduleActionOn.
  ///
  /// In en, this message translates to:
  /// **'Arrives on {date} at {time}'**
  String scheduleActionOn(String date, String time);

  /// No description provided for @scheduleSet.
  ///
  /// In en, this message translates to:
  /// **'Scheduled — arrives {when}'**
  String scheduleSet(String when);

  /// No description provided for @scheduleFailed.
  ///
  /// In en, this message translates to:
  /// **'This note could not be scheduled'**
  String get scheduleFailed;

  /// No description provided for @scheduleHint.
  ///
  /// In en, this message translates to:
  /// **'Hold ↑ to schedule it for later'**
  String get scheduleHint;

  /// No description provided for @scheduledTitle.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get scheduledTitle;

  /// No description provided for @scheduledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notes on their way'**
  String get scheduledSubtitle;

  /// No description provided for @scheduledEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled. While writing a note, hold the send button to have it arrive later.'**
  String get scheduledEmpty;

  /// No description provided for @scheduledArrives.
  ///
  /// In en, this message translates to:
  /// **'Arrives {when}'**
  String scheduledArrives(String when);

  /// No description provided for @scheduledWritten.
  ///
  /// In en, this message translates to:
  /// **'Written {when}'**
  String scheduledWritten(String when);

  /// No description provided for @scheduledSendNow.
  ///
  /// In en, this message translates to:
  /// **'Deliver now'**
  String get scheduledSendNow;

  /// No description provided for @scheduledChangeTime.
  ///
  /// In en, this message translates to:
  /// **'Change time'**
  String get scheduledChangeTime;

  /// No description provided for @scheduledDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get scheduledDiscard;

  /// No description provided for @scheduledDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard this note? It never reached your notes, so it cannot be restored.'**
  String get scheduledDiscardConfirm;

  /// No description provided for @cycleTitle.
  ///
  /// In en, this message translates to:
  /// **'Cycle'**
  String get cycleTitle;

  /// No description provided for @cycleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your cycle, kept on this phone'**
  String get cycleSubtitle;

  /// No description provided for @cycleWelcome.
  ///
  /// In en, this message translates to:
  /// **'A few questions to begin'**
  String get cycleWelcome;

  /// No description provided for @cycleWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Answer what you know; Nex learns the rest from what you log. Everything stays on this phone.'**
  String get cycleWelcomeBody;

  /// No description provided for @cycleAskLastStart.
  ///
  /// In en, this message translates to:
  /// **'When did your last period start?'**
  String get cycleAskLastStart;

  /// No description provided for @cycleAskPeriodLength.
  ///
  /// In en, this message translates to:
  /// **'How many days does it usually last?'**
  String get cycleAskPeriodLength;

  /// No description provided for @cycleAskCycleLength.
  ///
  /// In en, this message translates to:
  /// **'How many days from one period to the next?'**
  String get cycleAskCycleLength;

  /// No description provided for @cycleDontKnow.
  ///
  /// In en, this message translates to:
  /// **'I don\'t know'**
  String get cycleDontKnow;

  /// No description provided for @cyclePickDate.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get cyclePickDate;

  /// No description provided for @cycleDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String cycleDays(int count);

  /// No description provided for @cycleBegin.
  ///
  /// In en, this message translates to:
  /// **'Begin'**
  String get cycleBegin;

  /// No description provided for @cycleDayOfPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period, day {day}'**
  String cycleDayOfPeriod(String day);

  /// No description provided for @cycleDaysUntil.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day until your period} other{{count} days until your period}}'**
  String cycleDaysUntil(int count);

  /// No description provided for @cycleDueToday.
  ///
  /// In en, this message translates to:
  /// **'Your period may start today'**
  String get cycleDueToday;

  /// No description provided for @cycleLate.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day late} other{{count} days late}}'**
  String cycleLate(int count);

  /// No description provided for @cycleDayOfCycle.
  ///
  /// In en, this message translates to:
  /// **'Day {day} of your cycle'**
  String cycleDayOfCycle(String day);

  /// No description provided for @cycleLikelyBetween.
  ///
  /// In en, this message translates to:
  /// **'Likely between {from} and {to}'**
  String cycleLikelyBetween(String from, String to);

  /// No description provided for @cycleConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'Still learning your cycle'**
  String get cycleConfidenceLow;

  /// No description provided for @cycleConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'Getting to know your cycle'**
  String get cycleConfidenceMedium;

  /// No description provided for @cycleConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'Based on your regular cycles'**
  String get cycleConfidenceHigh;

  /// No description provided for @cycleFertileNow.
  ///
  /// In en, this message translates to:
  /// **'Likely fertile days'**
  String get cycleFertileNow;

  /// No description provided for @cyclePeriodStarted.
  ///
  /// In en, this message translates to:
  /// **'Period started'**
  String get cyclePeriodStarted;

  /// No description provided for @cyclePeriodEnded.
  ///
  /// In en, this message translates to:
  /// **'Period ended'**
  String get cyclePeriodEnded;

  /// No description provided for @cycleAnotherDay.
  ///
  /// In en, this message translates to:
  /// **'On another day?'**
  String get cycleAnotherDay;

  /// No description provided for @cycleLogToday.
  ///
  /// In en, this message translates to:
  /// **'Log today'**
  String get cycleLogToday;

  /// No description provided for @cycleNothingLogged.
  ///
  /// In en, this message translates to:
  /// **'Nothing noted yet'**
  String get cycleNothingLogged;

  /// No description provided for @cycleDayToday.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get cycleDayToday;

  /// No description provided for @cycleDayOvulation.
  ///
  /// In en, this message translates to:
  /// **'likely ovulation'**
  String get cycleDayOvulation;

  /// No description provided for @cycleDayLogged.
  ///
  /// In en, this message translates to:
  /// **'logged'**
  String get cycleDayLogged;

  /// No description provided for @cyclePeriodOverlap.
  ///
  /// In en, this message translates to:
  /// **'Those dates overlap another period. Change them, or delete the other period first.'**
  String get cyclePeriodOverlap;

  /// No description provided for @cycleLegendOvulation.
  ///
  /// In en, this message translates to:
  /// **'Likely ovulation'**
  String get cycleLegendOvulation;

  /// No description provided for @cycleLegendPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get cycleLegendPeriod;

  /// No description provided for @cycleLegendPredicted.
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get cycleLegendPredicted;

  /// No description provided for @cycleLegendFertile.
  ///
  /// In en, this message translates to:
  /// **'Fertile window'**
  String get cycleLegendFertile;

  /// No description provided for @cycleInsights.
  ///
  /// In en, this message translates to:
  /// **'Your averages'**
  String get cycleInsights;

  /// No description provided for @cycleAverageCycle.
  ///
  /// In en, this message translates to:
  /// **'Cycle'**
  String get cycleAverageCycle;

  /// No description provided for @cycleCyclesCounted.
  ///
  /// In en, this message translates to:
  /// **'Cycles counted'**
  String get cycleCyclesCounted;

  /// No description provided for @cycleHistory.
  ///
  /// In en, this message translates to:
  /// **'Past periods'**
  String get cycleHistory;

  /// No description provided for @cycleOngoing.
  ///
  /// In en, this message translates to:
  /// **'ongoing'**
  String get cycleOngoing;

  /// No description provided for @cycleEditPeriod.
  ///
  /// In en, this message translates to:
  /// **'Edit period'**
  String get cycleEditPeriod;

  /// No description provided for @cycleStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get cycleStart;

  /// No description provided for @cycleEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get cycleEnd;

  /// No description provided for @cycleDeletePeriod.
  ///
  /// In en, this message translates to:
  /// **'Delete this period'**
  String get cycleDeletePeriod;

  /// No description provided for @cycleDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Predictions are estimates from your own history. Cycle is not a method of contraception and does not replace a doctor.'**
  String get cycleDisclaimer;

  /// No description provided for @cyclePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Kept only on this phone and in your backups. Sent to an AI service only if you let the assistant read it.'**
  String get cyclePrivacy;

  /// No description provided for @cycleAlertLate.
  ///
  /// In en, this message translates to:
  /// **'Your period is later than usual. Stress, travel and illness can all do this; if it goes on, or you might be pregnant, it is worth checking.'**
  String get cycleAlertLate;

  /// No description provided for @cycleAlertLongPeriod.
  ///
  /// In en, this message translates to:
  /// **'This period has gone on for more than eight days. If it keeps on, or is very heavy, talk to a doctor.'**
  String get cycleAlertLongPeriod;

  /// No description provided for @cycleAlertShortCycle.
  ///
  /// In en, this message translates to:
  /// **'Your last cycle was shorter than 21 days. One short cycle is common; if it happens often, mention it to a doctor.'**
  String get cycleAlertShortCycle;

  /// No description provided for @cycleAlertLongCycle.
  ///
  /// In en, this message translates to:
  /// **'Your last cycle was longer than 38 days. If your cycles stay this long, mention it to a doctor.'**
  String get cycleAlertLongCycle;

  /// No description provided for @cycleAlertIrregular.
  ///
  /// In en, this message translates to:
  /// **'Your cycles vary by more than a week, so predictions are wide. If this is new for you, a doctor can help.'**
  String get cycleAlertIrregular;

  /// No description provided for @cycleNotAdvice.
  ///
  /// In en, this message translates to:
  /// **'This is not medical advice.'**
  String get cycleNotAdvice;

  /// No description provided for @cycleFlow.
  ///
  /// In en, this message translates to:
  /// **'Flow'**
  String get cycleFlow;

  /// No description provided for @cycleFlowNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get cycleFlowNone;

  /// No description provided for @cycleFlowSpotting.
  ///
  /// In en, this message translates to:
  /// **'Spotting'**
  String get cycleFlowSpotting;

  /// No description provided for @cycleFlowLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get cycleFlowLight;

  /// No description provided for @cycleFlowMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get cycleFlowMedium;

  /// No description provided for @cycleFlowHeavy.
  ///
  /// In en, this message translates to:
  /// **'Heavy'**
  String get cycleFlowHeavy;

  /// No description provided for @cycleMood.
  ///
  /// In en, this message translates to:
  /// **'Mood'**
  String get cycleMood;

  /// No description provided for @cycleMoodLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get cycleMoodLow;

  /// No description provided for @cycleMoodSensitive.
  ///
  /// In en, this message translates to:
  /// **'Sensitive'**
  String get cycleMoodSensitive;

  /// No description provided for @cycleMoodCalm.
  ///
  /// In en, this message translates to:
  /// **'Calm'**
  String get cycleMoodCalm;

  /// No description provided for @cycleMoodGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get cycleMoodGood;

  /// No description provided for @cycleMoodGreat.
  ///
  /// In en, this message translates to:
  /// **'Great'**
  String get cycleMoodGreat;

  /// No description provided for @cycleEnergy.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get cycleEnergy;

  /// No description provided for @cycleSymptoms.
  ///
  /// In en, this message translates to:
  /// **'Symptoms'**
  String get cycleSymptoms;

  /// No description provided for @cycleSymptomCramps.
  ///
  /// In en, this message translates to:
  /// **'Cramps'**
  String get cycleSymptomCramps;

  /// No description provided for @cycleSymptomHeadache.
  ///
  /// In en, this message translates to:
  /// **'Headache'**
  String get cycleSymptomHeadache;

  /// No description provided for @cycleSymptomBackPain.
  ///
  /// In en, this message translates to:
  /// **'Back pain'**
  String get cycleSymptomBackPain;

  /// No description provided for @cycleSymptomBloating.
  ///
  /// In en, this message translates to:
  /// **'Bloating'**
  String get cycleSymptomBloating;

  /// No description provided for @cycleSymptomBreastTenderness.
  ///
  /// In en, this message translates to:
  /// **'Tender breasts'**
  String get cycleSymptomBreastTenderness;

  /// No description provided for @cycleSymptomAcne.
  ///
  /// In en, this message translates to:
  /// **'Acne'**
  String get cycleSymptomAcne;

  /// No description provided for @cycleSymptomNausea.
  ///
  /// In en, this message translates to:
  /// **'Nausea'**
  String get cycleSymptomNausea;

  /// No description provided for @cycleSymptomFatigue.
  ///
  /// In en, this message translates to:
  /// **'Tiredness'**
  String get cycleSymptomFatigue;

  /// No description provided for @cycleSymptomCravings.
  ///
  /// In en, this message translates to:
  /// **'Cravings'**
  String get cycleSymptomCravings;

  /// No description provided for @cycleSymptomInsomnia.
  ///
  /// In en, this message translates to:
  /// **'Poor sleep'**
  String get cycleSymptomInsomnia;

  /// No description provided for @cycleSymptomDizziness.
  ///
  /// In en, this message translates to:
  /// **'Dizziness'**
  String get cycleSymptomDizziness;

  /// No description provided for @cycleSymptomDischarge.
  ///
  /// In en, this message translates to:
  /// **'Discharge'**
  String get cycleSymptomDischarge;

  /// No description provided for @cyclePainRelief.
  ///
  /// In en, this message translates to:
  /// **'Took pain relief'**
  String get cyclePainRelief;

  /// No description provided for @cycleIntimacy.
  ///
  /// In en, this message translates to:
  /// **'Intimacy'**
  String get cycleIntimacy;

  /// No description provided for @cyclePillTaken.
  ///
  /// In en, this message translates to:
  /// **'Took my pill'**
  String get cyclePillTaken;

  /// No description provided for @cycleNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get cycleNote;

  /// No description provided for @cycleStartHere.
  ///
  /// In en, this message translates to:
  /// **'Period started this day'**
  String get cycleStartHere;

  /// No description provided for @cycleEndHere.
  ///
  /// In en, this message translates to:
  /// **'Period ended this day'**
  String get cycleEndHere;

  /// No description provided for @cycleSettings.
  ///
  /// In en, this message translates to:
  /// **'Cycle settings'**
  String get cycleSettings;

  /// No description provided for @cycleReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get cycleReminders;

  /// No description provided for @cycleRemindSoon.
  ///
  /// In en, this message translates to:
  /// **'Two days before my period'**
  String get cycleRemindSoon;

  /// No description provided for @cycleRemindLog.
  ///
  /// In en, this message translates to:
  /// **'Each evening of my period, to log the day'**
  String get cycleRemindLog;

  /// No description provided for @cycleRemindPill.
  ///
  /// In en, this message translates to:
  /// **'Daily pill'**
  String get cycleRemindPill;

  /// No description provided for @cycleRemindersHint.
  ///
  /// In en, this message translates to:
  /// **'Notifications only say “Nex reminder”, never what they are about.'**
  String get cycleRemindersHint;

  /// No description provided for @cycleTypicalLengths.
  ///
  /// In en, this message translates to:
  /// **'Typical lengths'**
  String get cycleTypicalLengths;

  /// No description provided for @cycleDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all cycle data'**
  String get cycleDeleteAll;

  /// No description provided for @cycleDeleteAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Every period, every logged day and these settings are deleted from this phone, and the backups on this phone are replaced with one that does not hold them. Your notes are not touched. Copies you saved to a folder or shared are not changed. This cannot be undone.'**
  String get cycleDeleteAllConfirm;

  /// No description provided for @cycleDeleted.
  ///
  /// In en, this message translates to:
  /// **'Cycle data deleted'**
  String get cycleDeleted;

  /// No description provided for @cycleNotifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nex reminder'**
  String get cycleNotifyTitle;

  /// No description provided for @cycleNotifySoon.
  ///
  /// In en, this message translates to:
  /// **'A reminder for the coming days'**
  String get cycleNotifySoon;

  /// No description provided for @cycleNotifyLog.
  ///
  /// In en, this message translates to:
  /// **'Time for today\'s check-in'**
  String get cycleNotifyLog;

  /// No description provided for @cycleNotifyPill.
  ///
  /// In en, this message translates to:
  /// **'Your daily reminder'**
  String get cycleNotifyPill;

  /// No description provided for @settingsFeatures.
  ///
  /// In en, this message translates to:
  /// **'Sections'**
  String get settingsFeatures;

  /// No description provided for @cycleShow.
  ///
  /// In en, this message translates to:
  /// **'Show Cycle'**
  String get cycleShow;

  /// No description provided for @cycleShowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The menstrual cycle assistant in Tools'**
  String get cycleShowSubtitle;

  /// No description provided for @cycleTurnOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off Cycle?'**
  String get cycleTurnOffTitle;

  /// No description provided for @cycleTurnOffBody.
  ///
  /// In en, this message translates to:
  /// **'Its page and reminders will be gone. Keep your cycle data for when you turn it back on, or delete it now?'**
  String get cycleTurnOffBody;

  /// No description provided for @cycleTurnOffKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep data'**
  String get cycleTurnOffKeep;

  /// No description provided for @cycleTurnOffDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete data'**
  String get cycleTurnOffDelete;

  /// No description provided for @cycleMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get cycleMode;

  /// No description provided for @cycleModeNormal.
  ///
  /// In en, this message translates to:
  /// **'Tracking my cycle'**
  String get cycleModeNormal;

  /// No description provided for @cycleModeConceive.
  ///
  /// In en, this message translates to:
  /// **'Trying to conceive'**
  String get cycleModeConceive;

  /// No description provided for @cycleModePregnant.
  ///
  /// In en, this message translates to:
  /// **'Pregnant'**
  String get cycleModePregnant;

  /// No description provided for @cycleModeBreastfeeding.
  ///
  /// In en, this message translates to:
  /// **'Breastfeeding'**
  String get cycleModeBreastfeeding;

  /// No description provided for @cycleModeMenopause.
  ///
  /// In en, this message translates to:
  /// **'Perimenopause or menopause'**
  String get cycleModeMenopause;

  /// No description provided for @cycleModeNormalHint.
  ///
  /// In en, this message translates to:
  /// **'Predictions, the fertile window and gentle alerts.'**
  String get cycleModeNormalHint;

  /// No description provided for @cycleModeConceiveHint.
  ///
  /// In en, this message translates to:
  /// **'The fertile window and likely ovulation, front and centre.'**
  String get cycleModeConceiveHint;

  /// No description provided for @cycleModePregnantHint.
  ///
  /// In en, this message translates to:
  /// **'Weeks of pregnancy and the due date instead of predictions.'**
  String get cycleModePregnantHint;

  /// No description provided for @cycleModeOffHint.
  ///
  /// In en, this message translates to:
  /// **'Predictions are off; you can still log periods and days.'**
  String get cycleModeOffHint;

  /// No description provided for @cyclePredictionsOff.
  ///
  /// In en, this message translates to:
  /// **'Predictions are off in this mode. Logging works as always.'**
  String get cyclePredictionsOff;

  /// No description provided for @cycleFertileToday.
  ///
  /// In en, this message translates to:
  /// **'A likely fertile day'**
  String get cycleFertileToday;

  /// No description provided for @cycleUntilFertile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day to your fertile window} other{{count} days to your fertile window}}'**
  String cycleUntilFertile(int count);

  /// No description provided for @cycleOvulationOn.
  ///
  /// In en, this message translates to:
  /// **'Likely ovulation: {date}'**
  String cycleOvulationOn(String date);

  /// No description provided for @cyclePregnancyWeek.
  ///
  /// In en, this message translates to:
  /// **'Week {weeks}, day {days}'**
  String cyclePregnancyWeek(String weeks, String days);

  /// No description provided for @cycleDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date: {date}'**
  String cycleDueDate(String date);

  /// No description provided for @cycleTrimester.
  ///
  /// In en, this message translates to:
  /// **'Trimester {n}'**
  String cycleTrimester(String n);

  /// No description provided for @cycleDaysToGo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day to go} other{{count} days to go}}'**
  String cycleDaysToGo(int count);

  /// No description provided for @cyclePregnancyStart.
  ///
  /// In en, this message translates to:
  /// **'First day of the last period'**
  String get cyclePregnancyStart;

  /// No description provided for @cycleKnowDueDate.
  ///
  /// In en, this message translates to:
  /// **'I know my due date'**
  String get cycleKnowDueDate;

  /// No description provided for @cyclePregnancyNote.
  ///
  /// In en, this message translates to:
  /// **'Weeks are counted from the first day of your last period, the way doctors count them.'**
  String get cyclePregnancyNote;

  /// No description provided for @cyclePatterns.
  ///
  /// In en, this message translates to:
  /// **'Patterns'**
  String get cyclePatterns;

  /// No description provided for @cyclePatternsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Patterns appear here after a couple of cycles with symptoms logged.'**
  String get cyclePatternsEmpty;

  /// No description provided for @cyclePatternBefore.
  ///
  /// In en, this message translates to:
  /// **'{symptom}: usually about {days} before your period'**
  String cyclePatternBefore(String symptom, String days);

  /// No description provided for @cyclePatternDuring.
  ///
  /// In en, this message translates to:
  /// **'{symptom}: usually during your period'**
  String cyclePatternDuring(String symptom);

  /// No description provided for @cyclePatternOvulation.
  ///
  /// In en, this message translates to:
  /// **'{symptom}: usually around ovulation'**
  String cyclePatternOvulation(String symptom);

  /// No description provided for @cycleReport.
  ///
  /// In en, this message translates to:
  /// **'Report for a doctor'**
  String get cycleReport;

  /// No description provided for @cycleReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Cycle report'**
  String get cycleReportTitle;

  /// No description provided for @cycleReportMade.
  ///
  /// In en, this message translates to:
  /// **'Made with Nex on {date}'**
  String cycleReportMade(String date);

  /// No description provided for @cycleReportPeriods.
  ///
  /// In en, this message translates to:
  /// **'Recent periods'**
  String get cycleReportPeriods;

  /// No description provided for @cycleReportCycleLength.
  ///
  /// In en, this message translates to:
  /// **'Cycle length'**
  String get cycleReportCycleLength;

  /// No description provided for @cycleReportVariation.
  ///
  /// In en, this message translates to:
  /// **'Variation'**
  String get cycleReportVariation;

  /// No description provided for @cycleReportSymptoms.
  ///
  /// In en, this message translates to:
  /// **'Symptoms, last six months'**
  String get cycleReportSymptoms;

  /// No description provided for @cycleReportSave.
  ///
  /// In en, this message translates to:
  /// **'Save PDF'**
  String get cycleReportSave;

  /// No description provided for @cycleReportSaved.
  ///
  /// In en, this message translates to:
  /// **'Report saved'**
  String get cycleReportSaved;

  /// No description provided for @cycleAssistantAccess.
  ///
  /// In en, this message translates to:
  /// **'Let the assistant read Cycle'**
  String get cycleAssistantAccess;

  /// No description provided for @cycleAssistantAccessHint.
  ///
  /// In en, this message translates to:
  /// **'When on, a summary of your cycle is sent to your AI provider only when you ask the assistant about it. Off by default.'**
  String get cycleAssistantAccessHint;

  /// No description provided for @cycleFertilitySigns.
  ///
  /// In en, this message translates to:
  /// **'Fertility signs'**
  String get cycleFertilitySigns;

  /// No description provided for @cycleTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature on waking (°C)'**
  String get cycleTemperature;

  /// No description provided for @cycleOvulationTest.
  ///
  /// In en, this message translates to:
  /// **'Ovulation test'**
  String get cycleOvulationTest;

  /// No description provided for @cycleTestNegative.
  ///
  /// In en, this message translates to:
  /// **'Negative'**
  String get cycleTestNegative;

  /// No description provided for @cycleTestPositive.
  ///
  /// In en, this message translates to:
  /// **'Positive'**
  String get cycleTestPositive;

  /// No description provided for @cycleMucus.
  ///
  /// In en, this message translates to:
  /// **'Cervical mucus'**
  String get cycleMucus;

  /// No description provided for @cycleMucusDry.
  ///
  /// In en, this message translates to:
  /// **'Dry'**
  String get cycleMucusDry;

  /// No description provided for @cycleMucusSticky.
  ///
  /// In en, this message translates to:
  /// **'Sticky'**
  String get cycleMucusSticky;

  /// No description provided for @cycleMucusCreamy.
  ///
  /// In en, this message translates to:
  /// **'Creamy'**
  String get cycleMucusCreamy;

  /// No description provided for @cycleMucusWatery.
  ///
  /// In en, this message translates to:
  /// **'Watery'**
  String get cycleMucusWatery;

  /// No description provided for @cycleMucusEggWhite.
  ///
  /// In en, this message translates to:
  /// **'Egg white'**
  String get cycleMucusEggWhite;

  /// No description provided for @cyclePositiveTest.
  ///
  /// In en, this message translates to:
  /// **'Positive ovulation test on {date}: ovulation is likely within a day or two.'**
  String cyclePositiveTest(String date);

  /// No description provided for @cycleBabyArrived.
  ///
  /// In en, this message translates to:
  /// **'Has your baby arrived?'**
  String get cycleBabyArrived;

  /// No description provided for @cycleBabyArrivedBody.
  ///
  /// In en, this message translates to:
  /// **'Congratulations. Breastfeeding keeps logging without predictions; or go back to tracking your cycle.'**
  String get cycleBabyArrivedBody;

  /// No description provided for @cycleGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get cycleGreetingMorning;

  /// No description provided for @cycleGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get cycleGreetingAfternoon;

  /// No description provided for @cycleGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get cycleGreetingEvening;

  /// No description provided for @cycleGreetingNight.
  ///
  /// In en, this message translates to:
  /// **'A quiet night'**
  String get cycleGreetingNight;

  /// No description provided for @cycleWhisperPeriod.
  ///
  /// In en, this message translates to:
  /// **'Be gentle with yourself today.'**
  String get cycleWhisperPeriod;

  /// No description provided for @cycleWhisperSoon.
  ///
  /// In en, this message translates to:
  /// **'Your period is near; a little extra rest is a kindness.'**
  String get cycleWhisperSoon;

  /// No description provided for @cycleWhisperFertile.
  ///
  /// In en, this message translates to:
  /// **'These are often the days your energy shines brightest.'**
  String get cycleWhisperFertile;

  /// No description provided for @cycleWhisperCalm.
  ///
  /// In en, this message translates to:
  /// **'Every day of your cycle is part of your own rhythm.'**
  String get cycleWhisperCalm;

  /// No description provided for @cycleWhisperPregnant.
  ///
  /// In en, this message translates to:
  /// **'Two heartbeats, one gentle rhythm.'**
  String get cycleWhisperPregnant;

  /// No description provided for @cycleGentle.
  ///
  /// In en, this message translates to:
  /// **'Gentle companion'**
  String get cycleGentle;

  /// No description provided for @cycleGentleHint.
  ///
  /// In en, this message translates to:
  /// **'On the days that are often harder — just before and at the start of a period, or when you log feeling low, sensitive or in pain — the assistant answers more softly and patiently. It never brings up your cycle. Only a line about tone is sent to your AI provider, never your cycle data. Off by default.'**
  String get cycleGentleHint;

  /// No description provided for @cycleProfileAbout.
  ///
  /// In en, this message translates to:
  /// **'Follows your menstrual cycle and predicts your next period and fertile days from your own history.\nLog how you feel and what you notice, and it shows you your body\'s patterns — and, if you like, the assistant becomes a gentler companion on harder days.\nEverything stays on this phone.'**
  String get cycleProfileAbout;

  /// No description provided for @cycleProfileOpen.
  ///
  /// In en, this message translates to:
  /// **'Open Cycle'**
  String get cycleProfileOpen;

  /// No description provided for @cycleInProfile.
  ///
  /// In en, this message translates to:
  /// **'In your profile'**
  String get cycleInProfile;

  /// No description provided for @localModelChoose.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get localModelChoose;

  /// No description provided for @localModelOnPhone.
  ///
  /// In en, this message translates to:
  /// **'On this phone'**
  String get localModelOnPhone;

  /// No description provided for @localModelPartial.
  ///
  /// In en, this message translates to:
  /// **'{size} downloaded so far'**
  String localModelPartial(String size);

  /// No description provided for @localModelNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloading {model}'**
  String localModelNoticeTitle(String model);

  /// No description provided for @chatLookedSearch.
  ///
  /// In en, this message translates to:
  /// **'Searched your notes'**
  String get chatLookedSearch;

  /// No description provided for @chatLookedCycle.
  ///
  /// In en, this message translates to:
  /// **'Read your Cycle summary'**
  String get chatLookedCycle;

  /// No description provided for @chatLookedThreads.
  ///
  /// In en, this message translates to:
  /// **'Looked at your threads'**
  String get chatLookedThreads;

  /// No description provided for @chatLookedNotes.
  ///
  /// In en, this message translates to:
  /// **'Read the notes asked about'**
  String get chatLookedNotes;

  /// Title of the on-device search model screen and its row in the intelligence settings.
  ///
  /// In en, this message translates to:
  /// **'On-device search'**
  String get searchModelTitle;

  /// What the on-device search model is and is not, at the top of its screen.
  ///
  /// In en, this message translates to:
  /// **'EmbeddingGemma 2 lets Nex find notes by what they mean, right on this phone — in search, in related notes, and when the assistant looks something up. It does not chat or write anything; it only finds. Nothing you write is sent anywhere for it, and it works with no internet.'**
  String get searchModelExplained;

  /// Banner after the search model installed and ran.
  ///
  /// In en, this message translates to:
  /// **'On-device search is ready. Your notes are being prepared for it in the background.'**
  String get searchModelReady;

  /// Body of the dialog confirming removal of the search model.
  ///
  /// In en, this message translates to:
  /// **'Search by meaning goes back to your AI provider, if it offers it. Your notes are not affected.'**
  String get searchModelDeleteBody;

  /// Subtitle of the on-device search row when the model is in use.
  ///
  /// In en, this message translates to:
  /// **'On — finds notes by meaning on this phone'**
  String get searchModelRowOn;

  /// Subtitle of the on-device search row when the model is not installed.
  ///
  /// In en, this message translates to:
  /// **'Find notes by meaning with no internet'**
  String get searchModelRowOff;

  /// Button on the on-device model screen: load the installed model again, retrying every backend.
  ///
  /// In en, this message translates to:
  /// **'Try loading it again'**
  String get localModelRetry;

  /// Heading of the reminder sheet
  ///
  /// In en, this message translates to:
  /// **'Set a reminder'**
  String get remindTitle;

  /// First row of the reminder sheet's day wheel
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get remindDayToday;

  /// Second row of the reminder sheet's day wheel
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get remindDayTomorrow;

  /// Primary button of the reminder sheet when the chosen day is today
  ///
  /// In en, this message translates to:
  /// **'Remind today at {time}'**
  String remindActionToday(String time);

  /// Primary button of the reminder sheet when the chosen day is tomorrow
  ///
  /// In en, this message translates to:
  /// **'Remind tomorrow at {time}'**
  String remindActionTomorrow(String time);

  /// Primary button of the reminder sheet for any other day
  ///
  /// In en, this message translates to:
  /// **'Remind on {date} at {time}'**
  String remindActionOn(String date, String time);

  /// Shown in place of the reminder sheet's button when the chosen time is in the past
  ///
  /// In en, this message translates to:
  /// **'That moment has already gone by'**
  String get remindPast;

  /// Settings row for the once-a-day notification
  ///
  /// In en, this message translates to:
  /// **'Daily nudge'**
  String get nudgeTitle;

  /// Explains the daily nudge
  ///
  /// In en, this message translates to:
  /// **'One notification a day, at a time you choose'**
  String get nudgeSubtitle;

  /// The row that opens the daily nudge's time picker
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get nudgeTime;

  /// Settings section for notifications
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// Notification title before noon
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name}'**
  String nudgeGreetingMorning(String name);

  /// Notification title the rest of the day
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String nudgeGreetingDay(String name);

  /// Notification title when there is no name
  ///
  /// In en, this message translates to:
  /// **'Nex'**
  String get nudgeGreetingPlain;

  /// Notification body when there is no recap
  ///
  /// In en, this message translates to:
  /// **'A clear page. Nex is here when something comes up.'**
  String get nudgeNothing;

  /// Plain-language gloss under the model's verbatim licence notice
  ///
  /// In en, this message translates to:
  /// **'In short: the model belongs to its maker, it comes with its own terms, and downloading it means accepting them.'**
  String get localModelLicenseGloss;

  /// Settings row that posts a test notification
  ///
  /// In en, this message translates to:
  /// **'Send a test notification'**
  String get notificationTest;

  /// Explains what the test does
  ///
  /// In en, this message translates to:
  /// **'One now, and one in ten seconds'**
  String get notificationTestHint;

  /// Confirms the test notifications were posted
  ///
  /// In en, this message translates to:
  /// **'Sent — one now, one in ten seconds'**
  String get notificationTestSent;

  /// The test notification failed, with the system's own message
  ///
  /// In en, this message translates to:
  /// **'Could not send it — {error}'**
  String notificationTestFailed(String error);

  /// Reminder countdown on a card, minutes
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String timeMinutesShort(int count);

  /// Reminder countdown on a card, hours
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String timeHoursShort(int count);

  /// Reminder countdown on a card, days
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String timeDaysShort(int count);

  /// A reminder whose time has passed
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get remindOverdue;

  /// A reminder due later today
  ///
  /// In en, this message translates to:
  /// **'Today at {time}'**
  String remindWhenToday(String time);

  /// A reminder due tomorrow
  ///
  /// In en, this message translates to:
  /// **'Tomorrow at {time}'**
  String remindWhenTomorrow(String time);

  /// A reminder due on a named date
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String remindWhenOn(String date, String time);

  /// Header of the reminder picker when one is already set
  ///
  /// In en, this message translates to:
  /// **'Set for {when}'**
  String remindCurrent(String when);

  /// Title of the picker when a reminder already exists
  ///
  /// In en, this message translates to:
  /// **'Change reminder'**
  String get remindChange;

  /// Hint under the no-op swipe action
  ///
  /// In en, this message translates to:
  /// **'This edge does nothing'**
  String get swipeNoneHint;

  /// Hint under the delete swipe action
  ///
  /// In en, this message translates to:
  /// **'Move the note to Recently Deleted'**
  String get swipeDeleteHint;

  /// Hint under the add-tag swipe action
  ///
  /// In en, this message translates to:
  /// **'Pick a tag for the note'**
  String get swipeAddTagHint;

  /// Hint under the pin swipe action
  ///
  /// In en, this message translates to:
  /// **'Keep the note at the top of the timeline'**
  String get swipePinHint;

  /// Hint under the reminder swipe action
  ///
  /// In en, this message translates to:
  /// **'Choose when it should come back'**
  String get swipeRemindHint;

  /// Hint under the share swipe action
  ///
  /// In en, this message translates to:
  /// **'Send the note to another app'**
  String get swipeShareHint;

  /// Hint under the ask-the-assistant swipe action
  ///
  /// In en, this message translates to:
  /// **'Open the assistant on this note'**
  String get swipeAskHint;

  /// Title of the leading-edge swipe row
  ///
  /// In en, this message translates to:
  /// **'Swipe from the left'**
  String get swipeLeadingEdge;

  /// Title of the trailing-edge swipe row
  ///
  /// In en, this message translates to:
  /// **'Swipe from the right'**
  String get swipeTrailingEdge;

  /// A file past the in-app preview size limit
  ///
  /// In en, this message translates to:
  /// **'Too large to show here — open it in another app.'**
  String get filePreviewTooLarge;

  /// A file that failed to open, with the runtime's own message
  ///
  /// In en, this message translates to:
  /// **'This file could not be read — {error}'**
  String filePreviewUnreadable(String error);

  /// A CSV or TSV file with more rows than the preview draws
  ///
  /// In en, this message translates to:
  /// **'Showing the first {count} rows.'**
  String tableTruncated(int count);

  /// Selection menu: make the selected text bold
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get formatBold;

  /// Selection menu: make the selected text italic
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get formatItalic;

  /// Selection menu: set the selected text in a monospace face
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get formatMono;

  /// Selection menu: strike the selected text through
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get formatStrikethrough;

  /// Selection menu: mark the selected lines as a quotation
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get formatQuote;

  /// Selection menu: turn the selected text into a link
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get formatLink;

  /// Selection menu: remove formatting from the selection
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get formatClear;

  /// A .docx longer than the in-app preview reads
  ///
  /// In en, this message translates to:
  /// **'Only the start of this document is shown — open it in another app for the rest.'**
  String get documentTruncated;

  /// A .docx the in-app reader could not open at all
  ///
  /// In en, this message translates to:
  /// **'This document could not be shown here.'**
  String get documentUnreadable;

  /// Shown under the progress bar when a download is interrupted
  ///
  /// In en, this message translates to:
  /// **'Download stopped'**
  String get downloadStopped;

  /// Button that picks a stopped download up where it left off
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeDownload;

  /// Notification title while the update downloads
  ///
  /// In en, this message translates to:
  /// **'Downloading update'**
  String get updateDownloadingTitle;

  /// Notification title once the installer has landed
  ///
  /// In en, this message translates to:
  /// **'Update ready'**
  String get updateReadyTitle;

  /// Notification body once the installer has landed
  ///
  /// In en, this message translates to:
  /// **'Tap to install'**
  String get updateReadyBody;

  /// Action that makes a note’s timeline card show all of it
  ///
  /// In en, this message translates to:
  /// **'Show in full'**
  String get expandCard;

  /// Action that puts an expanded timeline card back to its normal height
  ///
  /// In en, this message translates to:
  /// **'Show two lines'**
  String get collapseCard;

  /// Title of the user guide screen
  ///
  /// In en, this message translates to:
  /// **'How Nex works'**
  String get guideTitle;

  /// Settings row subtitle for the user guide
  ///
  /// In en, this message translates to:
  /// **'Everything the app does, in one place'**
  String get guideSubtitle;

  /// Shown if the bundled guide file is missing
  ///
  /// In en, this message translates to:
  /// **'The guide could not be opened.'**
  String get guideUnavailable;

  /// Onboarding page title about files
  ///
  /// In en, this message translates to:
  /// **'Whatever you throw at it'**
  String get onboardingFilesTitle;

  /// Onboarding page body about files
  ///
  /// In en, this message translates to:
  /// **'Share a document, a PDF, a song or a picture into Nex and it shows you the thing itself — not just a filename.'**
  String get onboardingFilesBody;

  /// Onboarding page title about privacy
  ///
  /// In en, this message translates to:
  /// **'It stays yours'**
  String get onboardingYoursTitle;

  /// Onboarding page body about privacy
  ///
  /// In en, this message translates to:
  /// **'No account, no server, and it works with the plane on. Lock it behind your fingerprint if you like, and export the lot whenever you want.'**
  String get onboardingYoursBody;

  /// Heading above the guide link on the last onboarding step
  ///
  /// In en, this message translates to:
  /// **'Not sure where something is?'**
  String get onboardingGuideTitle;

  /// Text above the guide link on the last onboarding step
  ///
  /// In en, this message translates to:
  /// **'The guide walks through everything, and it is always in Settings.'**
  String get onboardingGuideBody;

  /// Button that opens the user guide from onboarding
  ///
  /// In en, this message translates to:
  /// **'Read the guide'**
  String get onboardingGuideOpen;

  /// Title of the dialog asking where a link should point
  ///
  /// In en, this message translates to:
  /// **'Add link'**
  String get addLink;

  /// Label of the field holding a link’s URL
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get linkAddress;

  /// Confirms a reminder and says how far off it is
  ///
  /// In en, this message translates to:
  /// **'Reminder set — {when} from now'**
  String remindSetIn(String when);

  /// No description provided for @remindInDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String remindInDays(int count);

  /// No description provided for @remindInHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String remindInHours(int count);

  /// No description provided for @remindInMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String remindInMinutes(int count);

  /// Scheduling failed even though the due date was stored
  ///
  /// In en, this message translates to:
  /// **'That time was saved on the note, but this phone would not take the alarm.'**
  String get remindNotScheduled;

  /// Confirmation after setting a reminder
  ///
  /// In en, this message translates to:
  /// **'Reminder set'**
  String get remindSet;

  /// Shown when notification permission is refused
  ///
  /// In en, this message translates to:
  /// **'Nex needs permission to send notifications.'**
  String get remindDenied;

  /// Shown when microphone permission is refused and a recording cannot start
  ///
  /// In en, this message translates to:
  /// **'Nex needs permission to use the microphone. You can grant it in your device\'s app settings.'**
  String get micDenied;

  /// Shown in the results area when a search throws
  ///
  /// In en, this message translates to:
  /// **'That search could not be run.'**
  String get searchFailed;

  /// Shown when an on-demand summary produces nothing
  ///
  /// In en, this message translates to:
  /// **'No summary came back for this note.'**
  String get summarizeFailed;

  /// No description provided for @fullBackupExplained.
  ///
  /// In en, this message translates to:
  /// **'Choose a .nexbak library backup to restore notes, media, reminders, commitments and assistant memory. App preferences, profile and downloaded AI models are not included.'**
  String get fullBackupExplained;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes?'**
  String get unsavedChanges;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @checklistItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 item} other{{count} items}}'**
  String checklistItemCount(int count);

  /// No description provided for @annotateColor.
  ///
  /// In en, this message translates to:
  /// **'{color, select, white{White} black{Black} red{Red} yellow{Yellow} green{Green} blue{Blue} other{Color}}'**
  String annotateColor(String color);

  /// No description provided for @annotateStrokeWidth.
  ///
  /// In en, this message translates to:
  /// **'Stroke width'**
  String get annotateStrokeWidth;

  /// No description provided for @playAudio.
  ///
  /// In en, this message translates to:
  /// **'Play audio'**
  String get playAudio;

  /// No description provided for @pauseAudio.
  ///
  /// In en, this message translates to:
  /// **'Pause audio'**
  String get pauseAudio;

  /// No description provided for @convertToMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Save as Markdown'**
  String get convertToMarkdown;

  /// No description provided for @convertToNote.
  ///
  /// In en, this message translates to:
  /// **'Convert to note'**
  String get convertToNote;

  /// No description provided for @markdownConvertFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not convert this file. The original is still safe. Markdown files must be UTF-8 and at most 16 MB.'**
  String get markdownConvertFailed;

  /// No description provided for @fullBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete device backup'**
  String get fullBackupTitle;

  /// No description provided for @fullBackupPrivateHint.
  ///
  /// In en, this message translates to:
  /// **'Includes the library, settings and API keys. Settings and keys are encrypted; library files and the optional model are not. Save this recovery code separately: without it the settings and keys cannot be restored. This backup can replace your current library.'**
  String get fullBackupPrivateHint;

  /// No description provided for @backupKeySaved.
  ///
  /// In en, this message translates to:
  /// **'I saved the recovery code somewhere safe'**
  String get backupKeySaved;

  /// No description provided for @backupIncludeModel.
  ///
  /// In en, this message translates to:
  /// **'Include downloaded offline model (about 2.6 GB)'**
  String get backupIncludeModel;

  /// No description provided for @backupRecoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery code'**
  String get backupRecoveryKey;

  /// No description provided for @toolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get toolsTitle;

  /// No description provided for @toolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your essentials, in their own space.'**
  String get toolsSubtitle;

  /// No description provided for @toolsPrivateHint.
  ///
  /// In en, this message translates to:
  /// **'Separate from notes, search and AI.'**
  String get toolsPrivateHint;

  /// No description provided for @vaultPasswords.
  ///
  /// In en, this message translates to:
  /// **'Passwords'**
  String get vaultPasswords;

  /// No description provided for @vaultPasswordsHint.
  ///
  /// In en, this message translates to:
  /// **'Accounts, passwords and Chrome CSV import.'**
  String get vaultPasswordsHint;

  /// No description provided for @vaultCards.
  ///
  /// In en, this message translates to:
  /// **'Bank cards'**
  String get vaultCards;

  /// No description provided for @vaultCardsHint.
  ///
  /// In en, this message translates to:
  /// **'Card details and IBAN, ready to copy.'**
  String get vaultCardsHint;

  /// No description provided for @vaultLocked.
  ///
  /// In en, this message translates to:
  /// **'Your vault is locked'**
  String get vaultLocked;

  /// No description provided for @vaultUnlockHint.
  ///
  /// In en, this message translates to:
  /// **'Use your device fingerprint or screen lock to open this private space.'**
  String get vaultUnlockHint;

  /// No description provided for @vaultUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock vault'**
  String get vaultUnlock;

  /// No description provided for @vaultAuthReason.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity to open the Nex vault'**
  String get vaultAuthReason;

  /// No description provided for @vaultUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unlock was not completed. Set up a screen lock if needed, then try again.'**
  String get vaultUnavailable;

  /// No description provided for @vaultError.
  ///
  /// In en, this message translates to:
  /// **'Could not access the vault. Your stored data has not been reset.'**
  String get vaultError;

  /// No description provided for @vaultLock.
  ///
  /// In en, this message translates to:
  /// **'Lock vault'**
  String get vaultLock;

  /// No description provided for @vaultSearch.
  ///
  /// In en, this message translates to:
  /// **'Find in this vault'**
  String get vaultSearch;

  /// No description provided for @vaultEmpty.
  ///
  /// In en, this message translates to:
  /// **'Keep your first item here'**
  String get vaultEmpty;

  /// No description provided for @vaultEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add an item to keep its details private and easy to copy.'**
  String get vaultEmptyHint;

  /// No description provided for @vaultAddPassword.
  ///
  /// In en, this message translates to:
  /// **'Add password'**
  String get vaultAddPassword;

  /// No description provided for @vaultAddCard.
  ///
  /// In en, this message translates to:
  /// **'Add bank card'**
  String get vaultAddCard;

  /// No description provided for @vaultAll.
  ///
  /// In en, this message translates to:
  /// **'All items'**
  String get vaultAll;

  /// No description provided for @vaultFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get vaultFavorites;

  /// No description provided for @vaultFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get vaultFavorite;

  /// No description provided for @vaultNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching items'**
  String get vaultNoResults;

  /// No description provided for @vaultTitleField.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get vaultTitleField;

  /// No description provided for @vaultLogin.
  ///
  /// In en, this message translates to:
  /// **'Username or email'**
  String get vaultLogin;

  /// No description provided for @vaultPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get vaultPassword;

  /// No description provided for @vaultWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get vaultWebsite;

  /// No description provided for @vaultNotes.
  ///
  /// In en, this message translates to:
  /// **'Private notes'**
  String get vaultNotes;

  /// No description provided for @vaultBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get vaultBank;

  /// No description provided for @vaultHolder.
  ///
  /// In en, this message translates to:
  /// **'Cardholder'**
  String get vaultHolder;

  /// No description provided for @vaultNumber.
  ///
  /// In en, this message translates to:
  /// **'Card number'**
  String get vaultNumber;

  /// No description provided for @vaultExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry as printed (MM/YY)'**
  String get vaultExpiry;

  /// No description provided for @vaultCvv2.
  ///
  /// In en, this message translates to:
  /// **'CVV2'**
  String get vaultCvv2;

  /// No description provided for @vaultInvalidCvv2.
  ///
  /// In en, this message translates to:
  /// **'CVV2 is 3 or 4 digits'**
  String get vaultInvalidCvv2;

  /// No description provided for @vaultIban.
  ///
  /// In en, this message translates to:
  /// **'IBAN'**
  String get vaultIban;

  /// No description provided for @vaultAccount.
  ///
  /// In en, this message translates to:
  /// **'Account number'**
  String get vaultAccount;

  /// No description provided for @vaultRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get vaultRequired;

  /// No description provided for @vaultInvalidCard.
  ///
  /// In en, this message translates to:
  /// **'Check the card number'**
  String get vaultInvalidCard;

  /// No description provided for @vaultInvalidIban.
  ///
  /// In en, this message translates to:
  /// **'Check the IBAN'**
  String get vaultInvalidIban;

  /// No description provided for @vaultInvalidExpiry.
  ///
  /// In en, this message translates to:
  /// **'Use a month from 01 to 12 and a 2- or 4-digit year'**
  String get vaultInvalidExpiry;

  /// No description provided for @vaultShow.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get vaultShow;

  /// No description provided for @vaultHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get vaultHide;

  /// No description provided for @vaultCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get vaultCopied;

  /// No description provided for @vaultCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy. Try again.'**
  String get vaultCopyFailed;

  /// No description provided for @vaultGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate a new password'**
  String get vaultGenerate;

  /// No description provided for @vaultGenerator.
  ///
  /// In en, this message translates to:
  /// **'Password generator'**
  String get vaultGenerator;

  /// No description provided for @vaultSymbols.
  ///
  /// In en, this message translates to:
  /// **'Include symbols'**
  String get vaultSymbols;

  /// No description provided for @vaultUseGenerated.
  ///
  /// In en, this message translates to:
  /// **'Use this password'**
  String get vaultUseGenerated;

  /// No description provided for @vaultLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get vaultLength;

  /// No description provided for @vaultEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get vaultEdit;

  /// No description provided for @vaultSave.
  ///
  /// In en, this message translates to:
  /// **'Save securely'**
  String get vaultSave;

  /// No description provided for @vaultSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved securely'**
  String get vaultSaved;

  /// No description provided for @vaultDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard draft'**
  String get vaultDiscard;

  /// No description provided for @vaultResume.
  ///
  /// In en, this message translates to:
  /// **'Continue unfinished edit'**
  String get vaultResume;

  /// No description provided for @vaultDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete item'**
  String get vaultDelete;

  /// No description provided for @vaultDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'This removes the item from this vault.'**
  String get vaultDeleteHint;

  /// No description provided for @vaultDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get vaultDeleteConfirm;

  /// No description provided for @vaultBackupHint.
  ///
  /// In en, this message translates to:
  /// **'For a transferable copy, select Include vault in Complete app backup and keep its recovery code separately.'**
  String get vaultBackupHint;

  /// No description provided for @vaultPrivacyHint.
  ///
  /// In en, this message translates to:
  /// **'Vaults are encrypted on this device. One unlock opens every private tool; they lock after 2 minutes without activity, even while you are in another app. Leaving the app always hides their contents.'**
  String get vaultPrivacyHint;

  /// No description provided for @vaultEditHint.
  ///
  /// In en, this message translates to:
  /// **'Unfinished edits are kept as an encrypted draft.'**
  String get vaultEditHint;

  /// No description provided for @backupIncludeVault.
  ///
  /// In en, this message translates to:
  /// **'Include private vault (requires device authentication)'**
  String get backupIncludeVault;

  /// No description provided for @vaultRestoreAuth.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity before restoring this complete backup'**
  String get vaultRestoreAuth;

  /// No description provided for @assistantGeneralKnowledge.
  ///
  /// In en, this message translates to:
  /// **'From general knowledge, not your notes'**
  String get assistantGeneralKnowledge;

  /// No description provided for @assistantOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open this note'**
  String get assistantOpenSource;

  /// No description provided for @threads.
  ///
  /// In en, this message translates to:
  /// **'Threads'**
  String get threads;

  /// No description provided for @threadsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notes about the same thing, gathered without moving them'**
  String get threadsSubtitle;

  /// No description provided for @threadsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No threads yet. When a new note clearly continues an earlier one, Nex offers to gather them — or add a note to a thread from its details.'**
  String get threadsEmpty;

  /// No description provided for @threadNew.
  ///
  /// In en, this message translates to:
  /// **'New thread'**
  String get threadNew;

  /// No description provided for @threadName.
  ///
  /// In en, this message translates to:
  /// **'Thread name'**
  String get threadName;

  /// No description provided for @threadRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get threadRename;

  /// No description provided for @threadDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete thread'**
  String get threadDelete;

  /// No description provided for @threadDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'The thread goes; its notes stay exactly where they are.'**
  String get threadDeleteBody;

  /// No description provided for @threadRemoveNote.
  ///
  /// In en, this message translates to:
  /// **'Remove from thread'**
  String get threadRemoveNote;

  /// No description provided for @threadNoteCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note} other{{count} notes}}'**
  String threadNoteCount(int count);

  /// No description provided for @threadAddTo.
  ///
  /// In en, this message translates to:
  /// **'Threads'**
  String get threadAddTo;

  /// No description provided for @threadEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notes in this thread any more.'**
  String get threadEmpty;

  /// No description provided for @threadSuggestJoin.
  ///
  /// In en, this message translates to:
  /// **'Continues “{name}”?'**
  String threadSuggestJoin(String name);

  /// No description provided for @threadSuggestStart.
  ///
  /// In en, this message translates to:
  /// **'Start a thread “{name}”?'**
  String threadSuggestStart(String name);

  /// No description provided for @threadSuggestAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get threadSuggestAdd;

  /// No description provided for @threadSuggestStartAction.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get threadSuggestStartAction;

  /// No description provided for @threadAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to “{name}”'**
  String threadAdded(String name);

  /// No description provided for @threadSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggest threads after a capture'**
  String get threadSuggestions;

  /// No description provided for @threadSuggestionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only when a new note clearly continues an earlier one. Nothing is added without a tap.'**
  String get threadSuggestionsSubtitle;

  /// No description provided for @searchByMeaning.
  ///
  /// In en, this message translates to:
  /// **'Found by meaning'**
  String get searchByMeaning;

  /// The line under the Nex wordmark on the opening screen: the octopus mark, one mind with many arms, joining the pieces of a life.
  ///
  /// In en, this message translates to:
  /// **'One mind. A thousand connections.'**
  String get splashTagline;

  /// No description provided for @cameraClose.
  ///
  /// In en, this message translates to:
  /// **'Close camera'**
  String get cameraClose;

  /// No description provided for @cameraShutter.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get cameraShutter;

  /// No description provided for @cameraOptions.
  ///
  /// In en, this message translates to:
  /// **'Camera options'**
  String get cameraOptions;

  /// No description provided for @cameraSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get cameraSwitch;

  /// No description provided for @cameraFlashOff.
  ///
  /// In en, this message translates to:
  /// **'Flash off'**
  String get cameraFlashOff;

  /// No description provided for @cameraFlashAuto.
  ///
  /// In en, this message translates to:
  /// **'Flash auto'**
  String get cameraFlashAuto;

  /// No description provided for @cameraFlashOn.
  ///
  /// In en, this message translates to:
  /// **'Flash on'**
  String get cameraFlashOn;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Nex can\'t open the camera. Allow camera access for Nex in Android settings, or use the phone\'s camera app.'**
  String get cameraUnavailable;

  /// No description provided for @cameraUseSystem.
  ///
  /// In en, this message translates to:
  /// **'Use the camera app'**
  String get cameraUseSystem;

  /// No description provided for @disclosuresTitle.
  ///
  /// In en, this message translates to:
  /// **'What left this device'**
  String get disclosuresTitle;

  /// No description provided for @disclosuresRow.
  ///
  /// In en, this message translates to:
  /// **'Every request Nex made to an AI provider'**
  String get disclosuresRow;

  /// No description provided for @disclosuresIntro.
  ///
  /// In en, this message translates to:
  /// **'Each time Nex sent something to an AI provider: which one, what for, what kind of content and from which notes. This record stays on this phone, is never uploaded and is not part of any backup. An offline model sends nothing and never appears here.'**
  String get disclosuresIntro;

  /// No description provided for @disclosuresEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing has left this device.'**
  String get disclosuresEmpty;

  /// No description provided for @disclosuresClear.
  ///
  /// In en, this message translates to:
  /// **'Clear record'**
  String get disclosuresClear;

  /// No description provided for @disclosuresClearBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this record of what was sent? What was already sent is not affected.'**
  String get disclosuresClearBody;

  /// No description provided for @disclosuresFromNotes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{From 1 note} other{From {count} notes}}'**
  String disclosuresFromNotes(int count);

  /// No description provided for @disclosuresNotesGone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note has since been deleted.} other{{count} notes have since been deleted.}}'**
  String disclosuresNotesGone(int count);

  /// No description provided for @disclosureChat.
  ///
  /// In en, this message translates to:
  /// **'Assistant question'**
  String get disclosureChat;

  /// No description provided for @disclosureTags.
  ///
  /// In en, this message translates to:
  /// **'Tag suggestions'**
  String get disclosureTags;

  /// No description provided for @disclosureSummary.
  ///
  /// In en, this message translates to:
  /// **'Note summary'**
  String get disclosureSummary;

  /// No description provided for @disclosureDailySummary.
  ///
  /// In en, this message translates to:
  /// **'Smart summary'**
  String get disclosureDailySummary;

  /// No description provided for @disclosureGreeting.
  ///
  /// In en, this message translates to:
  /// **'Greeting'**
  String get disclosureGreeting;

  /// No description provided for @disclosureTranslation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get disclosureTranslation;

  /// No description provided for @disclosureRewrite.
  ///
  /// In en, this message translates to:
  /// **'Rewrite'**
  String get disclosureRewrite;

  /// No description provided for @disclosureTranscription.
  ///
  /// In en, this message translates to:
  /// **'Voice transcription'**
  String get disclosureTranscription;

  /// No description provided for @disclosurePhotoText.
  ///
  /// In en, this message translates to:
  /// **'Text in a photo'**
  String get disclosurePhotoText;

  /// No description provided for @disclosureSearchIndex.
  ///
  /// In en, this message translates to:
  /// **'Search by meaning'**
  String get disclosureSearchIndex;

  /// No description provided for @disclosureConnectionTest.
  ///
  /// In en, this message translates to:
  /// **'Connection test'**
  String get disclosureConnectionTest;

  /// No description provided for @disclosureOther.
  ///
  /// In en, this message translates to:
  /// **'Other request'**
  String get disclosureOther;

  /// No description provided for @disclosureText.
  ///
  /// In en, this message translates to:
  /// **'text'**
  String get disclosureText;

  /// No description provided for @disclosureFileText.
  ///
  /// In en, this message translates to:
  /// **'file'**
  String get disclosureFileText;

  /// No description provided for @disclosureImage.
  ///
  /// In en, this message translates to:
  /// **'image'**
  String get disclosureImage;

  /// No description provided for @disclosureAudio.
  ///
  /// In en, this message translates to:
  /// **'audio'**
  String get disclosureAudio;

  /// No description provided for @backupFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic copy to a folder'**
  String get backupFolderTitle;

  /// No description provided for @backupFolderExplained.
  ///
  /// In en, this message translates to:
  /// **'Once a day while Nex is open, a complete backup — notes, media, settings and service keys, never the private vault — goes into a folder you choose: on this phone, or one that Google Drive, Nextcloud or Syncthing offers in the picker. The newest three are kept. Settings and keys in it are encrypted with a recovery code; the notes are not, so choose a folder you trust.'**
  String get backupFolderExplained;

  /// No description provided for @backupFolderChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get backupFolderChoose;

  /// No description provided for @backupFolderKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Every automatic copy is locked with this recovery code. Keep it somewhere other than this phone: without it the settings and keys in a copy cannot be restored.'**
  String get backupFolderKeyHint;

  /// No description provided for @backupFolderStatus.
  ///
  /// In en, this message translates to:
  /// **'{folder} · last copy {when}'**
  String backupFolderStatus(String folder, String when);

  /// No description provided for @backupFolderNever.
  ///
  /// In en, this message translates to:
  /// **'{folder} · no copy yet'**
  String backupFolderNever(String folder);

  /// No description provided for @backupFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'The last copy did not reach the folder. Check that it is still available, or choose it again.'**
  String get backupFolderFailed;

  /// No description provided for @backupFolderCopyNow.
  ///
  /// In en, this message translates to:
  /// **'Copy now'**
  String get backupFolderCopyNow;

  /// No description provided for @backupFolderShowKey.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get backupFolderShowKey;

  /// No description provided for @backupFolderStop.
  ///
  /// In en, this message translates to:
  /// **'Stop copying'**
  String get backupFolderStop;

  /// No description provided for @backupFolderStopBody.
  ///
  /// In en, this message translates to:
  /// **'Stop the automatic copies? The copies already in the folder stay there.'**
  String get backupFolderStopBody;

  /// No description provided for @backupFolderCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to the folder'**
  String get backupFolderCopied;

  /// No description provided for @backupFolderCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy to the folder'**
  String get backupFolderCopyFailed;

  /// No description provided for @metricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Speed and reliability'**
  String get metricsTitle;

  /// No description provided for @metricsRowOn.
  ///
  /// In en, this message translates to:
  /// **'Measuring on this device'**
  String get metricsRowOn;

  /// No description provided for @metricsRowOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get metricsRowOff;

  /// No description provided for @metricsSwitch.
  ///
  /// In en, this message translates to:
  /// **'Measure on this device'**
  String get metricsSwitch;

  /// No description provided for @metricsIntro.
  ///
  /// In en, this message translates to:
  /// **'Nex can time how fast it opens, how long a capture takes from opening to saved, and how long a search takes to find the note you open. The numbers stay on this phone: they are never sent, never backed up, and never include your notes or what you searched for. Turning this off deletes them.'**
  String get metricsIntro;

  /// No description provided for @metricsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing measured yet. Use Nex as usual and come back later.'**
  String get metricsEmpty;

  /// No description provided for @metricsLaunch.
  ///
  /// In en, this message translates to:
  /// **'Opening, to your library'**
  String get metricsLaunch;

  /// No description provided for @metricsTimeline.
  ///
  /// In en, this message translates to:
  /// **'Opening, to your notes on screen'**
  String get metricsTimeline;

  /// No description provided for @metricsTimelineHint.
  ///
  /// In en, this message translates to:
  /// **'Includes the opening animation'**
  String get metricsTimelineHint;

  /// No description provided for @metricsCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture, from opening to saved'**
  String get metricsCapture;

  /// No description provided for @metricsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search, to opening a note'**
  String get metricsSearch;

  /// No description provided for @metricsValue.
  ///
  /// In en, this message translates to:
  /// **'Usually {median} · slowest {slow}'**
  String metricsValue(String median, String slow);

  /// No description provided for @metricsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 time} other{{count} times}}'**
  String metricsCount(int count);

  /// No description provided for @metricsNoData.
  ///
  /// In en, this message translates to:
  /// **'Not measured yet'**
  String get metricsNoData;

  /// No description provided for @metricsSessions.
  ///
  /// In en, this message translates to:
  /// **'Captures without an error'**
  String get metricsSessions;

  /// No description provided for @metricsSessionsValue.
  ///
  /// In en, this message translates to:
  /// **'{clean} of {total} sessions with a capture'**
  String metricsSessionsValue(String clean, String total);

  /// No description provided for @metricsMs.
  ///
  /// In en, this message translates to:
  /// **'{value} ms'**
  String metricsMs(String value);

  /// No description provided for @metricsSeconds.
  ///
  /// In en, this message translates to:
  /// **'{value} s'**
  String metricsSeconds(String value);

  /// No description provided for @metricsFootnote.
  ///
  /// In en, this message translates to:
  /// **'Timed from Nex\'s own code starting, on cold starts only. \"Slowest\" is the slowest one in ten.'**
  String get metricsFootnote;

  /// No description provided for @feedbackAttachMetrics.
  ///
  /// In en, this message translates to:
  /// **'Attach my speed measurements'**
  String get feedbackAttachMetrics;

  /// No description provided for @feedbackAttachMetricsHint.
  ///
  /// In en, this message translates to:
  /// **'Timings and counts only — nothing from your notes. Shown below before sending.'**
  String get feedbackAttachMetricsHint;

  /// No description provided for @backupFolderFailedCode.
  ///
  /// In en, this message translates to:
  /// **'The recovery code for this folder is missing. Choose the folder again to make a new one.'**
  String get backupFolderFailedCode;

  /// No description provided for @backupFolderFailedAccess.
  ///
  /// In en, this message translates to:
  /// **'Nex no longer has access to this folder. Choose it again.'**
  String get backupFolderFailedAccess;

  /// No description provided for @backupFolderFailedBackup.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be made ({detail}).'**
  String backupFolderFailedBackup(String detail);

  /// No description provided for @backupFolderFailedWrite.
  ///
  /// In en, this message translates to:
  /// **'The folder\'s app did not accept the file ({detail}). Try again, or choose a folder on this phone.'**
  String backupFolderFailedWrite(String detail);

  /// No description provided for @cardDensity.
  ///
  /// In en, this message translates to:
  /// **'Card size'**
  String get cardDensity;

  /// No description provided for @cardDensityCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get cardDensityCompact;

  /// No description provided for @cardDensityStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get cardDensityStandard;

  /// No description provided for @cardDensityReadable.
  ///
  /// In en, this message translates to:
  /// **'Easier to read'**
  String get cardDensityReadable;

  /// No description provided for @selectNotes.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectNotes;

  /// No description provided for @selectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String selectionCount(int count);

  /// No description provided for @selectionClose.
  ///
  /// In en, this message translates to:
  /// **'Stop selecting'**
  String get selectionClose;

  /// No description provided for @selectionCopied.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Copied 1 note} other{Copied {count} notes}}'**
  String selectionCopied(int count);

  /// No description provided for @selectionTagged.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Tagged 1 note} other{Tagged {count} notes}}'**
  String selectionTagged(int count);

  /// No description provided for @selectionPinned.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Pinned 1 note} other{Pinned {count} notes}}'**
  String selectionPinned(int count);

  /// No description provided for @selectionUnpinned.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Unpinned 1 note} other{Unpinned {count} notes}}'**
  String selectionUnpinned(int count);

  /// No description provided for @recoveryCodeCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy the recovery code'**
  String get recoveryCodeCopy;

  /// The name of the whole-app palette setting, on the assistant's confirmation card.
  ///
  /// In en, this message translates to:
  /// **'Colour palette'**
  String get assistantSettingPalette;

  /// A switch turned on, on the assistant's confirmation card.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get assistantValueOn;

  /// A switch turned off, on the assistant's confirmation card.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get assistantValueOff;

  /// Warning on the assistant's confirmation card when a one-off reminder's time is already in the past.
  ///
  /// In en, this message translates to:
  /// **'this time has passed, so it will not ring'**
  String get assistantReminderPast;

  /// Shown after the user confirmed a one-off reminder whose time had already passed.
  ///
  /// In en, this message translates to:
  /// **'That time has already passed, so no reminder was set. Ask again with a time still ahead.'**
  String get assistantReminderPastFailed;

  /// After the first few note names on the assistant's confirmation card.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{and 1 more} other{and {count} more}}'**
  String assistantMoreNotes(int count);

  /// Confirmation for a search the assistant wants to run that the user did not ask for in words.
  ///
  /// In en, this message translates to:
  /// **'Search your notes for this?'**
  String get assistantConfirmSearch;

  /// No description provided for @settingsLanguageAndCalendar.
  ///
  /// In en, this message translates to:
  /// **'Language and calendar'**
  String get settingsLanguageAndCalendar;

  /// No description provided for @settingsGesturesAndMenus.
  ///
  /// In en, this message translates to:
  /// **'Gestures and menus'**
  String get settingsGesturesAndMenus;

  /// No description provided for @settingsSecurityAndPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Security and privacy'**
  String get settingsSecurityAndPrivacy;

  /// No description provided for @settingsRemindersAndNotifications.
  ///
  /// In en, this message translates to:
  /// **'Reminders and notifications'**
  String get settingsRemindersAndNotifications;
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
