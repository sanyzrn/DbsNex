/// The English half of Word by Word's words. The Persian half lives
/// beside it in `words_strings_fa.dart`; `words_strings.dart` holds them
/// together, and the module kit's test holds the two maps to the same
/// keys.
library;

const Map<String, String> wordsStringsEn = {
  'repairDueAction': 'Set review date to today',
  'repairDueBody':
      'Use today for this unavailable review date? Your history, pause state and typed edits stay.',

  'reviewSettings': 'Review settings',

  'discardDraft': 'Discard draft',

  'draftLoadError': 'Could not read the saved draft. Try again before editing.',

  'batchFormat':
      'One word per line. Optionally separate the word and your meaning with a Tab. Preview before adding. Repeated or already-saved words in this language are skipped.',
  'batchTextLabel': 'Words to add',
  'batchPreviewAll': 'Preview the list',

  'saveError':
      'Could not save your draft. Your changes are still here; try again.',
  'loadError': 'Could not load your words. Try again.',
  'retry': 'Try again',
  'draftHint': 'Back keeps your draft. Cancel discards it.',
  'scheduleUnknown': 'No review date recorded',
  'whenUnknown': 'Date unknown',
  'sessionCap': 'Review batch',
  'sessionCapOff': 'All waiting cards',
  'sessionCount': '{count} cards per session',
  'filterLearned': 'Learned',
  'tagsAll': 'Show all {count} tags',
  'tagsLess': 'Show fewer tags',
  'clearFilters': 'Clear filters',
  'noMatches': 'No words match these filters.',
  'meaningNeeded': 'Add your meaning before grading this card.',
  'editMeaning': 'Add meaning',
  'skipForNow': 'Skip for now',
  'reviewChanged': 'This card changed. The review has been refreshed.',
  'batchLimit': 'Use up to 200 words in each batch. Your pasted text is kept.',
  'batchPartial':
      '{added} added. Could not confirm {remaining}; the remaining list is kept for retry.',

  'title': 'Word by Word',
  'tagline': 'Keep the words you meet; review them until they stay',
  'about':
      'A calm, offline vocabulary box. Capture words and phrases with your '
      'own meanings, then review a few at a time on a simple, honest '
      'spaced schedule — no account, no cloud, no AI.',
  'point1': 'Your own words',
  'point2': 'Spaced review, on this phone',
  'point3': 'No account, no cloud',

  // -------------------------------------------------------------- home
  'collection': 'Your words',
  'heroWaiting': '{count} to review',
  'heroDone': 'All caught up',
  'emptyWords':
      'No words yet. Add the first one — a word, a phrase, whatever you '
      'are reading.',
  'addWord': 'Add a word',
  'searchHint': 'Search words, meanings, notes',
  'filterAll': 'All',
  'filterNew': 'New',
  'filterDue': 'Due',
  'filterPaused': 'Paused',
  'dueNowCount': '{count} due now',
  'newTodayCount': '{count} new today',
  'startReview': 'Start review',
  'nothingToReview':
      'Nothing to review right now. Words come back on their own days.',
  'dailyCap': 'New per day',
  'dailyPerDay': '{count} a day',
  'dailyCapOff': 'No cap',
  'reverseTip': 'Ask the meaning first',
  'reverseOnTip': 'Back to word first',
  'reverseHint':
      'Meaning first: you are shown the meaning and recall the word.',
  'copyListTip': 'Copy this list',
  'listCopiedOne': 'Copied 1 word',
  'listCopiedMany': 'Copied {count} words',
  'batchEntryTip': 'Paste a list',
  'learnedMark': 'Learned',

  // -------------------------------------------------------- due words
  'dueToday': 'today',
  'dueTomorrow': 'tomorrow',
  'dueInDays': 'in {count} days',
  'dueOverdueOne': '1 day overdue',
  'dueOverdue': '{count} days overdue',
  'statusNew': 'new',
  'whenToday': 'today',
  'whenYesterday': 'yesterday',
  'whenDaysAgo': '{count} days ago',
  'whenDate': 'on {date}',

  // -------------------------------------------------------- the card
  'wordLabel': 'Word or phrase',
  'languageLabel': 'Language',
  'languageHint': 'Any label you like — «English», «فارسی», «French»…',
  'meaningLabel': 'Meaning',
  'meaningHint': 'Your own words. Several senses? One per line.',
  'exampleLabel': 'Example',
  'noteLabel': 'Note',
  'tagLabel': 'Tag or source',
  'saveFailed': 'Could not save. Try again.',
  'wordRequired': 'The word itself is needed.',
  'duplicateTitle': 'Already in your words',
  'duplicateBody':
      '«{word}» is already saved in {language}. Add it again as a second '
      'card?',
  'duplicateAdd': 'Add anyway',
  'deleteTitle': 'Delete this word?',
  'deleteBody':
      'The card and its whole review history go away. Undo stays '
      'available for a few seconds.',
  'wordDeleted': 'Word deleted',
  'wordRestored': 'Word restored',
  'pausedLabel': 'Paused',
  'pausedHint':
      'A paused card is not scheduled and never counts as due. Unpause '
      'whenever you like; it keeps its place.',
  'progressLabel': 'Review progress',
  'statsLine': '{reps} reviews · {lapses} lapses · step {step}',
  'nextDue': 'Next review',
  'neverReviewed': 'Not reviewed yet',
  'createdLine': 'Added {when}',

  // ------------------------------------------------------- the review
  'reviewTitle': 'Review',
  'tapToReveal': 'Tap to reveal the answer',
  'revealedSemantics': 'Answer revealed',
  'again': 'Again',
  'hard': 'Hard',
  'good': 'Good',
  'easy': 'Easy',
  'progressOf': '{n} of {total}',
  'sessionDone': 'That is the session — {count} cards reviewed.',
  'sessionDoneOne': 'That is the session — one card reviewed.',
  'sessionDoneCalm': 'Come back tomorrow; a few will be waiting.',
  'scheduleHow': 'How the schedule works',
  'scheduleHowBody':
      'A fixed ladder: 1, 3, 7, 14, 30 and 60 days. «Again» starts over at '
      'one day and counts a lapse; «Hard» repeats the current interval; '
      '«Good» climbs one rung; «Easy» climbs two. Everything is computed '
      'on this phone from calendar days — no account, no sync, no '
      'cleverness.',

  // --------------------------------------------------------- the batch
  'batchTitle': 'Paste a list of words',
  'batchPreview': '{count} words ready to add',
  'batchEmpty': 'Nothing to add yet — paste a few lines first.',
  'batchAdd': 'Add {count} words',
  'batchAdded': '{count} words added',
  'batchSkipped': '{count} skipped — repeated or already saved',
};
