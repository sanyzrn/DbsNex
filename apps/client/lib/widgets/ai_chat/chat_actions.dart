part of '../ai_chat_sheet.dart';

/// Carrying out what the assistant proposed, once the person agrees.
extension _ChatActions on _AiChatSheetState {
  /// Carries out what the user just confirmed.
  ///
  /// Everything here goes through [NexServices], the same path the UI itself
  /// uses — so an assistant edit is indistinguishable from a hand edit, syncs
  /// like one, and lands in Recently Deleted like one.
  Future<void> _runPending() async {
    final actions = _pending;
    if (actions.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    _rebuild(() {
      _pending = const [];
      _sending = true;
    });
    var ok = true;
    try {
      // Every note this set claims to act on, checked before any of it runs.
      //
      // Without this the confirmation was a guess. `ok` only went false when
      // something *threw*, and none of these throw on a note that is not
      // there: a delete is an UPDATE matched by id, and matching no rows is
      // a successful statement that changed nothing. So an id the model
      // invented, or one left over from a note deleted earlier in the same
      // conversation, produced "Done" over a library that had not moved —
      // and the reader's next act is to believe it.
      //
      // Checked first rather than counted afterwards, for the reason the
      // loop below already gives: a half-applied set is worse than none of
      // it. Finding the bad id on the third of three actions is finding it
      // too late.
      if (!await _targetsExist(actions)) {
        throw StateError('an action names a note that is not there');
      }
      // In order, and stopping at the first failure. A half-applied set is
      // worse than none of it: the user confirmed one intention, and leaving
      // two of its three changes in place is a state nobody asked for and
      // nobody can see.
      for (final action in actions) {
        switch (action.kind) {
          case AssistantActionKind.create:
            final created = action.items.isNotEmpty
                ? await widget.services.captureChecklist([
                    for (final line in action.items)
                      ChecklistItem(text: line, done: false),
                  ])
                : await widget.services.captureText(action.text!);
            // The reminder that came with it, set the way `remind` sets one.
            if (action.at case final at? when created != null) {
              await widget.services.setDueAt(
                created.id,
                at,
                repeat: action.repeat,
              );
            }
          case AssistantActionKind.edit:
            await widget.services.updateNote(action.noteId!, action.text!);
          case AssistantActionKind.delete:
            await widget.services.deleteNote(action.noteId!);
          case AssistantActionKind.tag:
            await _applyTags(action);
          case AssistantActionKind.merge:
            await _merge(action);
          case AssistantActionKind.toChecklist:
            await _toChecklist(action);
          case AssistantActionKind.check:
            await widget.services.toggleChecklistItem(
              action.noteId!,
              action.index!,
            );
          case AssistantActionKind.setting:
            await _applySetting(action);
          case AssistantActionKind.remind:
            // Both halves at once, the way the reminder picker does it —
            // `setDueAt` schedules or cancels the alarm behind the date, so
            // nothing here has to know that a reminder is two things.
            await widget.services.setDueAt(
              action.noteId!,
              action.at,
              repeat: action.repeat,
            );
          case AssistantActionKind.pin:
            if (action.flag ?? true) {
              // Five pins is the library's limit, and `pinNote` answers
              // false rather than throwing when it is reached. Left
              // unchecked that is the same bug the id check above exists
              // for: a card that says "Done" over a timeline that has not
              // moved, and a reader whose next act is to believe it.
              if (!await widget.services.pinNote(action.noteId!)) {
                throw StateError('the library already has five pinned notes');
              }
            } else {
              await widget.services.unpinNote(action.noteId!);
            }
          case AssistantActionKind.title:
            await widget.services.setTitle(action.noteId!, action.text);
          case AssistantActionKind.restore:
            await widget.services.undelete(action.noteId!);
          case AssistantActionKind.renameTag:
            await _renameTag(action);
          case AssistantActionKind.tagColor:
            await _setTagColor(action);
          case AssistantActionKind.commitment:
            await _saveCommitment(action);
          case AssistantActionKind.commitmentMet:
            // Rolls it forward rather than finishing it — the difference
            // between a commitment and a reminder, in one call. Existence was
            // settled before any of this set ran.
            final met = await _commitmentByName(action.commitmentName);
            if (met != null) {
              await widget.services.markCommitmentMet(met.id);
            }
          case AssistantActionKind.commitmentDelete:
            final gone = await _commitmentByName(action.commitmentName);
            if (gone != null) {
              await widget.services.deleteCommitment(gone.id);
            }
          case AssistantActionKind.search:
            break;
        }
      }
    } catch (_) {
      ok = false;
    }
    await widget.services.refreshTimeline();
    if (!mounted) return;
    _rebuild(() {
      _sending = false;
      _actionResult = ok
          ? l10n.assistantActionDone
          : l10n.assistantActionFailed;
    });
    // The library moved, so the context the rest of this conversation is
    // answering from is now stale.
    unawaited(_loadNotesContext());
    _toBottom();
  }

  /// Whether every note the set names is really there.
  ///
  /// Both id fields count: `noteId` for the single-target actions and
  /// `noteIds` for a merge, which folds several notes together and is the one
  /// action that can be half-right — two real ids and one invented.
  ///
  /// A create carries no id and a search is never in this list, so an empty
  /// set of note targets is a legitimate answer of "nothing to check". The
  /// two tag-wide actions name a tag rather than a note and are checked the
  /// same way lower down, by name: a tag the model invented would otherwise
  /// be a rename that changed nothing and reported "Done".
  ///
  /// A restore is checked against the trash instead, because its target is
  /// by definition a note `getById` will not return: it is the one action
  /// whose id being absent from the library is the *reason* for it. Against
  /// the trash's own page of most-recent deletions, which is what the
  /// Recently Deleted screen shows and therefore the only notes the model
  /// could have been told about in the first place.
  Future<bool> _targetsExist(List<AssistantAction> actions) async {
    final targets = <String>{
      for (final action in actions)
        if (action.kind != AssistantActionKind.restore) ...[
          if (action.noteId case final id?) id,
          ...action.noteIds,
        ],
    };
    for (final id in targets) {
      if (await widget.services.getById(id) == null) return false;
    }
    final restoring = <String>{
      for (final action in actions)
        if (action.kind == AssistantActionKind.restore)
          if (action.noteId case final id?) id,
    };
    // Tags are named rather than identified, so "there is a tag called
    // this" is the same question `getById` answers for a note — and a tag
    // the model invented would otherwise be a rename that changed nothing
    // and said "Done".
    final tagNames = <String>{
      for (final action in actions)
        if (action.tagName case final name?) name.toLowerCase(),
    };
    if (tagNames.isNotEmpty) {
      final known = {
        for (final tag in await widget.services.listTags())
          tag.name.toLowerCase(),
      };
      if (!tagNames.every(known.contains)) return false;
    }
    // The two commitment actions that act on an existing one. A `commitment`
    // is left out on purpose: it creates as readily as it edits, so a name
    // that is not there yet is the ordinary case rather than a mistake.
    final named = <String>{
      for (final action in actions)
        if (action.kind == AssistantActionKind.commitmentMet ||
            action.kind == AssistantActionKind.commitmentDelete)
          if (action.commitmentName case final name?) name.toLowerCase(),
    };
    if (named.isNotEmpty) {
      final known = {
        for (final one in await widget.services.commitments())
          one.title.toLowerCase(),
      };
      if (!named.every(known.contains)) return false;
    }
    if (restoring.isEmpty) return true;
    final deleted = {
      for (final note in await widget.services.deletedNotes()) note.id,
    };
    return restoring.every(deleted.contains);
  }

  /// Renames a tag everywhere it is worn, found by the name the model used.
  ///
  /// By name because that is all the model ever sees — the notes it is given
  /// carry tag names, never tag ids — and case-insensitively because "Work"
  /// and "work" are the same tag to everybody except a string comparison.
  Future<void> _renameTag(AssistantAction action) async {
    final tag = await _tagNamed(action.tagName);
    if (tag == null || action.text == null) return;
    await widget.services.renameTag(tag.id, action.text!);
  }

  Future<void> _setTagColor(AssistantAction action) async {
    final tag = await _tagNamed(action.tagName);
    if (tag == null) return;
    // Null is `default` — the colour cleared, which is a thing the picker
    // can do and so is a thing that can be asked for.
    await widget.services.setTagColor(tagId: tag.id, color: action.text);
  }

  /// Creates a standing obligation, or edits the one already under that name.
  ///
  /// Same name means same thing, deliberately: a model asked twice about the
  /// rent should not leave two rents behind, and "change the insurance to
  /// every two years" is the same sentence as setting it up.
  Future<void> _saveCommitment(AssistantAction action) async {
    final name = action.commitmentName!;
    final cadence = action.cadence!;
    final every = action.every ?? 1;
    final now = DateTime.now();
    final existing = await _commitmentByName(name);
    if (existing != null) {
      await widget.services.saveCommitment(
        existing.copyWith(
          title: name,
          cadence: cadence,
          every: every,
          // No date given means leave it where it is. Editing the cadence
          // should not move the next occurrence the user already agreed to.
          dueAt: action.at,
          updatedAt: now,
        ),
      );
      return;
    }
    await widget.services.saveCommitment(
      NexCommitment(
        id: newUuidV7(),
        title: name,
        cadence: cadence,
        every: every,
        // Tomorrow morning when the model did not say. Not "now": a
        // commitment due the instant it is created is overdue before the
        // confirmation card has closed.
        dueAt:
            action.at ??
            DateTime(
              now.year,
              now.month,
              now.day,
              9,
            ).add(const Duration(days: 1)),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// The commitment stored under [name], case-insensitively.
  Future<NexCommitment?> _commitmentByName(String? name) async {
    if (name == null) return null;
    final lowered = name.toLowerCase();
    for (final one in await widget.services.commitments()) {
      if (one.title.toLowerCase() == lowered) return one;
    }
    return null;
  }

  Future<Tag?> _tagNamed(String? name) async {
    if (name == null) return null;
    final lowered = name.toLowerCase();
    final tags = await widget.services.listTags();
    for (final tag in tags) {
      if (tag.name.toLowerCase() == lowered) return tag;
    }
    return null;
  }

  /// Folds several notes into one and removes the originals.
  ///
  /// The merged text is the model's when it wrote one — that is the whole
  /// value of asking it to merge rather than concatenating — and a plain join
  /// when it did not, so the action never silently loses what was in the
  /// notes. The originals go to Recently Deleted rather than being erased:
  /// the one action here that destroys something the user cannot retype
  /// deserves the same undo every other delete has.
  Future<void> _merge(AssistantAction action) async {
    final notes = <Note>[];
    for (final id in action.noteIds) {
      final note = await widget.services.getById(id);
      if (note != null) notes.add(note);
    }
    if (notes.length < 2) return;
    final text =
        action.text ??
        notes
            .map((note) => (note.content ?? note.displayText ?? '').trim())
            .where((part) => part.isNotEmpty)
            .join('\n\n');
    if (text.trim().isEmpty) return;
    await widget.services.captureText(text);
    for (final note in notes) {
      await widget.services.deleteNote(note.id);
    }
  }

  /// Rewrites a note as a checklist, one item per line.
  ///
  /// A new note and a deleted one rather than a type change in place: a
  /// note's type is part of its identity in the timeline, in sync and in
  /// export, and turning one into another is exactly the kind of edit that
  /// should be undoable by pulling the original back out of the trash.
  Future<void> _toChecklist(AssistantAction action) async {
    final note = await widget.services.getById(action.noteId!);
    if (note == null) return;
    final source = action.text ?? note.content ?? note.displayText ?? '';
    final items = [
      for (final line in source.split('\n'))
        if (line.trim().isNotEmpty)
          ChecklistItem(
            text: line.trim().replaceFirst(RegExp(r'^[-*]\s*'), ''),
            done: false,
          ),
    ];
    if (items.isEmpty) return;
    await widget.services.captureChecklist(items);
    await widget.services.deleteNote(note.id);
  }

  /// Applies one setting from the short list in [assistantSettableKeys].
  ///
  /// Every value is checked here as well as at parse time. The parser
  /// guarantees the *key* is one this app offered; this guarantees the value
  /// is one that key accepts, so a model writing `{"key":"theme","value":
  /// "blue"}` changes nothing rather than storing a theme that does not
  /// exist.
  Future<void> _applySetting(AssistantAction action) async {
    final value = action.settingValue;
    switch (action.settingKey) {
      case 'theme':
        final mode = switch (value) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => null,
        };
        if (mode != null) await widget.preferences.setThemeMode(mode);
      case 'language':
        if (value == 'en' || value == 'fa' || value == 'system') {
          // 'system' verbatim, never an empty string: the getter reads
          // anything that is not null or 'system' as a language code, so an
          // empty value came back as Locale('') — a locale that matches no
          // translation and is not the system default either.
          await widget.preferences.setLocale(value!);
        }
      case 'ai_language':
        final language = switch (value) {
          'en' => AiOutputLanguage.english,
          'fa' => AiOutputLanguage.persian,
          'auto' => AiOutputLanguage.auto,
          _ => null,
        };
        if (language != null) {
          await widget.preferences.setAiOutputLanguage(language);
        }
      // The four sizes the settings screen offers and no others. A free
      // number would let a model store 4.0 and hand back a phone whose text
      // does not fit on it — and a size nobody can reach by hand is not a
      // size this app has.
      case 'text_size':
        final scale = switch (value) {
          'small' => 0.9,
          'default' || 'normal' || 'medium' => 1.0,
          'large' => 1.15,
          'larger' || 'largest' => 1.3,
          _ => null,
        };
        if (scale != null) await widget.preferences.setUiScale(scale);
      // The whole-app palettes on the Theme page, by the same ids it stores.
      case 'palette':
        if (nexThemePresets.any((preset) => preset.id == value)) {
          await widget.preferences.setThemePreset(value!);
        }
      // Already normalised to `#RRGGBB` by the parser, or `default` for the
      // shipped accent.
      case 'accent':
        if (value == 'default') {
          await widget.preferences.setAccentSeed(null);
        } else if (value != null &&
            _AiChatSheetState._hexSeed.hasMatch(value)) {
          await widget.preferences.setAccentSeed(value.toUpperCase());
        }
      case 'haptics':
        if (_AiChatSheetState._onOff(value) case final on?) {
          await widget.preferences.setHaptics(on);
        }
      case 'show_greeting':
        if (_AiChatSheetState._onOff(value) case final on?) {
          await widget.preferences.setShowGreeting(on);
        }
      case 'show_digest':
        if (_AiChatSheetState._onOff(value) case final on?) {
          await widget.preferences.setShowDaySummary(on);
        }
      case 'show_search':
        if (_AiChatSheetState._onOff(value) case final on?) {
          await widget.preferences.setShowSearchField(on);
        }
      case 'show_tags':
        if (_AiChatSheetState._onOff(value) case final on?) {
          await widget.preferences.setShowTagRow(on);
        }
      case 'daily_nudge':
        if (_AiChatSheetState._onOff(value) case final on?) {
          await widget.preferences.setDailyNudge(on);
        }
      case 'daily_nudge_time':
        if (_AiChatSheetState._minutesOfDay(value) case final minutes?) {
          await widget.preferences.setDailyNudgeMinutes(minutes);
        }
    }
  }

  Future<void> _applyTags(AssistantAction action) async {
    final existing = await widget.services.listTags();
    for (final name in action.removeTags) {
      final match = existing.where(
        (tag) => tag.name.toLowerCase() == name.toLowerCase(),
      );
      if (match.isEmpty) continue;
      await widget.services.removeTag(
        noteId: action.noteId!,
        tagId: match.first.id,
      );
    }
    for (final name in action.addTags) {
      await widget.services.addTag(noteId: action.noteId!, name: name);
    }
  }
}
