import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import '../l10n/app_localizations.dart';
import '../platform/capture_failure.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/note_search.dart';
import '../platform/os_capture_bridge.dart';
import '../platform/update_service.dart';
import 'package:nex_data/nex_data.dart';
import '../widgets/capture_sheet.dart';
import '../widgets/card_strings.dart';
import '../widgets/commit_receipt.dart';
import '../widgets/empty_timeline.dart';
import '../widgets/recording_sheet.dart';
import '../widgets/search_field_header.dart';
import '../widgets/search_results.dart';
import '../widgets/tag_picker.dart';
import 'library_screen.dart';
import 'note_detail_sheet.dart';
import 'settings_sheet.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.services,
    required this.preferences,
    this.osCapture,
    this.updates,
  });
  final NexServices services;
  final NexPreferences preferences;
  final OsCaptureBridge? osCapture;

  /// Null in tests that do not care about updates.
  final UpdateService? updates;
  @override
  State<TimelineScreen> createState() => TimelineScreenState();
}

class TimelineScreenState extends State<TimelineScreen> {
  /// Everything the timeline stream last delivered, before filters.
  ///
  /// **Null means "not known yet"**, which is a different thing from "empty".
  /// This was `const []` at field initialisation while `build` ran immediately
  /// and `_loadTimeline` resolved later, so the first frame of *every* cold
  /// launch satisfied the empty condition and flashed the full-screen
  /// onboarding copy — marketing text, in front of a user with a library.
  ///
  /// It also used to hold only the filtered list, so the next stream event —
  /// which a capture triggers — replaced it with the unfiltered one while the
  /// filter chips still claimed to be active.
  List<Note>? _all;
  List<Note> notes = const [];

  /// Keeps one card open at a time and lets a scroll close it.
  final NexSwipeController _swipe = NexSwipeController();
  List<Note> anniversary = const [];
  List<Tag> filterTags = const [];
  String? selectedTagId;
  NoteType? selectedType;
  StreamSubscription<List<Note>>? subscription;
  String? landedId;

  /// Starts at the top, with the search field in view.
  ///
  /// It used to start scrolled past the field, so that pulling down revealed
  /// it. That never worked in practice and the gesture is now a refresh, which
  /// needs the list to begin at offset zero — otherwise the first pull spends
  /// itself scrolling back up.
  final ScrollController _scroll = ScrollController();

  late final NoteSearchController _search =
      NoteSearchController(services: widget.services);
  final FocusNode _searchFocus = FocusNode();

  /// Which of the three greetings this run of the app gets.
  final int _greetingVariant = math.Random().nextInt(3);
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    subscription = widget.services.timelineStream.listen((value) {
      if (!mounted) return;
      setState(() { _all = value; notes = _visible(value); });
      // The filter row is fed by a separate query that only ran once, at
      // startup. Creating or deleting a tag anywhere in the app left the row
      // showing the old set until the next cold launch — which is exactly the
      // "I had to restart it" report. Every mutation path already refreshes
      // the timeline, so this is the one place that has to notice.
      unawaited(_loadFilterTags());
    });
    _search.addListener(_onSearchChanged);
    unawaited(_loadTimeline());
    unawaited(_loadAnniversary());
    unawaited(_loadFilterTags());
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  /// Marks a note as the one just captured, the way the capture paths do.
  ///
  /// Exposed so a test can exercise the receipt without driving the camera or
  /// the recorder; the production callers set [landedId] directly.
  @visibleForTesting
  void markLanded(String id) => setState(() => landedId = id);

  /// Brings the field in and puts the cursor in it.
  ///
  /// The AppBar icon and Ctrl+F both call this, so the gesture is a shortcut
  /// rather than the only way in — a hidden gesture as the sole route to a core
  /// feature is worse than the icon it replaced.
  Future<void> revealSearch() async {
    if (_scroll.hasClients && _scroll.offset > 0) {
      await _scroll.animateTo(
        0,
        duration: NexMotion.standard,
        curve: NexMotion.curve,
      );
    }
    if (!mounted) return;
    setState(() => _searching = true);
    _searchFocus.requestFocus();
    unawaited(_search.run());
  }

