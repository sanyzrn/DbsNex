import 'dart:async';
import 'dart:io';
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

  /// Starts past the search field so it sits just out of sight. Revealing it is
  /// then ordinary scrolling, which behaves the same under Android's clamping
  /// physics and iOS's bouncing ones — an overscroll effect would not.
  final ScrollController _scroll =
      ScrollController(initialScrollOffset: nexSearchHeaderExtent);

  late final NoteSearchController _search =
      NoteSearchController(services: widget.services);
  final FocusNode _searchFocus = FocusNode();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    subscription = widget.services.timelineStream.listen((value) {
      if (mounted) setState(() { _all = value; notes = _visible(value); });
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
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          nexSearchHeaderExtent.clamp(0, _scroll.position.maxScrollExtent),
          duration: NexMotion.standard,
          curve: NexMotion.curve,
        ),
      );
    }
  }

  /// Snaps the half-revealed field open or shut when the finger lifts.
  ///
  /// `animateTo` takes a duration and a curve rather than a simulation; getting
  /// a spring in here would mean a custom [ScrollActivity] for a 60px travel
  /// nobody could tell apart.
  bool _snapSearchHeader(ScrollEndNotification notification) {
    if (_searching || !_scroll.hasClients) return false;
    final offset = _scroll.offset;
    if (offset <= 0 || offset >= nexSearchHeaderExtent) return false;
    final target =
        offset < nexSearchHeaderExtent / 2 ? 0.0 : nexSearchHeaderExtent;
    // Scheduled, because a scroll cannot be started from inside the
    // notification that ended the last one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          target,
          duration: NexMotion.fast,
          curve: NexMotion.curve,
        ),
      );
    });
    return false;
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
        // Floating, rounded and inset so it reads as part of the surface
        // rather than a system banner pinned to the bottom edge.
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 6,
        duration: const Duration(seconds: 5),
        backgroundColor: theme.colorScheme.inverseSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexColors.cardRadius),
        ),
        content: Row(children: [
          Icon(Icons.delete_outline,
              size: 20, color: theme.colorScheme.onInverseSurface),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.noteDeleted,
              style: TextStyle(color: theme.colorScheme.onInverseSurface),
            ),
          ),
        ]),
        action: SnackBarAction(
          label: l10n.undo,
          textColor: theme.colorScheme.inversePrimary,
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
  String _title(AppLocalizations l10n) {
    final name = widget.preferences.displayName;
    if (name == null) return l10n.appTitle;
    return switch (DateTime.now().hour) {
      >= 5 && < 12 => l10n.greetingMorning(name),
      >= 12 && < 17 => l10n.greetingAfternoon(name),
      >= 17 && < 23 => l10n.greetingEvening(name),
      _ => l10n.greetingNight(name),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(l10n)),
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LibraryScreen(
                  services: widget.services,
                  preferences: widget.preferences,
                ),
              ),
            ),
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
              if (notification is ScrollEndNotification) {
                return _snapSearchHeader(notification);
              }
              return false;
            },
            child: Center(
              // One column, and the filter row is inside it. It used to be a
              // sibling *above* this, so on a wide window the pills started at
              // the window edge while the cards sat in a 760px column — two
              // things that belong to each other, visibly unaligned.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: CustomScrollView(
                  controller: _scroll,
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
                    const SliverToBoxAdapter(
                      child: SizedBox(height: nexFabClearance),
                    ),
                  ],
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
  bool shouldRebuild(_FilterRowHeader old) =>
      old.child != child || old.visible != visible;
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
