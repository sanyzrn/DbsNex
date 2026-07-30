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
import '../widgets/photo_editor.dart';
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
  final UpdateService? updates;
  @override
  State<TimelineScreen> createState() => TimelineScreenState();
}

class TimelineScreenState extends State<TimelineScreen> {
  List<Note>? _all;
  List<Note> notes = const [];
  final NexSwipeController _swipe = NexSwipeController();
  List<Tag> filterTags = const [];
  String? selectedTagId;
  NoteType? selectedType;
  StreamSubscription<List<Note>>? subscription;
  String? landedId;
  final ScrollController _scroll = ScrollController();
  late final NoteSearchController _search =
      NoteSearchController(services: widget.services);
  final FocusNode _searchFocus = FocusNode();
  final int _greetingVariant = math.Random().nextInt(3);
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    subscription = widget.services.timelineStream.listen((value) {
      if (!mounted) return;
      setState(() {
        _all = value;
        notes = _visible(value);
      });
      unawaited(_loadFilterTags());
    });
    _search.addListener(_onSearchChanged);
    unawaited(_loadTimeline());
    unawaited(_loadFilterTags());
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @visibleForTesting
  void markLanded(String id) => setState(() => landedId = id);

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
  }

  Future<void> _loadTimeline() async {
    final loaded = await widget.services.timeline(limit: 200);
    if (!mounted) return;
    setState(() {
      _all = loaded;
      notes = _visible(loaded);
    });
  }

  Future<void> _loadFilterTags() async {
    final loaded = await widget.services.tagUsage();
    if (!mounted) return;
    setState(() {
      filterTags = [
        for (final usage in loaded)
          if (usage.count > 0) usage.tag,
      ];
    });
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await Future.wait([
      widget.services.refreshTimeline(),
      _loadFilterTags(),
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
    setState(() {
      _all = loaded;
      notes = _visible(loaded);
    });
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
        onCommitted: (id) {
          landedId = id;
          if (widget.preferences.haptics) HapticFeedback.lightImpact();
        },
        onVoice: () {
          Navigator.pop(sheetContext);
          captureVoice();
        },
        onCamera: () {
          Navigator.pop(sheetContext);
          capturePhoto(ImageSource.camera);
        },
        onGallery: () {
          Navigator.pop(sheetContext);
          capturePhoto(ImageSource.gallery);
        },
        onFile: () {
          Navigator.pop(sheetContext);
          captureFile();
        },
      ),
    );
    widget.services.refreshTimeline();
  }

  Future<void> capturePhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      if (!mounted) return;

      // Item 4: crop + optional markup in-app before saving.
      final edited = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute<Uint8List>(
          builder: (_) => PhotoEditorScreen(sourcePath: picked.path),
          fullscreenDialog: true,
        ),
      );
      if (edited == null) return; // user cancelled crop/markup

      final dest = p.join(
        widget.services.mediaDir,
        'photo-${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await File(dest).writeAsBytes(edited, flush: true);
      final note = await widget.services.capturePhoto(
        mediaUri: dest,
        mediaBytes: Uint8List.fromList(edited),
      );
      landedId = note.id;
      widget.services.scheduleEnrichment(note.id);
      if (widget.preferences.haptics) HapticFeedback.lightImpact();
      await widget.services.refreshTimeline();
    } catch (error) {
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
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RecordingSheet(recorder: recorder),
    );
    final recorded = await recorder.stop();
    elapsed.stop();
    await recorder.dispose();
    if (keep != true || recorded == null) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
      return;
    }
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
      'type': 'shared_file',
      'path': picked.path,
      'filename': picked.filename,
      'mimeType': picked.mimeType,
    });
  }

  /// Swipe-to-tag (FR-2.6).
  ///
  /// ITEM 1 FIX: fetches the global tag list (services.listTags()) so the
  /// picker shows every existing tag, matching the Note Detail path. It used
  /// to read the local `filterTags` list, which is derived from
  /// `services.tagUsage()` filtered to `count > 0` — so a note with zero
  /// tags meant an empty picker even when tags existed system-wide.
  Future<void> _addTagTo(Note note) async {
    final all = await widget.services.listTags();
    if (!mounted) return;
    final choice = await TagPickerSheet.show(
      context,
      tags: all,
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
      >= 17 && < 22 => (
        const ['🌆', '🌙', '🕯️'],
        [l10n.greetingEvening, l10n.greetingEveningB, l10n.greetingEveningC],
      ),
      _ => (
        const ['🦉', '🌚', '✨'],
        [l10n.greetingNight, l10n.greetingNightB, l10n.greetingNightC],
      ),
    };
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
          IconButton(
            tooltip: l10n.libraryTitle,
            icon: const Icon(Icons.inventory_2_outlined),
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
            onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => SettingsSheet(
                      services: widget.services,
                      preferences: widget.preferences,
                      updates: widget.updates,
                    )),
          ),
        ],
      ),
      body: PopScope(
        canPop: !_searching,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitSearch();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _swipe.closeAll,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification) _swipe.closeAll();
              return false;
            },
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  edgeOffset: nexSearchHeaderExtent,
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
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
                            onSelected: (value) =>
                                unawaited(_selectTag(value)),
                          ),
                        ),
                      ),
                      ..._bodySlivers(l10n),
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
          onPressed: openCapture,
          tooltip: l10n.capture,
          child: const Icon(Icons.add, size: 32)),
    );
  }

  List<Widget> _bodySlivers(AppLocalizations l10n) {
    if (_searching) {
      return searchResultSlivers(
        context: context,
        search: _search,
        onOpen: (note) => unawaited(_openNote(note)),
      );
    }
    final all = _all;
    if (all == null) {
      return [
        SliverList.builder(
          itemCount: 4,
          itemBuilder: (_, __) => const NexCardSkeleton(),
        ),
      ];
    }
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
      SliverList.builder(
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return CommitReceipt(
            active: landedId == note.id,
            onDone: () {
              if (mounted && landedId == note.id) {
                setState(() => landedId = null);
              }
            },
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
                onTap: () => _tapNote(note),
              ),
            ),
          );
        },
      ),
    ];
  }

  void _tapNote(Note note) {
    if (_swipe.openCard != null) {
      _swipe.closeAll();
      return;
    }
    unawaited(_openNote(note));
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
    await _loadFilterTags();
    if (_searching) await _search.run();
  }
}

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
  final bool visible;
  static const _extent = nexMinTapTarget + NexSpacing.md + NexSpacing.sm;
  @override
  double get minExtent => visible ? _extent : 0;
  @override
  double get maxExtent => visible ? _extent : 0;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);
  @override
  bool shouldRebuild(_FilterRowHeader old) => true;
}

class _TypeChoice {
  const _TypeChoice(this.type);
  final NoteType? type;
}

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