  void _exitSearch() {
    _searchFocus.unfocus();
    _search.clear();
    setState(() => _searching = false);
    // No scroll on the way out. Leaving search used to push the list back down
    // past the field to re-hide it; the field lives at the top now, so that
    // would just be the timeline jumping for no reason a user could name.
  }

  /// The screen used to seed `notes` synchronously from the repository. The
  /// stream alone is not a replacement: it is a broadcast stream, so anything
  /// emitted before initState subscribes is dropped — a refresh that happens
  /// during startup left the timeline empty.
  Future<void> _loadTimeline() async {
    final loaded = await widget.services.timeline(limit: 200);
    if (!mounted) return;
    setState(() { _all = loaded; notes = _visible(loaded); });
  }

  /// FR-4 filter chips. TagFilterRow shipped in packages/ui, complete and
  /// covered by its own test, but nothing ever imported it — the timeline had
  /// no way to filter at all.
  Future<void> _loadFilterTags() async {
    final loaded = await widget.services.listTags();
    if (!mounted) return;
    setState(() => filterTags = loaded);
  }

  /// Everything this screen shows, read again.
  ///
  /// The pull-down was meant to reveal the search field. It never did — the
  /// field turned out to sit at the top permanently, so there was nothing to
  /// pull in — and a gesture that does nothing is worse than no gesture. This
  /// is what a downward pull on a list means everywhere else, and it is also
  /// the manual escape hatch for anything that fails to refresh on its own.
  ///
  /// Syncing is part of it only when a server is configured, and its failure
  /// is reported without taking the local reload down with it: the notes on
  /// this device are the point, and they reloaded either way.
  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await Future.wait([
      widget.services.refreshTimeline(),
      _loadFilterTags(),
      _loadAnniversary(),
    ]);
    if (widget.preferences.syncBaseUrl == null) return;
    try {
      await widget.services.syncNow();
    } catch (_) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.operationFailed)));
    }
  }

  Future<void> _selectTag(String? tagId) async {
    _tick();
    setState(() => selectedTagId = tagId);
    await _applyFilters();
  }

  Future<void> _selectType(NoteType? type) async {
    _tick();
    setState(() => selectedType = type);
    await _applyFilters();
  }

  /// The content-type filter, behind the mockup's icon button.
  Future<void> _pickType() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await showModalBottomSheet<_TypeChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in <NoteType?>[null, ...NoteType.values])
              ListTile(
                leading: Icon(nexNoteTypeIcon(type?.wireName)),
                title: Text(
                  type == null ? l10n.all : l10n.noteType(type.wireName),
                ),
                trailing: selectedType == type ? const Icon(Icons.check) : null,
                selected: selectedType == type,
                // Wrapped, because popping a bare null cannot be told apart
                // from the user dismissing the sheet.
                onTap: () => Navigator.pop(ctx, _TypeChoice(type)),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await _selectType(chosen.type);
  }

  void _tick() {
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
  }

  Future<void> _clearFilters() async {
    _tick();
    setState(() {
      selectedTagId = null;
      selectedType = null;
    });
    await _applyFilters();
  }

  bool get _filtering => selectedTagId != null || selectedType != null;

  /// FR-4.5: the content-type filter layers on top of the tag filter — it is
  /// not a separate mode, so both selections resolve into one view.
  List<Note> _visible(List<Note> source) {
    final tagId = selectedTagId;
    final type = selectedType;
    return source.where((note) {
      if (type != null && note.type != type) return false;
      if (tagId != null && !note.tags.any((t) => t.id == tagId)) return false;
      return true;
    }).toList();
  }

  Future<void> _applyFilters() async {
    final loaded = await widget.services.timeline(limit: 200);
    if (!mounted) return;
    setState(() { _all = loaded; notes = _visible(loaded); });
  }

  /// "A year ago today", opt-in and quiet by default. Loaded once rather than
  /// on every build: it is a database query, and build runs on every frame.
  Future<void> _loadAnniversary() async {
    if (!widget.preferences.quietAnniversary) return;
    final found = await widget.services.anniversary(DateTime.now());
    if (!mounted) return;
    setState(() => anniversary = found);
  }

  @override
  void dispose() {
    subscription?.cancel();
    _swipe.dispose();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> openCapture() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => CaptureSheet(
        services: widget.services,
        onCommitted: (id) { landedId = id; if (widget.preferences.haptics) HapticFeedback.lightImpact(); },
        onVoice: () { Navigator.pop(sheetContext); captureVoice(); },
        onCamera: () { Navigator.pop(sheetContext); capturePhoto(ImageSource.camera); },
        onGallery: () { Navigator.pop(sheetContext); capturePhoto(ImageSource.gallery); },
        onFile: () { Navigator.pop(sheetContext); captureFile(); },
      ),
    );
    widget.services.refreshTimeline();
  }

  Future<void> capturePhoto(ImageSource source) async {
    try {
      // Inside the try: this is the call that throws when the OS refuses the
      // camera or the photo library, which is the single most likely failure
      // and the one the old handler could not have caught.
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final dest = p.join(
        widget.services.mediaDir,
        'photo-${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}',
      );
      await File(dest).writeAsBytes(bytes, flush: true);
      final note = await widget.services.capturePhoto(
        mediaUri: dest,
        mediaBytes: Uint8List.fromList(bytes),
      );
      landedId = note.id;
      widget.services.scheduleEnrichment(note.id);
      if (widget.preferences.haptics) HapticFeedback.lightImpact();
      await widget.services.refreshTimeline();
    } catch (error) {
      // Not `catch (_)` with one sentence. Photo capture fails for at least
      // four unrelated reasons and three of them are things the user can do
      // something about — but only if the app says which one happened.
      if (mounted) _reportCaptureFailure(CaptureFailure.of(error), source);
    }
  }

  void _reportCaptureFailure(CaptureFailure failure, ImageSource source) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (failure) {
            CaptureFailure.permission => l10n.captureFailedPermission,
            CaptureFailure.storage => l10n.captureFailedStorage,
            CaptureFailure.unreadable => l10n.captureFailedUnreadable,
            CaptureFailure.unknown => l10n.captureFailed,
          }),
          action: SnackBarAction(
            label: l10n.retry,
            onPressed: () => unawaited(capturePhoto(source)),
          ),
        ),
      );
  }

  Future<void> captureVoice() async {
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) return recorder.dispose();
    final elapsed = Stopwatch()..start();
    final path = p.join(
      widget.services.mediaDir,
      'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await recorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    final keep = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      // The waveform needs the full sheet width and its own height, not the
      // half-screen default a content-sized sheet collapses to.
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RecordingSheet(recorder: recorder),
    );
    final recorded = await recorder.stop();
    elapsed.stop();
    await recorder.dispose();
    if (keep != true || recorded == null) { final file = File(path); if (file.existsSync()) file.deleteSync(); return; }
    final bytes = await File(recorded).readAsBytes();
    final note = await widget.services.captureVoice(
      mediaUri: recorded,
      mediaBytes: Uint8List.fromList(bytes),
      durationMs: elapsed.elapsedMilliseconds,
    );
    landedId = note.id;
    widget.services.scheduleEnrichment(note.id);
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    widget.services.refreshTimeline();
  }

  Future<void> captureFile() async {
    final picked = await OsCaptureBridge.pickFile();
    if (picked == null) return;
    await widget.osCapture?.handle({
      'type': 'shared_file', 'path': picked.path,
      'filename': picked.filename, 'mimeType': picked.mimeType,
    });
  }

  /// The non-destructive half of ADR-022's fixed action pair.
  /// Swipe-to-tag (FR-2.6).
  ///
  /// Offers the tags that exist rather than a bare text field, so tagging is
  /// picking from what you already use — the common case by a wide margin.
  Future<void> _addTagTo(Note note) async {
    final choice = await TagPickerSheet.show(
      context,
      tags: filterTags,
      alreadyOn: note.tags.map((t) => t.id).toSet(),
    );
    if (choice == null || !mounted) return;
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    await widget.services.addTag(
      noteId: note.id,
      name: choice.tag?.name ?? choice.name!,
      color: choice.color,
    );
    await widget.services.refreshTimeline();
    // A tag created here is new to the filter row too; without this it only
    // appeared after a restart.
    await _loadFilterTags();
  }

  Future<void> deleteWithUndo(Note note) async {
    final l10n = AppLocalizations.of(context);
    if (widget.preferences.haptics) HapticFeedback.mediumImpact();
    await widget.services.deleteNote(note.id);
    await widget.services.refreshTimeline();
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        // Shape, colour, inset and elevation all come from `snackBarTheme` now,
        // so this and the other nine toasts in the app are one capsule rather
        // than one hand-styled banner and nine framework defaults.
        duration: const Duration(seconds: 5),
        content: Row(children: [
          Icon(Icons.delete_outline,
              size: 20, color: theme.colorScheme.onInverseSurface),
          const SizedBox(width: NexSpacing.md),
          Expanded(child: Text(l10n.noteDeleted)),
        ]),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () async {
            _tick();
            await widget.services.undelete(note.id);
            await widget.services.refreshTimeline();
          },
        ),
      ));
  }

  /// "Nex", or a greeting if the user told the app their name.
  ///
  /// Decoration, deliberately kept to the one place the app already had a
  /// title. It says nothing, asks nothing and never appears outside the app —
  /// a greeting is not an engagement loop as long as it never leaves here.
  ///
  /// Three phrasings per time of day, with a mark in front. Fixed for the life
  /// of this screen rather than re-rolled on every build: the greeting is a
  /// title, and a title that changes while you are reading it is a bug, not a
  /// flourish. Opening the app again is what gets you a different one.
  /// The greeting, and the mark that goes after it — or null for neither.
  (String, String)? _greeting(AppLocalizations l10n) {
    final name = widget.preferences.displayName;
    if (name == null) return null;
    final v = _greetingVariant;
    final (glyphs, text) = switch (DateTime.now().hour) {
      >= 5 && < 12 => (
          const ['☀️', '🌱', '☕'],
          [l10n.greetingMorning, l10n.greetingMorningB, l10n.greetingMorningC],
        ),
      >= 12 && < 17 => (
          const ['🌤️', '🍵', '📌'],
          [
            l10n.greetingAfternoon,
            l10n.greetingAfternoonB,
            l10n.greetingAfternoonC,
          ],
        ),
      >= 17 && < 23 => (
          const ['🌆', '🌙', '🕯️'],
          [l10n.greetingEvening, l10n.greetingEveningB, l10n.greetingEveningC],
        ),
      _ => (
          const ['🦉', '🌚', '✨'],
          [l10n.greetingNight, l10n.greetingNightB, l10n.greetingNightC],
        ),
    };
    // Returned apart rather than joined into one string: the mark is animated,
    // so it has to be its own widget. Kept out of the text also puts it at the
    // trailing end in both directions for free — a Row is directional, where a
    // string is not.
    return (text[v](name), glyphs[v]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: switch (_greeting(l10n)) {
          null => Text(l10n.appTitle),
          (final text, final glyph) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: NexSpacing.sm),
                _GreetingGlyph(glyph),
              ],
            ),
        },
        actions: [
          // The same reveal the pull-down performs. Search is one interaction
          // and one surface now: it used to be a route push behind an
          // unlabelled icon, which put half the product's tagline a transition
          // away from the timeline it searches.
          IconButton(
            tooltip: l10n.search,
            icon: const Icon(Icons.search),
            onPressed: () => unawaited(revealSearch()),
          ),
          // Content lives here, preferences live behind the gear. Trash and
          // Tags were reachable only through Settings, and neither is a
          // preference — one of them holds the user's own deleted notes.
          IconButton(
            tooltip: l10n.libraryTitle,
            icon: const Icon(Icons.inventory_2_outlined),
            // Awaited, and the timeline reloads on the way back. Tags and
            // Trash both live behind here and both change what this screen
            // shows, and neither of them refreshes it on its own.
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => LibraryScreen(
                    services: widget.services,
                    preferences: widget.preferences,
                  ),
                ),
              );
              await _refresh();
            },
          ),
          _SettingsButton(
            updates: widget.updates,
            tooltip: l10n.settings,
            // useSafeArea keeps the sheet clear of the status bar; without it
            // the title sat flush against the top of the screen.
            onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true,
              useSafeArea: true, showDragHandle: true,
              builder: (_) => SettingsSheet(
                services: widget.services,
                preferences: widget.preferences,
                updates: widget.updates,
              )),
          ),
        ],
      ),
      // Android's back gesture leaves search before it leaves the screen.
      body: PopScope(
        canPop: !_searching,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitSearch();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // A tap anywhere that is not a card closes an open swipe.
          onTap: _swipe.closeAll,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Scrolling dismisses an open card, the way every list with
              // swipe actions behaves.
              if (notification is ScrollStartNotification) _swipe.closeAll();
              return false;
            },
            child: Center(
              // One column, and the filter row is inside it. It used to be a
              // sibling *above* this, so on a wide window the pills started at
              // the window edge while the cards sat in a 760px column — two
              // things that belong to each other, visibly unaligned.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  edgeOffset: nexSearchHeaderExtent,
                  child: CustomScrollView(
                  controller: _scroll,
                  // Always scrollable, so the pull works on a short list too —
                  // a refresh gesture that only exists once you have enough
                  // notes to scroll is a refresh gesture nobody finds.
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Both headers are always in the list, keyed, and collapse
                    // to zero extent rather than leaving it. A sliver list that
                    // changes length while another sliver changes its pinning
                    // leaves the viewport painting a child it never laid out.
                    SliverPersistentHeader(
                      key: const ValueKey('search-header'),
                      delegate: SearchFieldHeader(
                        controller: _search.query,
                        focusNode: _searchFocus,
                        searching: _searching,
                        onTap: () => unawaited(revealSearch()),
                        onChanged: (_) => _search.schedule(),
                        onClear: _exitSearch,
                      ),
                    ),
                    SliverPersistentHeader(
                      key: const ValueKey('filter-header'),
                      pinned: true,
                      delegate: _FilterRowHeader(
                        visible: !_searching,
                        child: TagFilterRow(
                          tags: filterTags,
                          selectedTagId: selectedTagId,
                          allLabel: l10n.all,
                          leading: _TypeFilterButton(
                            selected: selectedType,
                            onPressed: () => unawaited(_pickType()),
                          ),
                          onSelected: (value) => unawaited(_selectTag(value)),
                        ),
                      ),
                    ),
                    ..._bodySlivers(l10n),
                    // The capture button floats over the list, and on a
                    // device with a three-button navigation bar the system's
                    // own bar sits under that — the last card has to clear
                    // both, or it cannot be read or tapped.
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: nexFabClearance + nexBottomInset(context),
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: openCapture, tooltip: l10n.capture, child: const Icon(Icons.add, size: 32)),
    );
  }

  /// Whatever belongs under the chrome: results, skeletons, an empty state, or
  /// the timeline itself.
  List<Widget> _bodySlivers(AppLocalizations l10n) {
    if (_searching) {
      return searchResultSlivers(
        context: context,
        search: _search,
        onOpen: (note) => unawaited(_openNote(note)),
      );
    }

    // Three states, not two. "Not loaded yet" was indistinguishable from
    // "empty", which is why the onboarding screen flashed on every launch.
    final all = _all;
    if (all == null) {
      return [
        SliverList.builder(
          itemCount: 4,
          itemBuilder: (_, __) => const NexCardSkeleton(),
        ),
      ];
    }

    // The empty state belongs to an empty *library*, not an empty result. It
    // used to replace the whole body whenever a filter matched nothing, taking
    // the filter row with it — so the filter that caused it could not be
    // cleared without restarting the app.
    if (all.isEmpty && !_filtering) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: EmptyTimeline()),
      ];
    }
    if (notes.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _FilteredEmpty(onClear: () => unawaited(_clearFilters())),
        ),
      ];
    }

    return [
      if (anniversary.isNotEmpty)
        SliverToBoxAdapter(
          child: _AnniversaryRow(
            count: anniversary.length,
            onTap: () => unawaited(_showAnniversary()),
          ),
        ),
      SliverList.builder(
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return CommitReceipt(
            active: landedId == note.id,
            // Cleared when it finishes, so the receipt is a moment rather than
            // a permanent mark on whichever note was captured last.
            onDone: () {
              if (mounted && landedId == note.id) {
                setState(() => landedId = null);
              }
            },
            // ADR-022: the action set is open, and each edge is bound
            // independently.
            child: SwipeableNoteCard(
              deleteLabel: l10n.delete,
              addTagLabel: l10n.addTag,
              haptics: widget.preferences.haptics,
              controller: _swipe,
              resolveAction: ({required bool isLeading}) {
                final action = isLeading
                    ? widget.preferences.leadingAction
                    : widget.preferences.trailingAction;
                return switch (action) {
                  SwipeAction.none => null,
                  SwipeAction.delete => NexSwipeAction.delete,
                  SwipeAction.addTag => NexSwipeAction.addTag,
                };
              },
              onDelete: () => unawaited(deleteWithUndo(note)),
              onAddTag: () => unawaited(_addTagTo(note)),
              child: NoteCard(
                note: note,
                strings: nexCardStrings(context),
                onTap: () => unawaited(_openNote(note)),
              ),
            ),
          );
        },
      ),
    ];
  }

  Future<void> _openNote(Note note) async {
    final result = await showModalBottomSheet<DetailResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          NoteDetailSheet(services: widget.services, noteId: note.id),
    );
    if (result == DetailResult.deleted) await deleteWithUndo(note);
    await widget.services.refreshTimeline();
    // The sheet can create a tag; the filter row has to learn about it without
    // an app restart.
    await _loadFilterTags();
    if (_searching) await _search.run();
  }

  /// Shows only what was captured a year ago today.
  ///
  /// The line used to be inert text: the app's one resurfacing feature, with no
  /// way to act on what it announced.
  Future<void> _showAnniversary() async {
    _tick();
    setState(() {
      selectedTagId = null;
      selectedType = null;
      final ids = anniversary.map((n) => n.id).toSet();
      notes = (_all ?? const []).where((n) => ids.contains(n.id)).toList();
    });
  }
}

