import '../widgets/folded_note.dart';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import '../platform/note_copy.dart';
import '../platform/photo_encoding.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../documents/docx_markdown.dart';
import '../documents/text_import.dart';
import '../platform/hold_menu.dart';
import '../l10n/app_localizations.dart';
import '../widgets/card_strings.dart';
import '../widgets/dismiss_on_overscroll.dart';
import '../widgets/ai_chat_sheet.dart';
import 'package:nex_ai/cloud.dart';
import '../platform/file_opener.dart';
import '../platform/sharing.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/rename_file_dialog.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/pdf_preview.dart';
import '../platform/reminders.dart';
import '../platform/video_preview.dart';
import '../widgets/checklist_capture_sheet.dart';
import '../widgets/note_editor_sheet.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/nex_banner.dart';
import '../widgets/reminder_picker.dart';
import '../widgets/tag_picker.dart';
import '../widgets/translate_sheet.dart';
import 'photo_crop_screen.dart';
import 'threads_screen.dart';

part 'note_detail/detail_frame.dart';
part 'note_detail/detail_media.dart';
part 'note_detail/detail_bodies.dart';
part 'note_detail/detail_documents.dart';
part 'note_detail/detail_actions.dart';
part 'note_detail/detail_ai_panel.dart';

/// What the sheet reports back when it closes.
///
/// The timeline already switched on this to offer undo after a delete, but the
/// type was never declared and the sheet popped without a value, so the undo
/// path was unreachable.
enum DetailResult { deleted }

class NoteDetailSheet extends StatefulWidget {
  const NoteDetailSheet({
    super.key,
    required this.services,
    required this.noteId,
    this.preferences,
    this.focusAddTag = false,
    this.editOnOpen = false,
    this.runOnOpen,
  });

  final NexServices services;
  final String noteId;

  /// Optional, and only for the Ask action.
  ///
  /// Nullable rather than required because this sheet is opened from several
  /// places and none of the rest of it needs preferences — an argument added
  /// to every call site for one conditional button would be worse than a
  /// button that is simply absent where nobody wired it up.
  final NexPreferences? preferences;
  final bool focusAddTag;
  final bool editOnOpen;

  /// An action chosen from the note's hold menu that only this sheet knows
  /// how to do — the description, a conversion, a summary, a translation,
  /// the details. Run once, as soon as the note has loaded.
  final NexHoldAction? runOnOpen;

  @override
  State<NoteDetailSheet> createState() => _NoteDetailSheetState();
}

class _NoteDetailSheetState extends State<NoteDetailSheet> {
  Note? _note;
  List<TagSuggestion> _suggestions = const [];
  List<SemanticHit> _related = const [];

  int _pinnedNoteCount = 0;

  /// The threads this note is in, shown beside its tags.
  List<NoteThread> _threads = const [];

  /// Whether the first read has come back, whatever it found.
  ///
  /// Separate from `_note != null`, because the interesting case is exactly
  /// the one where both are false: nothing loaded *yet* is not nothing to
  /// load.
  bool _read = false;

  /// True while an on-demand summary is out.
  bool _summarizing = false;

