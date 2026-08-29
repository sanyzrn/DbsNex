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
import '../platform/ai_provider.dart';
import '../platform/capture_failure.dart';
import '../platform/daily_nudge.dart';
import '../platform/link_reader.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/route_observer.dart';
import '../platform/note_search.dart';
import '../platform/os_capture_bridge.dart';
import '../platform/sharing.dart';
import '../platform/update_service.dart';
import '../widgets/ai_chat_sheet.dart';
import '../widgets/capture_sheet.dart';
import '../widgets/checklist_capture_sheet.dart';
import '../widgets/card_strings.dart';
import '../widgets/commit_receipt.dart';
import '../widgets/note_spotlight.dart';
import '../widgets/empty_timeline.dart';
import '../widgets/first_run_tour.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_banner.dart';
import '../widgets/recording_sheet.dart';
import '../widgets/search_field_header.dart';
import '../widgets/search_results.dart';
import '../widgets/reminder_picker.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/tag_picker.dart';
import 'home_layout_sheet.dart';
import 'library_screen.dart';
import 'note_detail_sheet.dart';
import 'photo_preview_screen.dart';
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

class TimelineScreenState extends State<TimelineScreen>
    with RouteAware, WidgetsBindingObserver {
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

  /// Date groups the user has folded away, by their stable key.
  ///
  /// Persisted rather than kept for the session: someone who collapses "Last
  /// month" has said something about how they want the list to look, and
  /// having it spring open on the next launch means saying it again every day.
  Set<String> _collapsedGroups = const {};

  /// The group whose rows are on their way out — see [_toggleGroup]. Null at
  /// rest, which is every frame except the ~200ms after a fold.
  String? _closingGroup;

  /// The group whose rows are on their way in, for the same window.
  ///
  /// Needed because `SliverList` matches its children by index. Folding a run
  /// shortens the list, so every row below it arrives at a new index, gets a
  /// new [_FoldingRow] state, and — if that state animated itself in on
  /// creation — played the entrance animation. The result was every group
  /// below the one being folded flickering open, which is the report this
  /// exists to answer. Only the group actually being opened animates in;
  /// everyone else appears at full height, because they never left it.
  String? _openingGroup;
  List<Tag> filterTags = const [];
  String? selectedTagId;
  NoteType? selectedType;
  StreamSubscription<List<Note>>? subscription;
  String? landedId;

  /// Notes whose spent reminder has already had its one last showing.
  ///
  /// Read once into the frame rather than off preferences on every card: the
  /// set is rewritten when the timeline is covered, and a card that read it
  /// directly would change under a route transition.
  Set<String> _seenReminders = const {};

  /// The note a tapped reminder is about, until its border has finished
  /// pulsing.
  ///
  /// A tapped reminder used to open the app and stop there: the notification
  /// named the note, and the timeline then showed the same list it always
  /// shows, leaving the reader to find it.
  String? _spotlightId;

  /// The spotlighted card, so it can be scrolled into view.
  ///
  /// Only ever attached to one row — a key on every card would be a key per
  /// note in a list that is deliberately lazy.
  final GlobalKey _spotlightAnchor = GlobalKey();

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

  /// The four controls the first-run tour points at. Held here rather than
  /// created inline: a `GlobalKey` rebuilt every frame attaches to a new
  /// element each time, and the tour would measure a widget that no longer
  /// exists.
  final _captureAnchor = GlobalKey();
  final _searchAnchor = GlobalKey();
  final _libraryAnchor = GlobalKey();
  final _settingsAnchor = GlobalKey();

  /// The tour itself, while it is running.
  OverlayEntry? _tour;

  /// Requesting either string is a cold-launch thing, not a per-note-change
  /// thing — without this latch, every capture re-firing [timelineStream]
  /// would ask the provider again.
  bool _aiSummaryRequested = false;

  @override
  void initState() {
    super.initState();
    _collapsedGroups = widget.preferences.collapsedTimelineGroups;
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
    _seenReminders = widget.preferences.seenReminders;
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearchChanged);
    _scroll.addListener(_onAiSummaryScroll);
    // Both halves of a tapped reminder: one for a tap while the app is up,
    // one for the tap that started it.
    widget.services.reminders.onOpenNote = _spotlight;
    final launched = widget.services.reminders.takeLaunchNoteId();
    if (launched != null) _spotlight(launched);
    unawaited(_loadTimeline());
    unawaited(_loadFilterTags());
    // After the first frame, because every stop measures a real widget and
    // none of them has been laid out yet at this point.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartTour();
      // Also here, not only where the recap resolves: the notification is
      // scheduled for people with no AI provider too, and for them nothing
      // else on this screen would ever re-arm it.
      _refreshDailyNudge();
    });
  }

  /// Shows the walk-through once, on the first timeline after onboarding.
  ///
  /// In an overlay rather than as part of this screen's tree: it has to paint
  /// over the app bar and the capture button, both of which the `Scaffold`
  /// draws above its own body.
  void _maybeStartTour() {
    if (!mounted || widget.preferences.tourComplete || _tour != null) return;
    final l10n = AppLocalizations.of(context);
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (_) => FirstRunTour(
        onFinished: _endTour,
        stops: [
          TourStop(
            key: _captureAnchor,
            title: l10n.tourCaptureTitle,
            body: l10n.tourCaptureBody,
            radius: NexRadius.pill,
          ),
          TourStop(
            key: _searchAnchor,
            title: l10n.tourSearchTitle,
            body: l10n.tourSearchBody,
            radius: NexRadius.pill,
          ),
          TourStop(
            key: _libraryAnchor,
            title: l10n.tourLibraryTitle,
            body: l10n.tourLibraryBody,
            radius: NexRadius.pill,
          ),
          TourStop(
            key: _settingsAnchor,
            title: l10n.tourSettingsTitle,
            body: l10n.tourSettingsBody,
            radius: NexRadius.pill,
          ),
        ],
      ),
    );
    _tour = entry;
    overlay.insert(entry);
  }

  void _endTour() {
    _tour?.remove();
    _tour = null;
    unawaited(widget.preferences.completeTour());
  }

  /// True when there is a provider configured to generate anything at all.
  /// The whole header — headline and card both — is absent otherwise, rather
  /// than showing empty chrome for a feature that is switched off.
  bool get _aiHeaderAvailable =>
      widget.preferences.aiEnabled &&
      aiTextAvailableWith(widget.preferences.aiProvider);

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
    _refreshDailyNudge();
  }

  /// Which language the generated line has to be written in.
  ///
  /// Not the global "language Nex writes in", which is what every other
  /// generated string here follows. This one is glued onto the greeting and
  /// read as a single sentence, and the greeting is written in the language
  /// of the user's own name — so on the default setting ("answer in the
  /// language of the notes") the result was half an English sentence joined
  /// to half a Persian one, full stop at the wrong end.
  ///
  /// Null when there is no name to take the cue from; the line then stands
  /// alone and the global setting is right for it.
  AiOutputLanguage? get _headlineLanguage {
    final name = widget.preferences.shortDisplayName;
    if (name == null) return null;
    return nexDirectionOf(name) == TextDirection.rtl
        ? AiOutputLanguage.persian
        : AiOutputLanguage.english;
  }

  /// The headline over the timeline. Same shape as [_loadAiSummary] — cached
  /// per day, forced by a tap on the line itself.
  Future<void> _loadAiHeadline({bool force = false}) async {
    final prefs = widget.preferences;
    if (!_aiHeaderAvailable) return;
    final today = _aiSummaryDateKey();
    final language = _headlineLanguage;
    final langKey = language?.wireName;
    // A renamed user changes the greeting's language mid-day, so the day key
    // alone is not enough to decide the cached line still fits beside it.
    if (!force &&
        prefs.aiHeadlineDate == today &&
        prefs.aiHeadlineLang == langKey) {
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
      text = await adapter.headline(_aiSummarySource(), language: language);
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
      unawaited(prefs.setAiHeadline(text: text, dateKey: today, lang: langKey));
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

  /// Opens the assistant, held rather than tapped — see the capture button.
  ///
  /// Silent when nothing is configured: the glow still ran, because it tracks
  /// the finger and cannot know the outcome in advance, but nothing opens. A
  /// sheet that can only say "unavailable" is not worth the trip.
  void _openAssistant() {
    if (!AiChatSheet.availableFor(widget.preferences)) return;
    HapticFeedback.mediumImpact();
    unawaited(
      AiChatSheet.show(
        context,
        preferences: widget.preferences,
        services: widget.services,
        history: widget.preferences.chatHistory,
      ),
    );
  }

  void _toggleAiSummary() {
    _tick();
    setState(() {
      _aiSummaryToggledByUser = true;
      _aiSummaryCollapsed = !_aiSummaryCollapsed;
    });
  }

  String _aiSummaryDateKey() =>
      NexPreferences.daySummaryDateKey(DateTime.now());

  /// Re-arms the once-a-day notification with whatever Nex knows right now.
  ///
  /// Every open, not once at setup. The notification repeats daily on its own
  /// — that part the system handles — but its text is fixed at the moment it
  /// was scheduled, and the recap it carries is a day old by the next
  /// morning. So the schedule is rewritten each time the app is in a position
  /// to know something newer, which is here.
  void _refreshDailyNudge() {
    if (!mounted || !widget.preferences.dailyNudge) return;
    unawaited(
      DailyNudge.apply(
        context: context,
        preferences: widget.preferences,
        reminders: widget.services.reminders,
        recap: widget.preferences.lastRecap,
      ),
    );
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

  /// Records every reminder that has already rung as seen.
  ///
  /// The whole set is replaced rather than added to, so it prunes itself: a
  /// note whose reminder is pushed back into the future simply is not in the
  /// overdue set the next time this runs, and gets its chip back with nothing
  /// having had to remember to remove it.
  Future<void> _markRemindersSeen() async {
    final now = DateTime.now().toUtc();
    final overdue = {
      for (final note in _all ?? const <Note>[])
        // A repeating reminder is never spent: its stored time is in the past
        // by design after the first firing, and it is still going to ring
        // again. Only a one-off can be finished with.
        if (note.dueRepeat == NoteRepeat.once)
          if (note.dueAt case final due?)
            if (!due.isAfter(now)) note.id,
    };
    if (overdue.length == _seenReminders.length &&
        overdue.every(_seenReminders.contains)) {
      return;
    }
    await widget.preferences.setSeenReminders(overdue);
    if (mounted) setState(() => _seenReminders = overdue);
  }

  /// Points at the note a reminder was about.
  ///
  /// A search or a filter left over from last time would hide the very note
  /// the reminder just named, so both are cleared first — and so is the
  /// collapsed state of whichever date group holds it, since a folded group
  /// is the other way for a card to be absent from a list that contains it.
  void _spotlight(String noteId) {
    if (!mounted) return;
    setState(() {
      if (_searching) _exitSearch();
      _spotlightId = noteId;
    });
    unawaited(_revealSpotlight(noteId));
  }

  Future<void> _revealSpotlight(String noteId) async {
    // The group is expanded before the frame that would have to contain the
    // card is built, or the anchor below has nothing to find. Everything that
    // reads context happens here, ahead of the first await.
    final note = _all?.where((n) => n.id == noteId).firstOrNull;
    final now = DateTime.now();
    final key = note == null
        ? null
        : _bucketFor(
            note,
            DateTime(now.year, now.month, now.day),
            AppLocalizations.of(context),
          ).$1;
    if (key != null && _collapsedGroups.contains(key)) {
      await _toggleGroup(key);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final anchor = _spotlightAnchor.currentContext;
    // Absent when the note is far enough down that the list has not built its
    // row yet. The border still runs when scrolling brings the card into
    // view; this only saves the reader the scroll when it can.
    // `anchor.mounted`, not this State's: the row is its own element and can
    // have left the tree while the frame was being waited for.
    if (anchor != null && anchor.mounted) {
      await Scrollable.ensureVisible(
        anchor,
        duration: NexMotion.slow,
        curve: NexMotion.curve,
        alignment: 0.3,
      );
    }
  }

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
    // After the frame: with the field switched off it is not in the list
    // until this setState puts it there, and a focus request aimed at a node
    // no widget has attached yet is simply dropped.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
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

  void _tick() => nexTick();

  /// Where the list was when it last buzzed.
  ///
  /// A tick every [_scrollTickDistance] of travel, which is the trick the
  /// Windscribe app uses and the reason its lists feel attached to the
  /// finger. Distance rather than time: a slow drag should tick slowly and a
  /// fling should tick fast, and only distance does both without any state
  /// machine at all.
  double _lastTickOffset = 0;
  static const _scrollTickDistance = 64.0;

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    final offset = notification.metrics.pixels;
    final travelled = (offset - _lastTickOffset).abs();
    if (travelled < _scrollTickDistance) return false;
    // A jump this large is not a finger — it is the list being replaced
    // under one, which happens every time search opens or a filter changes.
    // Re-anchor silently rather than buzzing at a scroll nobody performed.
    final jumped = travelled > _scrollTickDistance * 8;
    _lastTickOffset = offset;
    if (!jumped) nexTick();
    return false;
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
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) nexRouteObserver.subscribe(this, route);
  }

  /// Something has covered the timeline — another screen, or a sheet.
  ///
  /// That is the moment a reminder that has already rung stops having
  /// anything left to say: it was delivered as a notification, and it has now
  /// been on screen once more with the reader looking at it. Written here
  /// rather than on the way back, so that the return is the first frame
  /// without it.
  @override
  void didPushNext() => unawaited(_markRemindersSeen());

  /// Leaving the app counts as leaving the timeline.
  ///
  /// `didPushNext` only fires when another *route* covers this one, and the
  /// way a spent reminder is actually met is nothing like that: the
  /// notification arrives, the app is opened to read the note, and then the
  /// app is put away — no route is ever pushed. So the chip was marked seen
  /// only by someone who happened to open Settings or the Library on the way
  /// out, and for everyone else it stayed on the card until the reminder was
  /// deleted by hand, which is the report.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_markRemindersSeen());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    nexRouteObserver.unsubscribe(this);
    // Removed, never left behind: an overlay entry outlives the state that
    // inserted it, so a screen replaced mid-tour would leave a scrim over
    // whatever came next with nothing able to dismiss it.
    _tour?.remove();
    _tour = null;
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
      // The preview first, not the cropper. Most photos need no edit at all,
      // and putting one in the path of every capture was the report.
      final cropped = await Navigator.of(context).push<Uint8List>(
        NexPageRoute(builder: (_) => PhotoPreviewScreen(image: original)),
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
    // Say so. A denied microphone used to end this method on the spot, with
    // no sheet, no banner and no reason — the button simply did nothing, and
    // "nothing" is indistinguishable from a broken control. There is no way
    // to open the system settings from here without a dependency this app
    // does not carry, so the message names where the permission lives.
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      if (!mounted) return;
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).micDenied,
        kind: NexBannerKind.failed,
        haptics: widget.preferences.haptics,
      );
      return;
    }
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

  /// Opens the assistant with one date run as its whole context.
  ///
  /// Same shape as asking about a single note, and for the same reason: the
  /// context is exactly what the question is about, so the answer is specific
  /// and the request is not carrying the rest of the library to get there.
  Future<void> _askAboutGroup(_NoteGroup group) async {
    await AiChatSheet.show(
      context,
      preferences: widget.preferences,
      services: widget.services,
      history: widget.preferences.chatHistory,
      scope: List.of(group.notes),
      scopeLabel: group.label,
    );
  }

  /// Deletes a whole date run, once, after asking.
  ///
  /// Confirmed rather than undone: a swipe deletes one note and an undo
  /// banner is the right weight for that, but a heading's menu can take a
  /// day's work away in one tap, and an undo that scrolls off screen is not
  /// a safety net for that much. The notes go to Trash either way, which the
  /// dialog says so nobody has to hope.
  Future<void> _deleteGroup(_NoteGroup group, AppLocalizations l10n) async {
    final notes = List.of(group.notes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(group.label),
        content: NexDialogBody(child: Text(l10n.groupDeleteBody(notes.length))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (widget.preferences.haptics) HapticFeedback.mediumImpact();
    for (final note in notes) {
      await widget.services.deleteNote(note.id);
    }
    await widget.services.refreshTimeline();
    if (!mounted) return;
    nexShowBanner(
      context,
      message: l10n.groupDeleted(notes.length),
      haptics: widget.preferences.haptics,
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
  /// The one line the app opens with.
  ///
  /// [aiPhrase] replaces the canned phrasing when a model wrote one; the name
  /// is still appended here rather than sent anywhere. That split is the whole
  /// design: the greeting is the only place the user's own name appears, and
  /// it never leaves the device — not to a provider, not to sync. So the model
  /// is asked for a phrase with a slot after it, and this puts the name in.
  (String, String)? _greeting(AppLocalizations interface, {String? aiPhrase}) {
    // Two words at most — a full name pushes this onto a second line and
    // shoves the headline under it out of place.
    final name = widget.preferences.shortDisplayName;
    if (name == null) return null;
    // Greeted in the language you wrote your own name in, whatever the
    // interface is set to. "صبح بخیر, Sany" and "Good morning, سعید" are both
    // sentences nobody writes, and the name is the one word here the app did
    // not choose — so it is the one that decides.
    final l10n = nexDirectionOf(name) == TextDirection.rtl
        ? lookupAppLocalizations(const Locale('fa'))
        : lookupAppLocalizations(const Locale('en'));
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
    // A comma in the script the name is written in — the phrase came back in
    // that language, so an ASCII comma in front of a Persian name is the same
    // seam this used to have between two half-sentences.
    if (aiPhrase != null && aiPhrase.isNotEmpty) {
      final comma = nexDirectionOf(name) == TextDirection.rtl ? '،' : ',';
      return ('$aiPhrase$comma $name', glyphs[v]);
    }
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
    final showGreeting = widget.preferences.showGreeting;
    final showSummary = _aiHeaderAvailable && widget.preferences.showDaySummary;
    final greeting = showGreeting
        ? _greeting(l10n, aiPhrase: _aiHeadlineText)
        : null;
    // The line is there either because there is a greeting to say or because
    // a provider is going to write one — the slot is a skeleton first and
    // text second, rather than appearing from nowhere later and pushing the
    // card below it down.
    final showLine = showGreeting && (greeting != null || _aiHeaderAvailable);
    if (!showLine && !showSummary) return const SizedBox.shrink();
    final headlineStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    // The generated line is written at the daily recap's size and weight, not
    // at display size. It is a flourish, not a title: set large and bold it
    // was the loudest thing on a screen whose subject is the notes below it,
    // and a model's turn of phrase does not earn that.
    final generatedStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.35);
    // The generated line has a slot as soon as there is a provider: it is a
    // skeleton first and text second, rather than appearing from nowhere and
    // pushing the card down once the request lands.
    final hasHeadlineSlot = _aiHeaderAvailable && showGreeting;

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
          if (showLine)
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
                // One line, and now genuinely one. It used to be the greeting
                // and a separate generated sentence joined by an em dash, which
                // read as two openings competing — "The quiet hours, Saeed —
                // Midnight code audits taste like stale glue." The model now
                // writes the greeting itself and the name follows it, so there
                // is one thought here instead of two.
                child: _GreetingLine(
                  text: greeting?.$1 ?? _aiHeadlineText ?? '',
                  glyph: greeting?.$2 ?? '',
                  loading: hasHeadlineSlot && _aiHeadlineLoading,
                  style: hasHeadlineSlot ? generatedStyle : headlineStyle,
                ),
              ),
            ),
          if (showSummary) ...[
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
                      nexBump();
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
    final glass = context.nexVisualStyle.liquidGlass;
    return Scaffold(
      appBar: AppBar(
        // Transparent so the blur below has the list to work on rather than a
        // fill of the bar's own — see [NexGlassBar]. Null keeps the theme's
        // opaque colour everywhere else.
        backgroundColor: glass ? Colors.transparent : null,
        flexibleSpace: glass ? const NexGlassBar() : null,
        // The greeting used to live here, squeezed between the mark and the
        // two action icons. It is a header now, at header size, in the list
        // below — which is what it always wanted to be, and what left the bar
        // free to be the small quiet strip it is here.
        titleSpacing: NexSpacing.md,
        title: const _WordmarkTile(),
        actions: [
          // The icon comes back exactly when the field it used to duplicate
          // is not on screen. It was removed because it pointed at something
          // already visible; with the field switched off, it is the only way
          // to search at all.
          if (!widget.preferences.showSearchField && !_searching)
            IconButton(
              tooltip: l10n.search,
              icon: const Icon(Icons.search),
              onPressed: () => unawaited(revealSearch()),
            ),
          IconButton(
            tooltip: l10n.layoutTitle,
            // Not `tune`: the content-type filter at the head of the tag row
            // already wears that, and two identical icons on one screen
            // meaning two different things is worse than either.
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: () async {
              await nexShowSheet<void>(
                context: context,
                builder: (_) =>
                    HomeLayoutSheet(preferences: widget.preferences),
              );
              if (mounted) setState(() {});
            },
          ),
          // Content lives here, preferences live behind the gear. Trash and
          // Tags were reachable only through Settings, and neither is a
          // preference — one of them holds the user's own deleted notes.
          IconButton(
            key: _libraryAnchor,
            tooltip: l10n.libraryTitle,
            icon: const Icon(Icons.inventory_2_outlined),
            // Awaited, and the timeline reloads on the way back. Tags and
            // Trash both live behind here and both change what this screen
            // shows, and neither of them refreshes it on its own.
            onPressed: () async {
              await Navigator.push(
                context,
                NexPageRoute<void>(
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
            key: _settingsAnchor,
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
        // The list keeps drawing all the way down, and stops *listening*
        // where the system's own navigation gestures begin. Without this the
        // two competed for the same upward drag at the bottom of the screen,
        // and which one won depended on the angle of the finger.
        //
        // Over the body, under the capture button: the FAB is a Scaffold slot
        // painted above this, so it stays tappable where the two overlap.
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              // A tap anywhere that is not a card closes an open swipe.
              onTap: _swipe.closeAll,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // Scrolling dismisses an open card, the way every list with
                  // swipe actions behaves.
                  if (notification is ScrollStartNotification) {
                    _swipe.closeAll();
                  }
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
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
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
                          // Kept in the list while a search is running even
                          // when it is switched off, or the field the app bar
                          // icon just asked for would not exist.
                          if (widget.preferences.showSearchField || _searching)
                            SliverPersistentHeader(
                              key: const ValueKey('search-header'),
                              delegate: SearchFieldHeader(
                                anchor: _searchAnchor,
                                controller: _search.query,
                                focusNode: _searchFocus,
                                searching: _searching,
                                onTap: () => unawaited(revealSearch()),
                                onChanged: (_) => _search.schedule(),
                                onClear: _exitSearch,
                              ),
                            ),
                          if (widget.preferences.showTagRow)
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: nexBottomGestureStrip(context),
              child: const AbsorbPointer(),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // Capture is a timeline action. Left up while searching, it read as
      // part of the search flow itself rather than what it actually still
      // did — open a fresh note, unrelated to whatever was just searched.
      floatingActionButton: _searching
          ? null
          // Hold the capture button to reach the assistant. It earns the
          // gesture rather than a second button on the same screen: capture
          // and "ask about what I captured" are the same intent at different
          // lengths, and this screen has one primary action, not two.
          //
          // Only when there is a provider to answer — a long press that opens
          // a chat which cannot reply is worse than one that does nothing.
          // Not the accent. Tapping this button and holding it are different
          // things, and lighting the same blue for both said they were the
          // same. Every assistant with an entrance uses a spectrum for this
          // reason — see [nexAssistantSpectrum].
          : NexLongPressGlow(
              colors: nexAssistantSpectrum,
              onHoldStart: _tick,
              onTriggered: _openAssistant,
              child: NexGlassSurface(
                borderRadius: BorderRadius.circular(nexCaptureFabSize / 2),
                child: FloatingActionButton(
                  key: _captureAnchor,
                  onPressed: openCapture,
                  tooltip: l10n.capture,
                  child: const Icon(Icons.add, size: 32),
                ),
              ),
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
        preferences: widget.preferences,
        onUseSaved: (query) {
          _search.query.text = query;
          _search.run();
        },
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

    // Grouped by date, and only by date. Manual arrangement is gone (the
    // repository's ORDER BY says why): a heading that says "Yesterday" has to
    // be telling the truth about every row beneath it, and a hand-placed note
    // lands wherever it was dropped.
    final groups = _groupNotes(notes, l10n);
    final rows = <_TimelineRow>[
      for (final group in groups) ...[
        _TimelineRow.header(group),
        // A closing group keeps its rows for one animation. Without that the
        // fold was a jump cut: the rows were simply gone on the next frame,
        // which is the report this fixes. See [_toggleGroup].
        if (!_collapsedGroups.contains(group.key) || group.key == _closingGroup)
          for (final note in group.notes) _TimelineRow.note(note, group.key),
      ],
    ];

    return [
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          if (row.group case final group?) {
            return _GroupHeader(
              label: group.label,
              count: group.notes.length,
              collapsed: _collapsedGroups.contains(group.key),
              onToggle: () => unawaited(_toggleGroup(group.key)),
              onAsk: AiChatSheet.availableFor(widget.preferences)
                  ? () => unawaited(_askAboutGroup(group))
                  : null,
              onDelete: () => unawaited(_deleteGroup(group, l10n)),
            );
          }
          final note = row.note!;
          return _FoldingRow(
            // Keyed on the note so the controller survives a rebuild of the
            // list and an entrance is never restarted mid-flight.
            key: ValueKey('fold-${note.id}'),
            open: row.groupKey != _closingGroup,
            animateIn: row.groupKey == _openingGroup,
            child: NoteSpotlight(
              key: _spotlightId == note.id ? _spotlightAnchor : null,
              active: _spotlightId == note.id,
              onDone: () {
                if (mounted && _spotlightId == note.id) {
                  setState(() => _spotlightId = null);
                }
              },
              child: CommitReceipt(
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
                  haptics: widget.preferences.haptics,
                  controller: _swipe,
                  resolveAction: ({required bool isLeading}) => nexSwipeSpec(
                    l10n,
                    isLeading
                        ? widget.preferences.leadingAction
                        : widget.preferences.trailingAction,
                  ),
                  onAction: (action) => unawaited(_runSwipe(action, note)),
                  child: NoteCard(
                    note: note,
                    strings: nexCardStrings(context),
                    onTap: () => _tapNote(note),
                    // A reminder still ahead keeps its chip. One that has
                    // rung and been seen gives the slot back to the note's
                    // own timestamp rather than wearing "Overdue" for ever.
                    showDue: !_seenReminders.contains(note.id),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  /// Runs whichever action an edge was bound to.
  ///
  /// Every one of these already existed behind the note detail sheet; a swipe
  /// is a second way to reach it, not a second implementation of it — which is
  /// why the reminder picker and the share path are shared functions rather
  /// than copies.
  Future<void> _runSwipe(NexSwipeAction action, Note note) async {
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case NexSwipeAction.delete:
        await deleteWithUndo(note);
      case NexSwipeAction.addTag:
        await _addTagTo(note);
      case NexSwipeAction.pin:
        // A toggle, because the swipe is the same gesture either way and a
        // pin that could only ever be set would need a second route to undo.
        if (note.pinnedAt == null) {
          final pinned = await widget.services.pinNote(note.id);
          if (!pinned && mounted) {
            nexShowBanner(context, message: l10n.pinLimitReached);
          }
        } else {
          await widget.services.unpinNote(note.id);
        }
        await widget.services.refreshTimeline();
      case NexSwipeAction.remind:
        await nexPickReminder(
          context: context,
          services: widget.services,
          note: note,
        );
        await widget.services.refreshTimeline();
      case NexSwipeAction.share:
        if (!await nexShareNote(note) && mounted) {
          nexShowBanner(context, message: l10n.nothingToCopy);
        }
      case NexSwipeAction.ask:
        if (!mounted) return;
        // Same guard the detail sheet uses: a button that can only answer
        // "unavailable" is worse than no button, and an edge bound to this
        // with no provider configured is exactly that.
        if (!AiChatSheet.availableFor(widget.preferences)) {
          nexShowBanner(context, message: l10n.chatUnavailable);
          return;
        }
        await AiChatSheet.show(
          context,
          preferences: widget.preferences,
          services: widget.services,
          history: widget.preferences.chatHistory,
          focus: note,
        );
    }
  }

  /// Folds a date run, or opens it.
  ///
  /// Opening is easy: the rows go into the list and each one animates itself
  /// in. Closing cannot work the same way — a row that has been removed has
  /// nothing left to animate — so the group is marked as closing, its rows
  /// stay in the list for exactly one animation while they shrink to nothing,
  /// and only then is the fold committed.
  ///
  /// The rows are kept rather than the whole group being built eagerly on the
  /// side, so the list stays lazy: `SliverList` still builds only what the
  /// viewport can see, which matters for a run like "Older" holding a
  /// hundred notes.
  Future<void> _toggleGroup(String key) async {
    nexBump();
    final closing = !_collapsedGroups.contains(key);
    if (closing) {
      setState(() {
        _closingGroup = key;
        _openingGroup = null;
        _collapsedGroups = {..._collapsedGroups, key};
      });
      await Future<void>.delayed(_foldDuration);
      if (!mounted) return;
      setState(() => _closingGroup = null);
    } else {
      setState(() {
        _closingGroup = null;
        _openingGroup = key;
        _collapsedGroups = {..._collapsedGroups}..remove(key);
      });
      await Future<void>.delayed(_foldDuration);
      if (!mounted) return;
      setState(() => _openingGroup = null);
    }
    await widget.preferences.setCollapsedTimelineGroups(_collapsedGroups);
  }

  /// Splits an already-ordered list into date runs.
  ///
  /// Walks the list rather than sorting it: the order is the repository's —
  /// pinned first, then newest — and re-deriving it here would be a second
  /// answer to the same question that could disagree with the first. A group
  /// simply ends where the bucket changes, which only works because the list
  /// arrives ordered, and which is why the pin gets its own group instead of
  /// interrupting whichever day it belongs to.
  List<_NoteGroup> _groupNotes(List<Note> source, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <_NoteGroup>[];

    for (final note in source) {
      final (key, label) = _bucketFor(note, today, l10n);
      if (groups.isEmpty || groups.last.key != key) {
        groups.add(_NoteGroup(key: key, label: label, notes: [note]));
      } else {
        groups.last.notes.add(note);
      }
    }
    return groups;
  }

  (String, String) _bucketFor(
    Note note,
    DateTime today,
    AppLocalizations l10n,
  ) {
    // Pinned before dated: a pinned note is held at the top on purpose, and
    // filing it under "Today" would put a heading over one row that then
    // repeats itself two rows later.
    if (note.pinnedAt != null) return ('pinned', l10n.timelineGroupPinned);

    // The same timestamp the list is ordered by. Grouping by createdAt while
    // sorting by updatedAt would scatter a group across the whole list.
    final at = note.updatedAt.toLocal();
    final day = DateTime(at.year, at.month, at.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return ('today', l10n.timelineGroupToday);
    if (days == 1) return ('yesterday', l10n.timelineGroupYesterday);
    if (days <= 7) return ('week', l10n.timelineGroupWeek);
    if (days <= 31) return ('month', l10n.timelineGroupMonth);
    return ('older', l10n.timelineGroupOlder);
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
      builder: (_) => NoteDetailSheet(
        services: widget.services,
        preferences: widget.preferences,
        noteId: note.id,
      ),
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
///
/// [_size] is larger than the icons across from it, and has to be. The asset
/// is a square canvas with the glyph inset inside it — the swirl is 54.7% of
/// the file's height, the rest transparent — so a box the same size as an
/// icon draws a mark visibly smaller than one. At 28 the glyph came out 15
/// logical pixels against the icons' 20 and read as undersized. 36 is what
/// puts the two on the same optical line; it does not make the mark bigger so
/// much as stop the padding from shrinking it.
class _WordmarkTile extends StatelessWidget {
  const _WordmarkTile();

  static const _size = 36.0;

  @override
  Widget build(BuildContext context) => Image.asset(
    Theme.of(context).brightness == Brightness.dark
        ? 'assets/branding/logo_dark.png'
        : 'assets/branding/logo_white.png',
    width: _size,
    height: _size,
    semanticLabel: 'Nex',
  );
}

/// "Good evening, Saeed ☀️" — the text and its animated mark on one line.
class _GreetingLine extends StatelessWidget {
  const _GreetingLine({
    required this.text,
    required this.glyph,
    required this.style,
    this.loading = false,
  });

  final String text;
  final String glyph;
  final TextStyle? style;

  /// The generated half is on its way. The greeting is already there, so the
  /// line dims rather than disappearing — a refresh should read as the words
  /// being replaced, not as them being taken away and given back.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty && !loading) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: NexMotion.standard,
      child: Opacity(
        key: ValueKey(text),
        opacity: loading ? 0.45 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          // The greeting's own language decides which end the mark sits at.
          // This string is written in the language of the user's name, which
          // is not necessarily the interface's — and the Row is what places
          // the glyph.
          textDirection: nexDirectionOf(text),
          children: [
            Flexible(
              child: Text(
                text,
                style: style,
                // Two, because the generated half joined on the end of a
                // greeting is regularly longer than one line and cutting it
                // mid-phrase reads as a bug.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (glyph.isNotEmpty) ...[
              const SizedBox(width: NexSpacing.xs),
              // The mark takes the line's own size: left alone it stays at
              // body size and sits visibly too large beside a small line.
              DefaultTextStyle.merge(
                style: style,
                child: _GreetingGlyph(glyph),
              ),
            ],
          ],
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

  /// The header row's height, open or closed — see the build method.
  static const _headerHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      label: semanticLabel,
      button: true,
      // The whole card is the toggle. A chevron is a small target for a
      // gesture with one meaning at any moment — open it, or fold it away —
      // and every part of the card that is not the refresh button now does
      // that. The chevron itself is gone: with the card doing the work it
      // was a second control for the same thing.
      child: NexTappable(
        onTap: onToggle,
        semanticLabel: toggleTooltip,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.pill),
        ),
        child: Container(
          width: double.infinity,
          // Directional. `fromLTRB` does not mirror, so in Persian the
          // sparkle — which is the row's *start* child, and therefore on the
          // right — was sitting in the 4-pixel inset meant for the refresh
          // button while the text below it kept a wider one. The two edges
          // that are supposed to line up were the two that did not.
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.cardInset,
            NexSpacing.xs,
            NexSpacing.xs,
            NexSpacing.xs,
          ),
          decoration: BoxDecoration(
            // The same fill the notes below it use, not the elevated tone.
            // Three different greys stacked down the top of the screen —
            // recap, search field, tag chips — read as three separate
            // materials; one reads as one surface with things on it.
            color: scheme.surfaceContainerLowest,
            // The search field's curvature, not the card radius used
            // elsewhere. These two sit directly above one another and were
            // visibly a step apart — 20 against the field's 24.
            borderRadius: BorderRadius.circular(NexRadius.pill),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fixed, and the same open or closed. The refresh button is
              // what gave this row its height, so dropping it on collapse
              // shrank the whole card to a thin strip that no longer read as
              // the same object folding away — and left a tap target barely
              // taller than the word inside it. 40 is the height that button
              // was setting anyway, so open is unchanged and closed now
              // matches it.
              SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
                    // The words "Daily Digest" are gone. The sparkle is the
                    // app's mark for anything a model wrote, this card is the
                    // only place it appears on the timeline, and a heading
                    // above two lines of text was naming something already
                    // named. Semantics still carry the title for anyone who
                    // cannot see the glyph.
                    const Spacer(),
                    // Refresh only while it is open, and it is then the only
                    // button on the card: closed, there is nothing on screen
                    // for a refresh to change, and a button that rewrites
                    // something you cannot see is a button that does nothing
                    // you can tell.
                    if (!collapsed)
                      IconButton(
                        tooltip: refreshTooltip,
                        onPressed: onRefresh,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.refresh, size: 20),
                      ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: NexMotion.slow,
                curve: NexMotion.curve,
                alignment: Alignment.topCenter,
                child: collapsed
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        // Start at zero, so the first character sits on the
                        // card's own inset and under the sparkle above it.
                        padding: const EdgeInsetsDirectional.fromSTEB(
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

  /// The backing appears only once the row is holding its place against
  /// content moving under it.
  ///
  /// Pinned headers need something opaque behind them or the list runs
  /// through the chips — but that is only true while something is passing
  /// underneath. Painted unconditionally it was a band of flat colour across
  /// the top of a screen whose background the reader had just chosen, at the
  /// one moment nothing was behind it to hide.
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      AnimatedContainer(
        duration: NexMotion.standard,
        curve: NexMotion.curve,
        color: overlaps
            ? Theme.of(context).colorScheme.surface
            : Colors.transparent,
        child: child,
      );

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
          // Only the selected chip is outlined. The rest sat in rings that
          // did no work the fill was not already doing.
          side: active ? BorderSide(color: scheme.primary) : BorderSide.none,
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
    super.key,
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

/// One date run: a heading and the notes under it.
class _NoteGroup {
  _NoteGroup({required this.key, required this.label, required this.notes});

  /// Stable across days, unlike the label. "Last week" holds different notes
  /// tomorrow; the key is what a collapsed state is remembered against.
  final String key;
  final String label;
  final List<Note> notes;
}

/// A row in the flattened list: either a heading or a note, never both.
class _TimelineRow {
  const _TimelineRow.header(this.group) : note = null, groupKey = null;
  const _TimelineRow.note(this.note, this.groupKey) : group = null;

  final _NoteGroup? group;
  final Note? note;

  /// Which run this note sits under. Needed only while a group is closing —
  /// see `_closingGroup`.
  final String? groupKey;
}

/// How long a run takes to fold away or open up.
const _foldDuration = Duration(milliseconds: 220);

/// The total vertical room a group heading claims, split 60/40 above and
/// below — see `_GroupHeader`.
const _headerSpace = NexSpacing.lg + NexSpacing.sm;

/// One note row, which grows in when its group opens and shrinks out when it
/// closes.
///
/// A `SizeTransition` rather than an `AnimatedSize`, because the two ends are
/// not symmetrical. A row that has just been inserted has to start closed and
/// open itself — that is the expand. A row on its way out is still in the list
/// only because [_TimelineScreenState._toggleGroup] is holding it there for
/// exactly this animation, and it has to reach zero before the fold commits.
///
/// The fade is deliberately faster than the size: content that disappears
/// before the space does reads as leaving, where the two together read as
/// being squashed.
class _FoldingRow extends StatefulWidget {
  const _FoldingRow({
    super.key,
    required this.open,
    required this.animateIn,
    required this.child,
  });

  final bool open;

  /// Whether this row is arriving now, or was already here.
  ///
  /// False means "start at full height and stay there". A row that was
  /// already on screen must not animate itself in when its index shifts —
  /// see [_TimelineScreenState._openingGroup].
  final bool animateIn;

  final Widget child;

  @override
  State<_FoldingRow> createState() => _FoldingRowState();
}

class _FoldingRowState extends State<_FoldingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _foldDuration,
      // Closed only when this row is genuinely arriving. Otherwise it starts
      // where it already was, which is the difference between one group
      // opening and every group below it flickering.
      value: widget.animateIn ? 0 : 1,
    );
    if (widget.open) _controller.forward();
  }

  @override
  void didUpdateWidget(_FoldingRow old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    widget.open ? _controller.forward() : _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Someone who asked for less motion gets none of this: the row is simply
    // there or not, which is what the setting means.
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.open ? widget.child : const SizedBox.shrink();
    }
    final curved = CurvedAnimation(
      parent: _controller,
      curve: NexMotion.curve,
      reverseCurve: NexMotion.curve.flipped,
    );
    return SizeTransition(
      sizeFactor: curved,
      child: FadeTransition(
        opacity: curved.drive(CurveTween(curve: const Interval(0.25, 1))),
        child: widget.child,
      ),
    );
  }
}

/// The heading over a date run: its fold control, and what can be done to the
/// whole run at once.
///
/// The heading itself is the fold target rather than the chevron alone — a
/// 16-pixel caret is a worse thing to aim at than a heading. The menu is
/// deliberately *outside* that target: it is the one other thing on the row,
/// and a three-dot button that also folded the group on the way to opening
/// would be a button that does two things at once.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    required this.onAsk,
    required this.onDelete,
  });

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Null when there is no provider to answer — a menu entry that can only
  /// say "unavailable" is worse than one that is not there.
  final VoidCallback? onAsk;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            expanded: !collapsed,
            label: label,
            child: InkWell(
              onTap: onToggle,
              // A heading is not a button, and the stock ripple across a full-width
              // row read as one — a slab of colour flashing under a label. Kept as
              // a hint that the row is live, at a quarter of the weight.
              splashFactory: NoSplash.splashFactory,
              highlightColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.04,
              ),
              hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.03),
              child: Padding(
                // Level with the cards below it — the same horizontal gutter
                // `nexCardInsets` gives them, so the heading and the run it names
                // start on the same line instead of the heading sitting inside the
                // margin.
                //
                // Vertically it is weighted 60/40 toward the top. A heading belongs
                // to what follows it, and even spacing makes it read as floating
                // between two runs rather than opening one.
                padding: const EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  _headerSpace * 0.6,
                  // Nothing on the trailing side: the menu button beside this
                  // carries its own, and the chevron sits just inside it rather
                  // than out at the screen edge on its own.
                  0,
                  _headerSpace * 0.4,
                ),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    // Only when folded. Open, the count is the list itself, and a
                    // number beside a heading you can already read is noise.
                    if (collapsed)
                      Text(
                        l10n.timelineGroupCount(count),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: NexMotion.standard,
                      curve: NexMotion.curve,
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          // The same vertical padding the heading carries, so the two glyphs
          // sit on one line. Without it the menu centred itself in the row's
          // full height while the chevron sat inside the heading's 60/40
          // weighting, and the pair read as very slightly crooked — which is
          // the kind of thing you see before you can say what it is.
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.xs,
            _headerSpace * 0.6,
            NexSpacing.md,
            _headerSpace * 0.4,
          ),
          child: PopupMenuButton<_GroupAction>(
            tooltip: l10n.groupActions,
            // Horizontal. A vertical ellipsis beside a chevron is two marks
            // running in two directions; laid flat it reads as a row of
            // controls rather than one control and a stray column of dots.
            icon: Icon(
              Icons.more_horiz,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            // Padding around the icon, not around the menu. The default is
            // large enough to set the height of every date heading in the
            // list; this keeps a tap target the thumb can find without the
            // button deciding how tall the row is.
            padding: const EdgeInsets.all(NexSpacing.sm),
            // Rounded, on a raised surface, sitting under the button rather
            // than over it.
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NexRadius.lg),
            ),
            color: theme.colorScheme.surfaceContainerHigh,
            elevation: 3,
            popUpAnimationStyle: AnimationStyle(
              duration: NexMotion.standard,
              curve: NexMotion.curve,
            ),
            onSelected: (action) => switch (action) {
              _GroupAction.ask => onAsk?.call(),
              _GroupAction.delete => onDelete(),
            },
            itemBuilder: (context) => [
              if (onAsk != null)
                PopupMenuItem(
                  value: _GroupAction.ask,
                  child: _GroupMenuRow(
                    icon: Icons.auto_awesome_outlined,
                    label: l10n.groupAsk,
                  ),
                ),
              PopupMenuItem(
                value: _GroupAction.delete,
                child: _GroupMenuRow(
                  icon: Icons.delete_outline,
                  label: l10n.groupDelete,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One line of the date heading's menu.
///
/// A plain row rather than a `ListTile`: a ListTile inside a PopupMenuItem is
/// two sets of vertical padding and two minimum heights fighting each other,
/// and the result was a menu whose rows were taller than they looked and
/// whose text sat off-centre against its own icon.
class _GroupMenuRow extends StatelessWidget {
  const _GroupMenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 20, color: tint),
        const SizedBox(width: NexSpacing.md),
        // Flexible, and so allowed to wrap. A popup menu is at most 280
        // logical pixels wide, and "Delete this group" beside an icon and a
        // gap does not fit that in every language — the ListTile this
        // replaced was quietly handling it, and a bare Row is not. The item
        // grows to a second line rather than clipping the label, because
        // `PopupMenuItem`'s height is a minimum.
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: tint),
          ),
        ),
      ],
    );
  }
}

/// What a date heading's menu can do to the whole run under it.
enum _GroupAction { ask, delete }