/// Keeps the filter row under the app bar while the cards scroll past it.
/// The greeting's mark, which arrives rather than appearing.
///
/// It plays once, when the screen opens and whenever the glyph itself changes
/// — not on a loop. A permanently moving element on the main screen of an app
/// whose whole promise is not demanding your attention would be the wrong
/// thing, and a repeating controller is also what makes `pumpAndSettle` never
/// return, so the tests could not pump past it either.
///
/// Reduce motion skips it entirely: the glyph is simply there.
class _GreetingGlyph extends StatefulWidget {
  const _GreetingGlyph(this.glyph);

  final String glyph;

  @override
  State<_GreetingGlyph> createState() => _GreetingGlyphState();
}

class _GreetingGlyphState extends State<_GreetingGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NexMotion.slow,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_GreetingGlyph old) {
    super.didUpdateWidget(old);
    if (old.glyph != widget.glyph &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeOutBack.transform(_controller.value);
          return Transform.rotate(
            // A small wave that unwinds as it settles, rather than a pulse:
            // the glyph reads as greeting you, which is what the line says.
            angle: (1 - _controller.value) * 0.5,
            child: Transform.scale(scale: 0.4 + 0.6 * t, child: child),
          );
        },
        child: Text(widget.glyph),
      );
}

class _FilterRowHeader extends SliverPersistentHeaderDelegate {
  const _FilterRowHeader({required this.child, required this.visible});

