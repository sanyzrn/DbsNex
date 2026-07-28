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
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/os_capture_bridge.dart';
import '../platform/update_service.dart';
import 'package:nex_data/nex_data.dart';
import '../widgets/capture_sheet.dart';
import '../widgets/card_strings.dart';
import '../widgets/empty_timeline.dart';
import '../widgets/recording_sheet.dart';
import '../widgets/tag_picker.dart';
import 'note_detail_sheet.dart';
import 'search_screen.dart';
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
  /// The screen used to hold only the filtered list, so the next stream event —
  /// which a capture triggers — replaced it with the unfiltered one while the
  /// filter chips still claimed to be active.
  List<Note> _all = const [];
  List<Note> notes = const [];

  /// Keeps one card open at a time and lets a scroll close it.
  final NexSwipeController _swipe = NexSwipeController();
  List<Note> anniversary = const [];
  List<Tag> filterTags = const [];
  String? selectedTagId;
  NoteType? selectedType;
  StreamSubscription<List<Note>>? subscription;
  String? landedId;

  @override
  void initState() {
    super.initState();
    subscription = widget.services.timelineStream.listen((value) {
      if (mounted) setState(() { _all = value; notes = _visible(value); });
    });
    unawaited(_loadTimeline());
    unawaited(_loadAnniversary());
    unawaited(_loadFilterTags());
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
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    try {
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).captureFailed)),
        );
      }
    }
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
          IconButton(tooltip: l10n.search, icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => SearchScreen(services: widget.services)))),
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
      // The empty state belongs to an empty *library*, not an empty result.
      // It used to replace the whole body whenever a filter matched nothing,
      // taking the filter row with it — so the filter that caused it could not
      // be cleared without restarting the app.
      body: _all.isEmpty && !_filtering
          ? const EmptyTimeline()
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              // A tap anywhere that is not a card closes an open swipe.
              onTap: _swipe.closeAll,
              child: Column(children: [
              // One filter row, as in the mockup: the icon button leads it and
              // holds the content-type filter, so the timeline keeps a single
              // row of pills rather than stacking a second one under it.
              TagFilterRow(
                tags: filterTags,
                selectedTagId: selectedTagId,
                allLabel: l10n.all,
                leading: _TypeFilterButton(
                  selected: selectedType,
                  onPressed: () => unawaited(_pickType()),
                ),
                onSelected: (value) => unawaited(_selectTag(value)),
              ),
              Expanded(child: notes.isEmpty
                  ? _FilteredEmpty(onClear: () => unawaited(_clearFilters()))
                  : NotificationListener<ScrollStartNotification>(
                      // Scrolling dismisses an open card, the way every list
                      // with swipe actions behaves.
                      onNotification: (_) {
                        _swipe.closeAll();
                        return false;
                      },
                      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: nexFabClearance),
            itemCount: notes.length + (anniversary.isEmpty ? 0 : 1),
            itemBuilder: (context, index) {
              if (anniversary.isNotEmpty && index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.md,
                    vertical: NexSpacing.md,
                  ),
                  child: Text(l10n.oneYearAgo(anniversary.length), style: Theme.of(context).textTheme.bodySmall),
                );
              }
              final note = notes[index - (anniversary.isEmpty ? 0 : 1)];
              return AnimatedSlide(
                offset: landedId == note.id && !MediaQuery.disableAnimationsOf(context)
                    ? const Offset(0, -0.02) : Offset.zero,
                duration: NexMotion.standard,
                // ADR-022: exactly two actions, and only which edge triggers
                // which is configurable. SwipeableNoteCard shipped in
                // packages/ui but nothing ever wrapped a card in it, so the
                // gesture did not exist in the app at all.
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
                    onTap: () async {
                      final result = await showModalBottomSheet<DetailResult>(
                        context: context, isScrollControlled: true, useSafeArea: true,
                        showDragHandle: true,
                        builder: (_) => NoteDetailSheet(services: widget.services, noteId: note.id),
                      );
                      if (result == DetailResult.deleted) {
                        await deleteWithUndo(note);
                      }
                      await widget.services.refreshTimeline();
                      // The sheet can create a tag; the filter row has to
                      // learn about it without an app restart.
                      await _loadFilterTags();
                    },
                  ),
                ),
              );
            },
          ),
        ),
              ))),
            ]),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: openCapture, tooltip: l10n.capture, child: const Icon(Icons.add, size: 32)),
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
