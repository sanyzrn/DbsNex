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
import '../feature_flags.dart';
import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/capture_failure.dart';
import '../platform/link_reader.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/note_search.dart';
import '../platform/os_capture_bridge.dart';
import '../platform/update_service.dart';
import '../widgets/capture_sheet.dart';
import '../widgets/checklist_capture_sheet.dart';
import '../widgets/card_strings.dart';
import '../widgets/commit_receipt.dart';
import '../widgets/empty_timeline.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_banner.dart';
import '../widgets/recording_sheet.dart';
import '../widgets/search_field_header.dart';
import '../widgets/search_results.dart';
import '../widgets/tag_picker.dart';
import 'library_screen.dart';
import 'note_detail_sheet.dart';
import 'photo_crop_screen.dart';
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

  /// The index [_onReorderStart] captured, compared against the index
  /// [_onReorderEnd] is handed to tell a hold-and-release apart from an
  /// actual drag — see the doc comment on [_onReorderEnd] for why this has
  /// to be a direct index comparison rather than waiting on [_onReorder].
  int? _reorderStartIndex;
  List<Tag> filterTags = const [];
  String? selectedTagId;
  NoteType? selectedType;
  StreamSubscription<List<Note>>? subscription;
  String? landedId;

  /// Guards against firing a second [NexServices.loadMoreTimeline] while one
  /// is still in flight, and against firing one at all once a fetch has come
  /// back empty — a finger held past the bottom during the overscroll bounce
  /// delivers a scroll notification per frame, not one per gesture.
  bool _loadingMore = false;
  bool _exhausted = false;

  /// Starts at the top, with the search field in view.
  ///
  /// It used to start scrolled past the field, so that pulling down revealed
  /// it. That never worked in practice and the gesture is now a refresh, which
  /// needs the list to begin at offset zero — otherwise the first pull spends
  /// itself scrolling back up.
  final ScrollController _scroll = ScrollController();

  late final NoteSearchController _search = NoteSearchController(
    services: widget.services,
  );
  final FocusNode _searchFocus = FocusNode();

  /// Which of the three fallback greetings is showing. Re-rolled, not fixed,
  /// because tapping the headline refreshes it — see [_refreshHeadline]. With
  /// no AI provider that re-roll *is* the refresh.
  int _greetingVariant = math.Random().nextInt(3);
  bool _searching = false;

  /// The AI-generated recap under the headline — see [_loadAiSummary].
  String? _aiSummaryText;
  bool _aiSummaryLoading = false;

  /// The AI-generated line across the top — see [_loadAiHeadline].
  String? _aiHeadlineText;
  bool _aiHeadlineLoading = false;

  /// Collapsed hides the recap's *body*; the card's header row, and with it
  /// the chevron that reopens it, stays on screen either way. It used to
  /// collapse to nothing and reopen from a chip in the app bar — a control
  /// nowhere near the thing it controlled.
  bool _aiSummaryCollapsed = false;

  /// The first real scroll collapses the card on its own, once. Touching the
  /// chevron takes that over: an explicit open should not be undone by the
  /// scroll that follows it.
  bool _aiSummaryToggledByUser = false;

  /// Requesting either string is a cold-launch thing, not a per-note-change
  /// thing — without this latch, every capture re-firing [timelineStream]
  /// would ask the provider again.
  bool _aiSummaryRequested = false;

  @override
  void initState() {
    super.initState();
    subscription = widget.services.timelineStream.listen((value) {
      if (!mounted) return;
      setState(() {
        _all = value;
        notes = _visible(value);
      });
      // A capture or a delete can change whether there is more to load —
      // most obviously a capture, past a window an earlier scroll had
      // already exhausted. Re-arming here costs one wasted fetch on the next
      // scroll-to-bottom when it turns out nothing changed; leaving it stuck
      // costs a note nobody can ever scroll to.
      _exhausted = false;
      // The filter row is fed by a separate query that only ran once, at
      // startup. Creating or deleting a tag anywhere in the app left the row
      // showing the old set until the next cold launch — which is exactly the
      // "I had to restart it" report. Every mutation path already refreshes
      // the timeline, so this is the one place that has to notice.
      unawaited(_loadFilterTags());
      if (!_aiSummaryRequested && value.isNotEmpty) {
        _aiSummaryRequested = true;
        unawaited(_loadAiSummary());
        unawaited(_loadAiHeadline());
      }
    });
    _search.addListener(_onSearchChanged);
    _scroll.addListener(_onAiSummaryScroll);
    unawaited(_loadTimeline());
    unawaited(_loadFilterTags());
  }

  /// True when there is a provider configured to generate anything at all.
  /// The whole header — headline and card both — is absent otherwise, rather
  /// than showing empty chrome for a feature that is switched off.
  bool get _aiHeaderAvailable =>
      widget.preferences.aiEnabled && widget.preferences.aiProvider.isUsable;

  /// Builds an adapter with the user's chosen output language applied.
  ///
  /// Every call site here closes it; the caller owning the lifetime is why
  /// this is a factory and not a field.
  CloudAIAdapter _aiAdapter() => CloudAIAdapter(
    config: widget.preferences.aiProvider,
    outputLanguage: widget.preferences.aiOutputLanguage,
  );

  /// Fetches (or restores) today's recap. Called once, the first time the
  /// timeline stream delivers any notes — see [_aiSummaryRequested].
  ///
  /// Silently does nothing when AI is off or unconfigured: this panel is
  /// additive chrome, never a reason to show an error on the app's home
  /// screen. A failed or empty reply leaves the card's empty line showing.
  ///
  /// [force] skips the cache — it is what the card's refresh button does.
  /// Without it, tapping refresh on a day whose text was already stored would
  /// have re-read the same string and looked broken.
  Future<void> _loadAiSummary({bool force = false}) async {
    final prefs = widget.preferences;
    if (!_aiHeaderAvailable) return;
    final today = _aiSummaryDateKey();
    if (!force && prefs.aiDaySummaryDate == today) {
      final cached = prefs.aiDaySummaryText;
      if (mounted && cached != null && cached.isNotEmpty) {
        setState(() => _aiSummaryText = cached);
      }
      return;
    }
    final source = _aiSummarySource();
    if (source.isEmpty) return;
    if (mounted) setState(() => _aiSummaryLoading = true);
    final adapter = _aiAdapter();
    String? text;
    try {
      text = await adapter.digest(source);
    } catch (_) {
      text = null;
    } finally {
      adapter.close();
    }
    if (!mounted) return;
    setState(() {
      _aiSummaryLoading = false;
      // A failed refresh keeps whatever was already on screen. Blanking a
      // recap that is still perfectly readable because the network dropped
      // would be the tap actively destroying something.
      if (text != null && text.isNotEmpty) _aiSummaryText = text;
    });
    if (text != null && text.isNotEmpty) {
      unawaited(prefs.setAiDaySummary(text: text, dateKey: today));
    }
  }

  /// The headline over the timeline. Same shape as [_loadAiSummary] — cached
  /// per day, forced by a tap on the line itself.
  Future<void> _loadAiHeadline({bool force = false}) async {
    final prefs = widget.preferences;
    if (!_aiHeaderAvailable) return;
    final today = _aiSummaryDateKey();
    if (!force && prefs.aiHeadlineDate == today) {
      final cached = prefs.aiHeadlineText;
      if (mounted && cached != null && cached.isNotEmpty) {
        setState(() => _aiHeadlineText = cached);
      }
      return;
    }
    if (mounted) setState(() => _aiHeadlineLoading = true);
    final adapter = _aiAdapter();
    String? text;
    try {
      // Unlike the recap, an empty library is not a reason to skip this: the
      // line is a mood, and "you have not written anything yet" is a mood the
      // prompt handles on its own.
      text = await adapter.headline(_aiSummarySource());
    } catch (_) {
      text = null;
    } finally {
      adapter.close();
    }
    if (!mounted) return;
    setState(() {
      _aiHeadlineLoading = false;
      if (text != null && text.isNotEmpty) _aiHeadlineText = text;
    });
    if (text != null && text.isNotEmpty) {
      unawaited(prefs.setAiHeadline(text: text, dateKey: today));
    }
  }

  /// Tapping the headline asks for a new one.
  ///
  /// With no provider configured there is still something to refresh — the
  /// local greeting has three phrasings per time of day, and re-rolling one
  /// is what the same tap does. A tap target that does nothing on half the
  /// installs would be worse than not having it.
  void _refreshHeadline() {
    _tick();
    if (_aiHeaderAvailable) {
      unawaited(_loadAiHeadline(force: true));
      return;
    }
    setState(() {
      // Never the one already showing: a refresh that lands on the same words
      // one time in three reads as a broken button.
      _greetingVariant = (_greetingVariant + 1 + math.Random().nextInt(2)) % 3;
    });
  }

  void _toggleAiSummary() {
    _tick();
    setState(() {
      _aiSummaryToggledByUser = true;
      _aiSummaryCollapsed = !_aiSummaryCollapsed;
    });
  }

  String _aiSummaryDateKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// The most recent notes' own text, newest first — plenty for a recap to
  /// say something real without sending the whole library on every launch.
  String _aiSummarySource() {
    final recent = (_all ?? notes).take(20);
    final lines = <String>[
      for (final note in recent)
        (note.content ?? note.transcriptText ?? note.ocrText ?? '').trim(),
    ]..removeWhere((line) => line.isEmpty);
    return lines.join('\n');
  }

  /// Collapses the card's body on the first real scroll, the way the Figma
  /// redesign asked for — reading a note is not the moment for a recap.
  ///
  /// Gives way to the chevron entirely: once the user has worked the control
  /// by hand, scrolling stops having an opinion about it.
  void _onAiSummaryScroll() {
    if (_aiSummaryCollapsed || _aiSummaryToggledByUser) return;
    if (_scroll.offset > 4) setState(() => _aiSummaryCollapsed = true);
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
  /// Tapping the field itself does this, and so does Ctrl+F — the field lives
  /// at the top of the list permanently now, so a dedicated AppBar icon for it
  /// pointed at something already on screen.
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
    setState(() {
      _all = loaded;
      notes = _visible(loaded);
    });
  }

  /// FR-4 filter chips. TagFilterRow shipped in packages/ui, complete and
  /// covered by its own test, but nothing ever imported it — the timeline had
  /// no way to filter at all.
  ///
  /// Built from usage counts rather than the bare tag list: a tag nothing is
  /// tagged with anymore (its last note deleted, or created and never used)
  /// was still showing up as a pill that filtered to an empty list.
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
    final banner = NexBannerHost.of(context);
    final l10n = AppLocalizations.of(context);
    await Future.wait([widget.services.refreshTimeline(), _loadFilterTags()]);
    if (widget.preferences.syncBaseUrl == null) return;
    try {
      await widget.services.syncNow();
    } catch (_) {
      if (!mounted) return;
      banner?.show(message: l10n.operationFailed, kind: NexBannerKind.failed);
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
    final chosen = await nexShowSheet<_TypeChoice>(
      context: context,
      builder: (ctx) => Column(
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

  /// Grows the timeline window when the list is close to its end.
  ///
  /// Not while searching — search results are their own query, not
  /// [NexServices.loadMoreTimeline]'s window. The result reaches [notes]
  /// through the same stream subscription every other mutation already goes
  /// through, so there is nothing to do here with what comes back beyond
  /// remembering whether it was empty.
  void _maybeLoadMore() {
    if (_searching || _loadingMore || _exhausted) return;
    _loadingMore = true;
    unawaited(
      widget.services
          .loadMoreTimeline()
          .then((more) => _exhausted = !more)
          .whenComplete(() => _loadingMore = false),
    );
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
    _scroll.removeListener(_onAiSummaryScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> openCapture() async {
    await nexShowSheet<void>(
      context: context,
      builder: (sheetContext) => CaptureSheet(
        services: widget.services,
        preferences: widget.preferences,
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
        onChecklist: () {
          Navigator.pop(sheetContext);
          unawaited(captureChecklist());
        },
        onLink: () {
          Navigator.pop(sheetContext);
          unawaited(captureLink());
        },
      ),
    );
    widget.services.refreshTimeline();
  }

  /// Opens the checklist sheet and commits whatever came back.
  ///
  /// Same shape as every other capture path here: the sheet decides *what*,
  /// this decides that it is kept. A dismissed sheet returns null and nothing
  /// is written — the one place in Nex where a capture can be abandoned, and
  /// only because nothing was committed in the first place.
  Future<void> captureChecklist() async {
    final items = await nexShowSheet<List<ChecklistItem>>(
      context: context,
      builder: (_) => ChecklistCaptureSheet(preferences: widget.preferences),
    );
    if (items == null || items.isEmpty) return;
    final note = await widget.services.captureChecklist(items);
    if (note != null) _landed(note.id);
    await widget.services.refreshTimeline();
  }

  Future<void> captureLink() async {
    final url = await nexShowSheet<String>(
      context: context,
      builder: (_) => LinkCaptureSheet(preferences: widget.preferences),
    );
    if (url == null) return;
    final note = await widget.services.captureLink(url);
    if (note != null) {
      _landed(note.id);
      // The page is read after the note exists, never before: a bookmark is
      // saved the moment you ask for it, and the title and description are an
      // improvement that arrives late or not at all.
      unawaited(_readLink(note.id, url));
    }
    await widget.services.refreshTimeline();
  }

  void _landed(String id) {
    if (!mounted) return;
    setState(() => landedId = id);
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
  }

  /// Reads the page a link note points at, and asks the provider to summarise
  /// it if one is configured.
  ///
  /// Never awaited by the capture path and never able to fail it: the note is
  /// already saved by the time this runs, and every outcome here — offline, a
  /// 404, a page with no title, no AI provider — leaves a link note that still
  /// opens. The two halves are independent, so a page that reads fine but
  /// cannot be summarised still gets its title.
  Future<void> _readLink(String noteId, String url) async {
    final reader = LinkReader();
    LinkPreview preview;
    try {
      preview = await reader.read(url);
    } finally {
      reader.close();
    }
    if (!preview.isEmpty) {
      await widget.services.setLinkMetadata(
        noteId,
        title: preview.title,
        excerpt: preview.excerpt,
      );
      if (mounted) await widget.services.refreshTimeline();
    }

    if (!_aiHeaderAvailable) return;
    // The page's own words are what gets summarised, never the URL — a bare
    // address tells a model nothing, and sending one would spend a request to
    // be told so.
    final source = [
      preview.title,
      preview.excerpt,
    ].whereType<String>().join('\n');
    if (source.trim().isEmpty) return;
    final adapter = _aiAdapter();
    try {
      final summary = await adapter.digest(source);
      if (summary != null && summary.isNotEmpty) {
        await widget.services.summarizeInto(noteId, summary);
        if (mounted) await widget.services.refreshTimeline();
      }
    } catch (_) {
      // A bookmark that could not be summarised is still a bookmark.
    } finally {
      adapter.close();
    }
  }

  Future<void> capturePhoto(ImageSource source) async {
    try {
      // Inside the try: this is the call that throws when the OS refuses the
      // camera or the photo library, which is the single most likely failure
      // and the one the old handler could not have caught.
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      final original = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => PhotoCropScreen(image: original)),
      );
      if (cropped == null) return;
      final dest = p.join(
        widget.services.mediaDir,
        'photo-${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}',
      );
      await File(dest).writeAsBytes(cropped, flush: true);
      final note = await widget.services.capturePhoto(
        mediaUri: dest,
        mediaBytes: cropped,
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
    nexShowBanner(
      context,
      kind: NexBannerKind.failed,
      haptics: widget.preferences.haptics,
      message: switch (failure) {
        CaptureFailure.permission => l10n.captureFailedPermission,
        CaptureFailure.storage => l10n.captureFailedStorage,
        CaptureFailure.unreadable => l10n.captureFailedUnreadable,
        CaptureFailure.unknown => l10n.captureFailed,
      },
      actionLabel: l10n.retry,
      onAction: () => unawaited(capturePhoto(source)),
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
    // Not dismissible: swiping the sheet away mid-recording would leave the
    // recorder running with nothing on screen driving it.
    final keep = await nexShowSheet<bool>(
      context: context,
      dismissible: false,
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

  /// The non-destructive half of ADR-022's fixed action pair.
  /// Swipe-to-tag (FR-2.6).
  ///
  /// Offers the tags that exist rather than a bare text field, so tagging is
  /// picking from what you already use — the common case by a wide margin.
  ///
  /// Every tag, not [filterTags]: that list only holds tags with at least one
  /// note left on them, so tagging the first note after clearing a library
  /// (or after every tagged note happened to be deleted) offered nothing.
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
    nexShowBanner(
      context,
      message: l10n.noteDeleted,
      haptics: widget.preferences.haptics,
      actionLabel: l10n.undo,
      onAction: () async {
        _tick();
        await widget.services.undelete(note.id);
        await widget.services.refreshTimeline();
      },
    );
  }

  void _onReorderStart(int index) {
    _reorderStartIndex = index;
    _swipe.closeAll();
  }

  /// A long-press-and-drag on a card's middle zone (see [SwipeableNoteCard])
  /// moved it: reflect that in [notes] straight away rather than waiting on
  /// the next stream tick, and persist the set that was actually dragged
  /// against — see [NexServices.reorderNotes].
  ///
  /// `sort_order` is one column shared by every note, not one scoped to
  /// whatever filter happens to be active. Persisting it for only the notes
  /// on screen — which is what [notes] holds under a filter — stamped a
  /// dense 0, 1, 2… onto that handful and left every other note with
  /// whatever it already had, so the two competed for the same numbers and
  /// the *unfiltered* timeline came out shuffled by an outcome nobody chose.
  /// Reported as: reordering under "All" behaves; reordering under a single
  /// tag rearranges notes that were never touched.
  ///
  /// The fix splices the move into [_all] — the complete, unfiltered list —
  /// right next to the note it now sits beside in the filtered view, and
  /// persists that whole list. Every note outside the filter keeps its exact
  /// relative position; only the moved note's slot changes. Filtering does
  /// not reorder, so re-deriving [notes] from the patched [_all] reproduces
  /// the same visible order the drag actually produced.
  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    // Nothing may land above a pinned note. It cannot be dragged itself, but
    // another card dropped on top of it would push it to second place — and
    // `listTimeline` sorts pinned-first, so the next read would snap it back
    // and the list would visibly jump for no reason the user could name.
    if (notes.isNotEmpty && notes.first.pinnedAt != null && newIndex == 0) {
      newIndex = 1;
    }
    if (newIndex == oldIndex) return;

    final visibleReordered = List<Note>.of(notes);
    final moved = visibleReordered.removeAt(oldIndex);
    visibleReordered.insert(newIndex, moved);

    // Anchor on whichever neighbour the move actually determined: the note
    // now right after it if there is one, otherwise the note now right
    // before it. Either way, `all` only has to know "next to this id" — it
    // never needs to reconstruct newIndex/oldIndex arithmetic of its own.
    final all = List<Note>.of(_all ?? notes)
      ..removeWhere((n) => n.id == moved.id);
    final after = newIndex + 1 < visibleReordered.length
        ? visibleReordered[newIndex + 1]
        : null;
    final before = newIndex > 0 ? visibleReordered[newIndex - 1] : null;
    int insertAt;
    if (after != null) {
      final at = all.indexWhere((n) => n.id == after.id);
      insertAt = at < 0 ? all.length : at;
    } else if (before != null) {
      final at = all.indexWhere((n) => n.id == before.id);
      insertAt = at < 0 ? all.length : at + 1;
    } else {
      insertAt = 0;
    }
    all.insert(insertAt, moved);

    setState(() {
      _all = all;
      notes = visibleReordered;
    });
    unawaited(widget.services.reorderNotes([for (final n in all) n.id]));
  }

  /// The same long press, released without ever crossing into a drag.
  ///
  /// This fires the instant the finger lifts, carrying the drop index — the
  /// same index [_onReorder] would use if the drag actually moved anything.
  /// [_onReorder] itself, though, only runs ~250ms later, once the drop's
  /// settle animation finishes; waiting for it here to decide whether to
  /// open the quick actions menu meant every real reorder opened the menu
  /// first and reordered second, the release fired while the card was still
  /// settling. Comparing indices directly avoids the wait entirely: the drop
  /// index is already final the moment this is called.
  void _onReorderEnd(int index) {
    final start = _reorderStartIndex;
    _reorderStartIndex = null;
    if (start == index && kReorderQuickActionsEnabled) {
      unawaited(_showQuickActions(notes[index]));
    }
  }

  /// What a long press that never turned into a drag opens: the same actions
  /// a swipe or the detail sheet already offer, reachable without aiming for
  /// either edge.
  Future<void> _showQuickActions(Note note) async {
    final l10n = AppLocalizations.of(context);
    final action = await nexShowSheet<_QuickAction>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              note.pinnedAt != null ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            title: Text(note.pinnedAt != null ? l10n.unpin : l10n.pin),
            onTap: () => Navigator.pop(ctx, _QuickAction.togglePin),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(l10n.addTag),
            onTap: () => Navigator.pop(ctx, _QuickAction.addTag),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.delete),
            onTap: () => Navigator.pop(ctx, _QuickAction.delete),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _QuickAction.togglePin:
        if (note.pinnedAt != null) {
          await widget.services.unpinNote(note.id);
        } else {
          await widget.services.pinNote(note.id);
        }
        await widget.services.refreshTimeline();
      case _QuickAction.addTag:
        await _addTagTo(note);
      case _QuickAction.delete:
        await deleteWithUndo(note);
    }
  }

  /// The dragged card's lift off the background — the same effect
  /// [ReorderableListView] gives its own items by default, reused here since
  /// [SliverReorderableList] has no default of its own to fall back on.
  Widget _reorderProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.02 * t,
          child: Material(
            color: Colors.transparent,
            elevation: 8 * t,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(NexRadius.lg),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  /// "Good evening, Saeed", and the mark that goes after it — or null when
  /// the user never told the app a name.
  ///
  /// Decoration, and it never leaves the device: the name is not sent with a
  /// sync, and not sent to the AI provider either — the generated headline
  /// beside this line is deliberately written without it.
  ///
  /// Three phrasings per time of day. Re-rolled only when the headline is
  /// tapped, never on an ordinary rebuild: a title that changes while you are
  /// reading it is a bug, not a flourish.
  (String, String)? _greeting(AppLocalizations l10n) {
    // Two words at most — a full name pushes this onto a second line and
    // shoves the headline under it out of place.
    final name = widget.preferences.shortDisplayName;
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

  /// Everything above the search field: the greeting, the generated headline,
  /// and the recap card.
  ///
  /// Which of those appear depends on what is configured, and the four cases
  /// are the whole design:
  ///
  /// - nothing set up at all — no header, just the search field, as before;
  /// - a name but no AI — the greeting *is* the headline, at headline size,
  ///   and tapping it re-rolls the phrasing;
  /// - AI but no name — the generated line alone;
  /// - both — the greeting small above, the generated line large below.
  ///
  /// The whole text block is one tap target rather than two: they read as one
  /// paragraph, and a refresh that only fires on the second of two adjacent
  /// lines is a refresh people report as broken.
  Widget _header(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final greeting = _greeting(l10n);
    if (greeting == null && !_aiHeaderAvailable) return const SizedBox.shrink();
    final headlineStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    // The generated line has a slot as soon as there is a provider: it is a
    // skeleton first and text second, rather than appearing from nowhere and
    // pushing the card down once the request lands.
    final hasHeadlineSlot = _aiHeaderAvailable;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        0,
      ),
      child: Column(
        // Stretch, so the tappable text block spans the column and the
        // centring inside it has something to centre against — sized to its
        // own content it would sit at one edge no matter how it aligned its
        // children. The card below wants the full width anyway.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexTappable(
            onTap: _refreshHeadline,
            semanticLabel: l10n.aiHeadlineRefresh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NexRadius.lg),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NexSpacing.xs,
                vertical: NexSpacing.sm,
              ),
              child: Column(
                // Centred, both lines. Left-aligned they read as two separate
                // starts stacked on each other; centred they read as one
                // block, which is what they are.
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (greeting != null)
                    _GreetingLine(
                      text: greeting.$1,
                      glyph: greeting.$2,
                      // Demoted to a label when there is a generated line to
                      // be the headline, promoted to being the headline when
                      // there is not.
                      style: hasHeadlineSlot
                          ? theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : headlineStyle,
                    ),
                  if (hasHeadlineSlot) ...[
                    if (greeting != null) const SizedBox(height: NexSpacing.xs),
                    _HeadlineText(
                      text: _aiHeadlineText,
                      loading: _aiHeadlineLoading,
                      style: headlineStyle,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_aiHeaderAvailable) ...[
            const SizedBox(height: NexSpacing.sm),
            _AiDaySummaryPanel(
              title: l10n.aiDaySummaryTitle,
              loading: _aiSummaryLoading,
              text: _aiSummaryText,
              emptyLabel: l10n.aiDaySummaryEmpty,
              collapsed: _aiSummaryCollapsed,
              semanticLabel: l10n.aiDaySummarySemanticLabel,
              refreshTooltip: l10n.aiDaySummaryRefresh,
              toggleTooltip: _aiSummaryCollapsed
                  ? l10n.aiDaySummaryExpand
                  : l10n.aiDaySummaryCollapse,
              // Disabled mid-request rather than queueing a second one: two
              // in flight means whichever finishes last wins, which is not
              // necessarily the one the last tap asked for.
              onRefresh: _aiSummaryLoading
                  ? null
                  : () {
                      _tick();
                      unawaited(_loadAiSummary(force: true));
                    },
              onToggle: _toggleAiSummary,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        // The greeting used to live here, squeezed between the mark and the
        // two action icons. It is a header now, at header size, in the list
        // below — which is what it always wanted to be, and what left the bar
        // free to be the small quiet strip it is here.
        titleSpacing: NexSpacing.md,
        title: const _WordmarkTile(),
        actions: [
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
            onPressed: () => nexShowSheet<void>(
              context: context,
              builder: (_) => SettingsSheet(
                services: widget.services,
                preferences: widget.preferences,
                updates: widget.updates,
              ),
            ),
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
              // Past 200 notes, this is the only thing that ever asks for
              // the rest — nothing rendered the tail of a long timeline
              // before this, it just never loaded.
              if (notification.metrics.extentAfter < 600) _maybeLoadMore();
              return false;
            },
            child: Center(
              // One column, and the filter row is inside it. It used to be a
              // sibling *above* this, so on a wide window the pills started at
              // the window edge while the cards sat in a 760px column — two
              // things that belong to each other, visibly unaligned.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                // No pull-to-refresh. There is nothing left for it to do:
                // the timeline is a broadcast stream that every mutation path
                // already re-fires, the filter row reloads on the same event,
                // and "Sync now" lives in Settings where a sync server is
                // configured in the first place. A pull that re-reads data
                // which is already current is a gesture that does nothing —
                // and this screen's own history says why that is worse than
                // no gesture: the pull used to be "reveal the search field",
                // and it was replaced precisely because it never revealed
                // anything.
                child: CustomScrollView(
                  controller: _scroll,
                  // Always scrollable, so a short list still bounces rather
                  // than feeling locked.
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // The headline and the recap card, above the search
                    // field. Both collapse to nothing rather than leaving
                    // the list, the same reason the two headers below do.
                    SliverToBoxAdapter(
                      key: const ValueKey('timeline-header'),
                      child: AnimatedSize(
                        duration: NexMotion.slow,
                        curve: NexMotion.curve,
                        alignment: Alignment.topCenter,
                        child: _searching
                            ? const SizedBox.shrink()
                            : _header(l10n),
                      ),
                    ),
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // Capture is a timeline action. Left up while searching, it read as
      // part of the search flow itself rather than what it actually still
      // did — open a fresh note, unrelated to whatever was just searched.
      floatingActionButton: _searching
          ? null
          : FloatingActionButton(
              onPressed: openCapture,
              tooltip: l10n.capture,
              child: const Icon(Icons.add, size: 32),
            ),
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
      SliverReorderableList(
        itemCount: notes.length,
        onReorderStart: _onReorderStart,
        onReorder: _onReorder,
        onReorderEnd: _onReorderEnd,
        proxyDecorator: _reorderProxyDecorator,
        itemBuilder: (context, index) {
          final note = notes[index];
          return CommitReceipt(
            key: ValueKey(note.id),
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
              // A pinned note is held in place by definition, so it is not
              // a thing that can be dragged somewhere else. Null here is what
              // SwipeableNoteCard reads as "no reorder gesture on this card".
              reorderIndex: notes[index].pinnedAt == null ? index : null,
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

  /// A tap on a card, which means two different things depending on what the
  /// list already looked like.
  ///
  /// With a card swiped open, a tap anywhere — on the open card itself, or on
  /// any other one — used to both close it *and* open whatever was tapped,
  /// since the outer tap-to-close and the card's own tap handler both fired
  /// off the same touch. The first tap while something is open now only
  /// closes it; opening a note takes its own, second tap.
  void _tapNote(Note note) {
    if (_swipe.openCard != null) {
      _swipe.closeAll();
      return;
    }
    unawaited(_openNote(note));
  }

  Future<void> _openNote(Note note) async {
    final result = await nexShowSheet<DetailResult>(
      context: context,
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
    if (old.glyph != widget.glyph && !MediaQuery.disableAnimationsOf(context)) {
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

/// The app's own mark, in the corner the app bar used to spend on a title.
///
/// Bare, on no ground of its own. It had a rounded tile behind it to match the
/// footprint of the two icon buttons opposite — but those are tap targets and
/// this is not, so the tile was claiming an affordance the mark does not have,
/// and it read as a fourth button that does nothing.
class _WordmarkTile extends StatelessWidget {
  const _WordmarkTile();

  @override
  Widget build(BuildContext context) => Image.asset(
    Theme.of(context).brightness == Brightness.dark
        ? 'assets/branding/logo_dark.png'
        : 'assets/branding/logo_white.png',
    width: 28,
    height: 28,
    semanticLabel: 'Nex',
  );
}

/// "Good evening, Saeed ☀️" — the text and its animated mark on one line.
class _GreetingLine extends StatelessWidget {
  const _GreetingLine({
    required this.text,
    required this.glyph,
    required this.style,
  });

  final String text;
  final String glyph;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    // Centred with the headline under it, so the two read as one block
    // rather than as a label and a separate line that happen to be adjacent.
    mainAxisAlignment: MainAxisAlignment.center,
    // The greeting's own language decides which end the mark sits at. This
    // string is localised, so in Persian it is RTL text inside an interface
    // that may still be in English — and the Row is what places the glyph.
    textDirection: nexDirectionOf(text),
    children: [
      Flexible(
        child: Text(
          text,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(width: NexSpacing.xs),
      // The mark takes the line's own size: at label size beside a headline
      // it would otherwise stay at body size and sit visibly too large.
      DefaultTextStyle.merge(style: style, child: _GreetingGlyph(glyph)),
    ],
  );
}

/// The generated line across the top: a skeleton until the first one lands,
/// then the line itself, cross-fading whenever a tap replaces it.
///
/// Two lines at most, hard. The prompt asks for nine words and the adapter
/// clamps to twelve, but a model that ignores both must not be able to push
/// the search field off the screen.
class _HeadlineText extends StatelessWidget {
  const _HeadlineText({
    required this.text,
    required this.loading,
    required this.style,
  });

  final String? text;
  final bool loading;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final value = text;
    // Loading with text already there keeps the text: a refresh should read
    // as the line being replaced, not as it being taken away and given back.
    if (value == null) {
      return loading
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                NexSkeleton(height: 22, width: 240),
                SizedBox(height: NexSpacing.xs),
                NexSkeleton(height: 22, width: 160),
              ],
            )
          : const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: NexMotion.standard,
      child: Opacity(
        // Dimmed rather than replaced while the next one is in flight —
        // the only visible sign that the tap did anything.
        key: ValueKey(value),
        opacity: loading ? 0.45 : 1,
        child: Text(
          value,
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          // The generated line follows the language it was written in, not
          // the interface's. Without this a Persian line rendered inside an
          // English UI resolves as left-to-right, which puts its full stop
          // at the wrong end of the sentence.
          textDirection: nexDirectionOf(value),
        ),
      ),
    );
  }
}

/// The AI recap card: a header row that is always there, and a body that the
/// chevron folds away.
///
/// Collapsing used to remove the card outright and leave a chip in the app bar
/// as the way back — a control nowhere near the thing it controlled, and one
/// that only existed once there was cached text to point at. The header row
/// stays put now, so the chevron that closed it is the chevron that reopens
/// it, in the same place, always.
///
/// No dashed border, unlike the Nex_ui mock: that reads there as "content
/// goes here" — a Figma placeholder convention for an empty slot, not a
/// finished look meant to ship. A filled card matches how every other
/// elevated surface in the app is drawn.
class _AiDaySummaryPanel extends StatelessWidget {
  const _AiDaySummaryPanel({
    required this.title,
    required this.loading,
    required this.text,
    required this.emptyLabel,
    required this.collapsed,
    required this.semanticLabel,
    required this.refreshTooltip,
    required this.toggleTooltip,
    required this.onRefresh,
    required this.onToggle,
  });

  final String title;
  final bool loading;
  final String? text;
  final String emptyLabel;
  final bool collapsed;
  final String semanticLabel;
  final String refreshTooltip;
  final String toggleTooltip;

  /// Null while a request is already in flight — see the call site.
  final VoidCallback? onRefresh;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          NexSpacing.cardInset,
          NexSpacing.xs,
          NexSpacing.xs,
          NexSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          // The search field's curvature, not the card radius used elsewhere.
          // These two sit directly above one another and were visibly a step
          // apart — 20 against the field's 24.
          borderRadius: BorderRadius.circular(NexRadius.pill),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: refreshTooltip,
                  onPressed: onRefresh,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                IconButton(
                  tooltip: toggleTooltip,
                  onPressed: onToggle,
                  visualDensity: VisualDensity.compact,
                  icon: AnimatedRotation(
                    // Down points at the body it would reveal; up points at
                    // the header it would fold into.
                    turns: collapsed ? 0 : 0.5,
                    duration: NexMotion.standard,
                    curve: NexMotion.curve,
                    child: const Icon(Icons.keyboard_arrow_down, size: 22),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: NexMotion.slow,
              curve: NexMotion.curve,
              alignment: Alignment.topCenter,
              child: collapsed
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(
                        0,
                        NexSpacing.xs,
                        NexSpacing.sm,
                        NexSpacing.sm,
                      ),
                      child: _summaryBody(theme),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBody(ThemeData theme) {
    final value = text;
    if (value == null) {
      return loading
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NexSkeleton(height: 16),
                SizedBox(height: NexSpacing.xs),
                NexSkeleton(height: 16),
              ],
            )
          : Text(
              emptyLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.start,
              textDirection: nexDirectionOf(emptyLabel),
            );
    }
    return Opacity(
      opacity: loading ? 0.45 : 1,
      child: SizedBox(
        // Full width, so a Persian recap reaches the right edge rather than
        // hugging whichever edge its first character happens to start at.
        width: double.infinity,
        child: Text(
          value,
          style: theme.textTheme.bodyMedium,
          // The recap is written in the language of the notes, which is not
          // necessarily the language of the interface around it — so it takes
          // its direction from itself, and `start` then means the right edge
          // in Persian and the left in English.
          textDirection: nexDirectionOf(value),
          textAlign: TextAlign.start,
        ),
      ),
    );
  }
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

/// Wraps the picker's answer so "All" survives the trip back through
/// `Navigator.pop`, which cannot distinguish a null result from a dismissal.
class _TypeChoice {
  const _TypeChoice(this.type);
  final NoteType? type;
}

/// What a hold-and-release without a drag can do to a note — see
/// [TimelineScreenState._showQuickActions].
enum _QuickAction { togglePin, addTag, delete }

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