  final Widget child;

  /// Searching hides it, by collapsing rather than by leaving the sliver list.
  final bool visible;

  // The row's own height: a 48px target plus the padding TagFilterRow carries.
  static const _extent = nexMinTapTarget + NexSpacing.md + NexSpacing.sm;

  @override
  double get minExtent => visible ? _extent : 0;

  @override
  double get maxExtent => visible ? _extent : 0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);

  @override
  /// Always, and for the same reason as [SearchFieldHeader].
  ///
  /// This one happened to rebuild anyway, because `child` is a fresh
  /// `TagFilterRow` on every build and the comparison is by identity — so it
  /// escaped the stale-theme bug by accident rather than by design. Relying on
  /// that is relying on a widget never gaining an `operator ==`.
  @override
  bool shouldRebuild(_FilterRowHeader old) => true;
}

/// "One year ago", as something you can act on.
///
/// It was a 12.5px grey sentence with no container, no icon and no gesture
/// detector — the single most valuable thing a capture app can show you,
/// rendered as the least prominent thing on the screen.
class _AnniversaryRow extends StatelessWidget {
  const _AnniversaryRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: nexCardInsets,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.md),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.md,
              vertical: NexSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.history_toggle_off,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.oneYearAgo(count),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
/// Wraps the picker's answer so "All" survives the trip back through
/// `Navigator.pop`, which cannot distinguish a null result from a dismissal.
class _TypeChoice {
  const _TypeChoice(this.type);
  final NoteType? type;
}