  /// Whether the user has asked to see what the intelligence layer produced.
  ///
  /// The layer works on its own, in the background — that is the point of it —
  /// but a note is the user's writing, and a machine's reading of it does not
  /// get to sit on top of that uninvited.
  bool _showAi = false;
  bool _loadingAi = false;
  Map<String, String> _relatedTitles = const {};
  AudioPlayer? _player;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.editOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _reload();
        if (!mounted) return;
        if (_note?.type == NoteType.text || _note?.type == NoteType.link) {
          await _editContent();
        } else if (_note?.type == NoteType.checklist) {
          await _editChecklist();
        } else if (_note?.type == NoteType.photo) {
          await _editImage();
        } else {
          await _editCaption();
        }
      });
    }
    if (widget.focusAddTag) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addTag());
    }
    if (widget.runOnOpen case final action?) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _reload();
        final note = _note;
        if (!mounted || note == null) return;
        switch (action) {
          case NexHoldAction.thread:
            await _pickThreads(note.id);
          case NexHoldAction.caption:
            await _editCaption();
          case NexHoldAction.convert:
            await _convertMarkdown();
          case NexHoldAction.summarize:
            await _summarize(note.id);
          case NexHoldAction.details:
            await _showDetails();
          case NexHoldAction.translate:
            final preferences = widget.preferences;
            final text = _translatableText(note);
            if (preferences != null && text.isNotEmpty) {
              await TranslateSheet.show(
                context,
                text: text,
                preferences: preferences,
                services: widget.services,
              );
            }
          default:
            break;
        }
      });
    }
    // Deliberately not loading the intelligence layer's output here. It does
    // its work on its own, in the background; showing it is the user's call,
    // and opening a note should not fire two network requests nobody asked
    // for. See [_revealAi].
  }

  /// [setState], for the extensions in `note_detail/` that carry this
  /// sheet's actions (W4.2): an extension is not a subclass, so it cannot
  /// call the protected method itself.
  void _rebuild(VoidCallback change) => setState(change);

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final loaded = await widget.services.getById(widget.noteId);
    final pinnedNoteCount = await widget.services.pinnedNoteCount();
    final threads = await widget.services.threadsForNote(widget.noteId);
    if (!mounted) return;
    setState(() {
      _note = loaded;
      _pinnedNoteCount = pinnedNoteCount;
      _threads = threads;
      _read = true;
    });
    final note = _note;
    // A voice note, and now a music file someone shared in as well. Both are a
    // path to something the bundled player already decodes, and there was
    // never a reason for the second to be a filename and a byte count.
    if (note != null && note.mediaUri != null && _player == null) {
      final playable =
          note.type == NoteType.voice ||
          (note.type == NoteType.file &&
              NexFileKinds.of(path: note.mediaUri, mimeType: note.mimeType) ==
                  NexFileKind.audio);
      if (playable) _initPlayer(note.mediaUri!);
    }
  }

  Future<void> _initPlayer(String uri) async {
    if (!File(uri).existsSync()) return;
    final player = AudioPlayer();
    try {
      await player.setFilePath(uri);
      _player = player;
      _posSub = player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _durSub = player.durationStream.listen((d) {
        if (mounted && d != null) setState(() => _duration = d);
      });
      if (mounted) setState(() {});
    } catch (_) {
      await player.dispose();
    }
  }

  /// Editing a text note in place. `updateNote` existed on every layer down to
  /// the repository, but no screen ever called it — a captured note could not
  /// be corrected after the fact.
  ///
  /// The editor itself is [NoteEditorSheet]: a sheet that can fill the screen,
  /// with the AI edits on it when there is a model to ask. It was an
  /// `AlertDialog` with three lines in it, which is the shape a question has
  /// rather than the shape of somebody's writing.
  bool _convertingMarkdown = false;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final note = _note;
    if (note == null) {
      // "Not found" is a conclusion, and it needs the read to have finished
      // to be one. It used to be shown for any null note, which includes
      // every note that had simply not arrived yet — so opening a perfectly
      // good note on slow storage said it was gone, then produced it. That is
      // a temporary wait told as data loss, about the one thing this app is
      // for.
      return Padding(
        padding: const EdgeInsets.all(NexSpacing.lg),
        child: _read ? Text(l10n.noteNotFound) : const NexSkeleton(height: 16),
      );
    }
    final isText = note.type == NoteType.text;
    final hasMedia = note.mediaUri != null;
    final editableImage =
        hasMedia &&
        (note.type == NoteType.photo ||
            (note.type == NoteType.file &&
                NexFileKinds.of(path: note.mediaUri, mimeType: note.mimeType) ==
                    NexFileKind.image));
    final screenHeight = MediaQuery.sizeOf(context).height;
    // The sheet is as tall as what is in it, up to almost the whole screen.
    //
    // There used to be a floor as well: past 220 characters of text the sheet
    // was forced to 70% of the screen. That is a step, and a step is exactly
    // what it looked like — a note one word over the line jumped to two thirds
    // of the display and then left the bottom third empty underneath its own
    // last sentence, because the content it was making room for was not that
    // tall. Where the threshold fell also depended on things the reader could
    // not see; a voice note's hidden transcript used to trip it.
    //
    // Nothing is needed in its place. `Flexible` inside a `MainAxisSize.min`
    // column already grows with the text and stops at the cap, so a long note
    // opens tall and a two-line thought hugs itself — which is what the floor
    // was trying to approximate in one jump.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.92),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            // A long note's sheet is almost entirely content, so the handle
            // at the top was the only part of it that could be dragged shut.
            child: NexDismissOnOverscroll(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The type and when it was captured, on one line.
                    //
                    // The date used to be on the timeline card and the time was
                    // nowhere except behind the Details button — so the card
                    // carried the half nobody needed at a glance and hid the
                    // half you go looking for. It is the other way round now:
                    // the card is clean, and this is where you find out when.
                    //
                    // A wrap, so at the largest text sizes the time moves under
                    // the type instead of running off the edge.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: NexSpacing.md,
                      children: [
                        Text(
                          l10n.noteType(note.type.wireName),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          _formatTimestamp(note.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    if (note.type == NoteType.checklist)
                      // The one place a checklist is interactive. On the card it
                      // is a picture of a list; here it is the list.
                      _ChecklistBody(
                        items: note.checklistItems,
                        onToggle: (index) => unawaited(_toggleItem(index)),
                      )
                    else if (note.type == NoteType.link)
                      _LinkBody(note: note, onOpen: _openLink)
                    else if (note.type == NoteType.text)
                      FoldedNote(
                        text: note.content ?? '',
                        onTapLink: _openHref,
                        onCopyCode: (code) =>
                            unawaited(_copyCodeSpan(context, code)),
                      )
                    else if (note.type == NoteType.voice) ...[
                      if (_player == null)
                        Text(
                          l10n.voiceDuration(
                            ((note.durationMs ?? 0) / 1000).ceil(),
                          ),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      if (_player != null) ...[
                        const SizedBox(height: NexSpacing.sm),
                        _VoicePlayerControls(
                          path: note.mediaUri,
                          player: _player!,
                          position: _position,
                          duration: _duration > Duration.zero
                              ? _duration
                              : Duration(milliseconds: note.durationMs ?? 0),
                        ),
                      ],
                      if (note.transcriptText == null)
                        Text(
                          l10n.voiceSearchHint,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ] else if (note.type == NoteType.photo) ...[
                      if (note.mediaUri != null &&
                          File(note.mediaUri!).existsSync()) ...[
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              NexPageRoute<void>(
                                builder: (_) =>
                                    _FullScreenPhoto(path: note.mediaUri!),
                                swipeBackEnabled: false,
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(NexRadius.md),
                            child: Image.file(
                              File(note.mediaUri!),
                              semanticLabel: l10n.photo,
                              fit: BoxFit.contain,
                              height: 220,
                              width: double.infinity,
                              cacheWidth: _imageCacheWidth(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: NexSpacing.sm),
                        Text(
                          l10n.tapToExpand,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else
                        Text(
                          l10n.mediaUnavailable,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                    ] else ...[
                      // File — same sheet, ADR-008 display fields. Tapping the row
                      // hands it to the OS, so the note behaves like the same file
                      // does in a file manager.
                      InkWell(
                        onTap: _openExternally,
                        borderRadius: BorderRadius.circular(NexRadius.lg),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: NexSpacing.sm,
                            horizontal: NexSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.insert_drive_file_outlined,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: NexSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      note.content?.trim().isNotEmpty == true
                                          ? note.content!
                                          : (note.mediaUri != null
                                                ? p.basename(note.mediaUri!)
                                                : l10n.file),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                    if (note.mediaUri != null &&
                                        File(note.mediaUri!).existsSync())
                                      Text(
                                        [
                                          nexDigits(
                                            nexFormatBytes(
                                              File(note.mediaUri!).lengthSync(),
                                            ),
                                            persian:
                                                Localizations.localeOf(
                                                  context,
                                                ).languageCode ==
                                                'fa',
                                          ),
                                          if (note.mimeType != null)
                                            note.mimeType!,
                                        ].join(' · '),
                                        textDirection: TextDirection.ltr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                              fontWeight: FontWeight.w400,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.revealInFolder,
                                onPressed: _copyPath,
                                icon: const Icon(
                                  Icons.folder_outlined,
                                  size: 18,
                                ),
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              Icon(
                                Icons.open_in_new,
                                size: 18,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // A file shown rather than merely listed. The note
                      // itself only ever held the filename — the content is in
                      // a file on disk — so this is the one place in the app
                      // that reads a note's media back.
                      if (note.mediaUri != null)
                        _FileBody(
                          path: note.mediaUri!,
                          kind: NexFileKinds.of(
                            path: note.mediaUri,
                            mimeType: note.mimeType,
                          ),
                          player: _player,
                          position: _position,
                          duration: _duration,
                          onOpen: _openExternally,
                        ),
                    ],
                    if (note.type != NoteType.text) ...[
                      const SizedBox(height: NexSpacing.md),
                      Text(
                        l10n.caption,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: NexSpacing.xs),
                      if (note.caption != null &&
                          note.caption!.trim().isNotEmpty)
                        // The caption editor offers the same bold, italic and
                        // link actions as a text note's, so a caption that
                        // used them is drawn the way a text note's body is.
                        nexLooksLikeMarkdown(note.caption!)
                            ? SelectionArea(
                                contextMenuBuilder: nexSelectionMenu,
                                child: NexMarkdown(
                                  note.caption!,
                                  selectable: false,
                                  onTapLink: _openHref,
                                  onCopyCode: (code) =>
                                      unawaited(_copyCodeSpan(context, code)),
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              )
                            : NexTextSurface(
                                note.caption!,
                                style: Theme.of(context).textTheme.bodyLarge,
                                selectable: true,
                              )
                      else
                        Text(
                          l10n.noCaption,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: _editCaption,
                          child: Text(
                            note.caption == null || note.caption!.trim().isEmpty
                                ? l10n.addCaption
                                : l10n.editCaption,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: NexSpacing.md),
                    Wrap(
                      spacing: NexSpacing.xs,
                      children: [
                        for (final tag in note.tags)
                          TagChip(
                            tag: tag,
                            strings: nexCardStrings(context),
                            onRemove: () async {
                              await widget.services.removeTag(
                                noteId: note.id,
                                tagId: tag.id,
                              );
                              // Unlike _addTag, this can take a tag's usage
                              // count to zero — without a refresh here, the
                              // filter row on the timeline never hears about
                              // it and keeps showing a tag nothing wears
                              // anymore until some unrelated capture or
                              // delete happens to trigger one.
                              await widget.services.refreshTimeline();
                              await _reload();
                            },
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(l10n.tag),
                          onPressed: _addTag,
                        ),
                        // Threads sit with the tags: both say what a note
                        // belongs with, and neither moves it anywhere.
                        for (final thread in _threads)
                          ActionChip(
                            avatar: const Icon(
                              Icons.timeline_outlined,
                              size: 16,
                            ),
                            label: Text(thread.name),
                            onPressed: () => unawaited(_openThread(thread)),
                          ),
                      ],
                    ),
                    _aiPanel(note, l10n),
                  ],
                ),
              ),
            ),
          ),
          // The actions are pinned below the scroll rather than sitting at the
          // end of it: a long note would otherwise bury them under a screenful
          // of text, and they belong to the note, not to its ending.
          //
          // Common actions have labels in a short fixed row. The remaining
          // actions are listed by name in a sheet, so none need a horizontally
          // scrolling strip of unexplained icons. The timeline still owns
          // soft-delete and its undo toast.
          Divider(height: 1, color: Theme.of(context).colorScheme.outline),
          Padding(
            padding: EdgeInsets.only(
              left: NexSpacing.md,
              right: NexSpacing.md,
              top: NexSpacing.sm,
              bottom: MediaQuery.viewInsetsOf(context).bottom + NexSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActionRow(
                  groups: [
                    // The note itself: take it somewhere, or change it.
                    [
                      if (hasMedia)
                        _DetailAction(
                          icon: Icons.open_in_new,
                          label: l10n.open,
                          onPressed: _openExternally,
                        ),
                      // Absent on Windows rather than present and broken: the
                      // platform has no share sheet this app can use, and an
                      // action that does nothing teaches the wrong lesson.
                      if (nexCanShare)
                        _DetailAction(
                          icon: Icons.ios_share,
                          label: l10n.share,
                          onPressed: _share,
                        ),
                      if (nexSaveTargetFor(note) != null)
                        _DetailAction(
                          icon: Icons.save_alt,
                          label: l10n.saveToDevice,
                          onPressed: _saveToDevice,
                        ),
                      if (note.type == NoteType.file)
                        _DetailAction(
                          icon: Icons.drive_file_rename_outline,
                          label: l10n.rename,
                          onPressed: _renameFile,
                        ),
                      if (_copyableText(note) != null)
                        _DetailAction(
                          icon: Icons.copy_outlined,
                          label: l10n.copy,
                          onPressed: _copyText,
                        ),
                      // The editor needs the preferences it reads the AI
                      // settings off. Everywhere a note is opened from has
                      // them; a caller without them keeps the note readable
                      // rather than offering a button that cannot open.
                      if (isText && widget.preferences != null)
                        _DetailAction(
                          icon: Icons.edit_outlined,
                          label: l10n.edit,
                          onPressed: _editContent,
                        ),
                      if (editableImage)
                        _DetailAction(
                          icon: Icons.crop_rotate,
                          label: l10n.edit,
                          onPressed: () => unawaited(_editImage()),
                        ),
                      // Needs the preferences the sheet it opens reads its
                      // haptics from. Everywhere a checklist is opened from
                      // has them; a caller that does not gets the sheet it
                      // had before rather than a button that cannot work.
                      if (note.type == NoteType.checklist &&
                          widget.preferences != null)
                        _DetailAction(
                          icon: Icons.edit_outlined,
                          label: l10n.edit,
                          onPressed: _editChecklist,
                        ),
                      if (note.type == NoteType.text ||
                          (note.type == NoteType.file &&
                              NexTextImport.canConvert(
                                note.originalFilename ?? note.mediaUri,
                                mimeType: note.mimeType,
                              )))
                        _DetailAction(
                          icon: Icons.description_outlined,
                          label: note.type == NoteType.text
                              ? l10n.convertToMarkdown
                              : l10n.convertToNote,
                          onPressed: _convertingMarkdown
                              ? null
                              : _convertMarkdown,
                        ),
                      if (note.type == NoteType.link)
                        _DetailAction(
                          icon: Icons.open_in_new,
                          label: l10n.openLink,
                          onPressed: _openLink,
                        ),
                    ],
                    // Where it sits and when it comes back. Tag and caption
                    // both already have their own affordance further up the
                    // sheet — repeating them here duplicated an action that
                    // was never out of reach.
                    [
                      _DetailAction(
                        icon: note.pinnedAt != null
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        label: note.pinnedAt != null
                            ? l10n.unpin
                            : _pinnedNoteCount >= 5
                            ? l10n.pinLimitReached
                            : l10n.pin,
                        onPressed:
                            note.pinnedAt == null && _pinnedNoteCount >= 5
                            ? null
                            : _togglePin,
                      ),
                      // Beside Pin, because the two answer the same kind of
                      // question: where this note sits on the timeline, and
                      // how hard it is to miss.
                      if (widget.preferences case final preferences?
                          when note.displayText != null ||
                              note.type == NoteType.checklist)
                        _DetailAction(
                          icon: preferences.isNoteExpanded(note.id)
                              ? Icons.unfold_less
                              : Icons.unfold_more,
                          label: preferences.isNoteExpanded(note.id)
                              ? l10n.collapseCard
                              : l10n.expandCard,
                          onPressed: () => unawaited(_toggleExpanded(note.id)),
                        ),
                      if (NexReminders.supported)
                        _DetailAction(
                          icon: note.dueAt == null
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                          label: l10n.remind,
                          onPressed: _pickReminder,
                        ),
                      _DetailAction(
                        icon: Icons.timeline_outlined,
                        label: l10n.threads,
                        onPressed: () => unawaited(_pickThreads(note.id)),
                      ),
                    ],
                    // The assistant. Tinted as a group and set off by the
                    // divider, because "is this the AI one?" is a question no
                    // single icon in a row of nine can answer on its own.
                    [
                      // Only when there is something behind it. The
                      // assistant's own rule everywhere else in the app: a
                      // button that can only answer "unavailable" is worse
                      // than no button.
                      if (widget.preferences case final preferences?
                          when AiChatSheet.availableFor(preferences))
                        _DetailAction(
                          // The sparkle, which is what this app means by AI
                          // everywhere else — on the chat sheet's own header
                          // and on the daily recap. A speech bubble meant
                          // "chat", and the report was that nobody could tell
                          // it was the assistant.
                          icon: Icons.auto_awesome,
                          label: l10n.askAboutNote,
                          accent: true,
                          onPressed: () => unawaited(
                            AiChatSheet.show(
                              context,
                              preferences: preferences,
                              services: widget.services,
                              history: preferences.chatHistory,
                              focus: note,
                            ),
                          ),
                        ),
                      // The transcript and the extracted text count: a
                      // recording in one language and a photographed sign in
                      // another are exactly the notes someone needs this for,
                      // and neither has typed content to offer.
                      if (widget.preferences case final preferences?
                          when TranslateSheet.availableFor(preferences) &&
                              _translatableText(note).isNotEmpty)
                        _DetailAction(
                          icon: Icons.translate,
                          label: l10n.translate,
                          accent: true,
                          onPressed: () => unawaited(
                            TranslateSheet.show(
                              context,
                              text: _translatableText(note),
                              preferences: preferences,
                              services: widget.services,
                            ),
                          ),
                        ),
                      // Only where it can do something. The action used to be
                      // offered unconditionally, and every path that cannot
                      // produce a summary — the capability switched off, no
                      // provider configured, the adapter unavailable —
                      // returns null from the same call, so tapping it did
                      // nothing at all and taught the reader that a primary
                      // action was broken. Gated on the same pair the
                      // translate action uses, plus the switch that governs
                      // this one specifically.
                      if (widget.preferences case final preferences?
                          when preferences
                                  .effectiveAiCapabilities
                                  .summarization &&
                              aiTextAvailableWith(preferences.aiProvider))
                        _DetailAction(
                          // A page with a sparkle on it. `summarize` is a
                          // page with lines, which is what the note icons in
                          // this same row already are — it named the content,
                          // not the action.
                          glyph: const NexSummariseIcon(),
                          label: l10n.summarize,
                          accent: true,
                          // Null while one is already running, so a slow
                          // summary cannot be asked for four more times.
                          onPressed: _summarizing
                              ? null
                              : () => unawaited(_summarize(note.id)),
                        ),
                    ],
                    // What the note is, and getting rid of it.
                    [
                      _DetailAction(
                        icon: Icons.info_outline,
                        label: l10n.details,
                        onPressed: _showDetails,
                      ),
                      _DetailAction(
                        icon: Icons.delete_outline,
                        label: l10n.delete,
                        destructive: true,
                        onPressed: () =>
                            Navigator.pop(context, DetailResult.deleted),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