/// The mockup's leading icon button on the filter row.
///
/// Carries a dot when a content type is filtering, so an active filter is
/// visible without opening the sheet.
class _TypeFilterButton extends StatelessWidget {
  const _TypeFilterButton({required this.selected, required this.onPressed});

  final NoteType? selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = selected != null;
    return NexTappable(
      onTap: onPressed,
      selected: active,
      semanticLabel: AppLocalizations.of(context).filters,
      shape: const StadiumBorder(),
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerLowest,
        shape: StadiumBorder(
          side: BorderSide(color: active ? scheme.primary : scheme.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.contentGap - NexSpacing.xs,
            vertical: NexSpacing.sm,
          ),
          child: Icon(
            Icons.tune,
            size: 18,
            color: active ? scheme.primary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Shown when a filter matches nothing.
///
/// Distinct from [EmptyTimeline], which promises the library keeps whatever you
/// put in it — a promise that would read as a lie next to notes the filter is
/// merely hiding.
class _FilteredEmpty extends StatelessWidget {
  const _FilteredEmpty({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_list_off,
            size: 36,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(l10n.noteCount(0), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          TextButton(onPressed: onClear, child: Text(l10n.clear)),
        ],
      ),
    );
  }
}

/// The settings icon, with a dot when an update is waiting.
///
/// A dot rather than a notification or a dialog: the release is not urgent and
/// nothing about it should interrupt a capture. Settings is where a person
/// goes to look, so that is where the app says there is something to see.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({
    required this.updates,
    required this.tooltip,
    required this.onPressed,
  });

  final UpdateService? updates;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final service = updates;
    final button = IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.settings_outlined),
      onPressed: onPressed,
    );
    if (service == null) return button;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          button,
          if (service.hasUpdate)
            const PositionedDirectional(
              top: 12,
              end: 10,
              child: IgnorePointer(child: NexBadgeDot()),
            ),
        ],
      ),
    );
  }
}
