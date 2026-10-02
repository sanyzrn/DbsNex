import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable, compute;
import '../documents/text_import.dart';
import '../platform/note_copy.dart';
import '../platform/file_opener.dart';
import '../platform/hold_menu.dart';
import '../widgets/translate_sheet.dart';
import '../platform/photo_encoding.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import '../l10n/app_localizations.dart';
import 'package:nex_ai/cloud.dart';
import '../platform/capture_failure.dart';
import '../platform/daily_nudge.dart';
import '../platform/download_notice.dart';
import '../platform/link_reader.dart';
import '../platform/nex_preferences.dart';
import '../platform/metrics.dart';
import 'timeline/timeline_model.dart';
import 'update_sheet.dart';
import '../platform/brief_report.dart';
import '../platform/nex_services.dart';
import '../platform/nex_widget.dart';
import '../platform/sponsor.dart';
import '../platform/route_observer.dart';
import '../platform/note_search.dart';
import '../platform/os_capture_bridge.dart';
import '../platform/sharing.dart';
import '../platform/update_service.dart';
import '../widgets/ai_chat_sheet.dart';
import '../widgets/capture_sheet.dart';
import '../widgets/checklist_capture_sheet.dart';
import '../widgets/card_strings.dart';
import '../widgets/tag_label.dart';
import '../widgets/note_context_menu.dart';
import '../widgets/commit_receipt.dart';
import '../widgets/commitments_sheet.dart';
import '../widgets/note_spotlight.dart';
import '../widgets/empty_timeline.dart';
import '../widgets/first_run_tour.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_brand.dart';
import '../widgets/recording_sheet.dart';
import '../widgets/search_field_header.dart';
import '../widgets/sponsor_card.dart';
import '../widgets/search_filter_sheet.dart';
import '../widgets/search_results.dart';
import '../widgets/reminder_picker.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/tag_picker.dart';
import 'home_layout_sheet.dart';
import 'camera_sheet.dart';
import 'tools_screen.dart';
import 'intelligence_screen.dart';
import 'library_screen.dart';
import 'note_detail_sheet.dart';
import 'threads_screen.dart';
import 'photo_preview_screen.dart';
import 'settings_sheet.dart';

part 'timeline/timeline_header_widgets.dart';
part 'timeline/timeline_filter_widgets.dart';
part 'timeline/timeline_groups.dart';
part 'timeline/timeline_ai_header.dart';
part 'timeline/timeline_capture.dart';
part 'timeline/timeline_note_actions.dart';
part 'timeline/timeline_navigation.dart';
part 'timeline/timeline_layout.dart';
part 'timeline/timeline_sticky_day.dart';
part 'timeline/timeline_body.dart';
part 'timeline/timeline_selection.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.services,
    required this.preferences,
    this.osCapture,
    this.updates,
    this.onLock,
    this.widgets,
  });
  final NexServices services;
  final NexPreferences preferences;
  final OsCaptureBridge? osCapture;

  /// Feeds the home-screen widgets, so a fresh recap reaches them.
  ///
  /// Null in tests and on any platform with no widgets. The bridge watches
  /// the timeline stream by itself and needs no help with notes; the recap
  /// is the one thing it cannot see coming, because it is filed without
  /// notifying listeners on purpose — see [NexWidgetBridge.refresh].
  final NexWidgetBridge? widgets;

  /// Null in tests that do not care about updates.
  final UpdateService? updates;

  /// Closes the app lock now, without waiting for the app to be left.
  ///
  /// Null where there is no gate to close — the tests that build this screen
  /// on its own, and any host that is not [NexApp]. The button is offered
  /// only when there is both a lock turned on and something to close it.
  final VoidCallback? onLock;
  @override
  State<TimelineScreen> createState() => TimelineScreenState();
}

class TimelineScreenState extends State<TimelineScreen>
    with RouteAware, WidgetsBindingObserver {
  /// What the timeline shows: the notes, the filters, paging and the folded
  /// groups (W4.2). This State keeps only what is about showing it.
  late final TimelineModel _model = TimelineModel(
    services: widget.services,
    preferences: widget.preferences,
  );

  @visibleForTesting
  TimelineModel get model => _model;

  /// Keeps one card open at a time and lets a scroll close it.
  final NexSwipeController _swipe = NexSwipeController();

  /// The screen's one "a tap while something is open only closes it" rule
  /// (W4.5): a swiped card and a card's hold menu both register here, and
  /// every control that must not act meanwhile is a [NexTapGuarded].
  final NexTapGuardController _guard = NexTapGuardController();

  void _onSwipeChanged() {
    if (_swipe.openCard != null) {
      _guard.open(_swipe, close: _swipe.closeAll);
    } else {
      _guard.closed(_swipe);
    }
  }

  /// The groups whose rows are on their way out — see [_toggleGroup]. Empty
  /// at rest, which is every frame except the ~200ms after a fold. Several
  /// at once when a pinch folds every day.
  final Set<String> _closingGroups = {};

  /// The group whose rows are on their way in, for the same window.
  ///
  /// Needed because `SliverList` matches its children by index. Folding a run
  /// shortens the list, so every row below it arrives at a new index, gets a
  /// new [_FoldingRow] state, and — if that state animated itself in on
  /// creation — played the entrance animation. The result was every group
  /// below the one being folded flickering open, which is the report this
  /// exists to answer. Only the group actually being opened animates in;
  /// everyone else appears at full height, because they never left it.
  final Set<String> _openingGroups = {};
  String? landedId;

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
  /// because holding the headline refreshes it — see [_refreshHeadline]. With
  /// no AI provider that re-roll *is* the refresh.
  int _greetingVariant = math.Random().nextInt(3);
  bool _searching = false;

  /// The note rows on screen, and the day of the one passing under the
  /// filter row — see [TimelineStickyDay].
  final Set<_DayMarkState> _dayMarks = {};

  /// The notes picked while picking several — see [_TimelineSelection].
  /// Empty is not picking.
  final Set<String> _selected = {};
  final ValueNotifier<String?> _stickyDay = ValueNotifier(null);
  final GlobalKey _stickyLine = GlobalKey();

  /// When the current search began, for [NexMetric.searchToOpen]. Null
  /// outside a search, and after its first note has been opened: the
  /// question is how long finding took, not how long the reading went on.
  Stopwatch? _searchStarted;

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

  /// How wide the timeline's column of cards gets on a window with room to
  /// spare, and therefore how wide the bottom bar gets: the two are the same
  /// column, and a bar that ran past the cards it belongs to would read as
  /// belonging to the window instead.
  static const _timelineColumnWidth = 760.0;

  /// The tour itself, while it is running.
  OverlayEntry? _tour;

  /// The headline is a cold-launch thing, not a per-note-change thing —
  /// without this latch, every capture re-firing [timelineStream] would ask
  /// the provider for a new greeting.
  ///
  /// The recap is no longer behind it: it has a cadence of its own now (see
  /// [recapInterval]), and being asked on every delivery is how it notices
  /// that the day has moved on.
  bool _aiSummaryRequested = false;

  /// The card that is not a note. Read from cache on the first frame so it
  /// never pops in under a thumb, then refreshed at most once a day — see
  /// [NexSponsorService].
  late final NexSponsorService _sponsor = NexSponsorService(
    preferences: widget.preferences,
  );

  @override
  void initState() {
    super.initState();
    _swipe.addListener(_onSwipeChanged);
    _model.addListener(_onModelChanged);
    // Fire and forget, and deliberately not awaited anywhere: the card that
    // is already cached draws on this frame, and a fetch that never comes
    // back changes nothing on screen.
    // The picture from last time first, so a card fetched yesterday draws on
    // this frame instead of a second later; then the network, at most daily.
    unawaited(
      _sponsor
          .restoreCachedImage()
          .then((_) {
            if (mounted) setState(() {});
            return _sponsor.refresh();
          })
          .then((_) {
            if (mounted) setState(() {});
          }),
    );
    _model.listen((delivered) {
      if (!mounted) return;
      // The tour waits for a first note, and this is the path the note that
      // ends that wait arrives on.
      _tourWhenReady();
      _requestAiHeader(delivered);
    });
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearchChanged);
    _scroll.addListener(_onAiSummaryScroll);
    // Both halves of a tapped reminder: one for a tap while the app is up,
    // one for the tap that started it.
    widget.services.reminders.onOpenNote = _spotlight;
    final launched = widget.services.reminders.takeLaunchNoteId();
    if (launched != null) _spotlight(launched);
    // Both halves of a share Nex would not keep, for the same reason as the
    // two lines above: it can arrive into a running app, or be the intent
    // that launched it — in which case the refusal already happened, during
    // bootstrap, with nothing on screen to say so.
    widget.osCapture?.onRejected = _sayTooLarge;
    final refused = widget.osCapture?.takeRejection();
    if (refused != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _sayTooLarge(refused),
      );
    }
    // Both halves of a widget tap, in the same two worlds and for the same
    // reason: the Capture tile asks for the capture sheet, a Timeline row
    // asks for the note it is showing. A tap that cold-started the app
    // arrives while this screen is still being built, so it waits in the
    // bridge until there is something here to answer it.
    widget.osCapture?.onCaptureRequested = _openCaptureFromOs;
    widget.osCapture?.onCaptureModeRequested = _captureFromOs;
    // The platform keeps its own copy of this switch so the notification
    // survives a reboot; this makes the two agree after a restore or an
    // update.
    unawaited(
      QuickCaptureNotification.setEnabled(
        widget.preferences.quickCaptureNotification,
      ),
    );
    widget.osCapture?.onOpenNoteRequested = _openNoteFromOs;
    widget.osCapture?.onRecapRefreshRequested = _refreshRecapFromOs;
    widget.osCapture?.onOpenTimelineRequested = _openTimelineFromOs;
    final requested = widget.osCapture?.takeRequest();
    if (requested != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (requested.kind) {
          case PendingOsRequestKind.refreshRecap:
            _refreshRecapFromOs();
          case PendingOsRequestKind.capture:
            if (requested.captureMode case final mode?) {
              _captureFromOs(mode);
            } else {
              _openCaptureFromOs();
            }
          case PendingOsRequestKind.openTimeline:
            _openTimelineFromOs();
          case PendingOsRequestKind.openNote:
            _openNoteFromOs(requested.noteId!);
        }
      });
    }
    // And both halves of a tapped download. Here rather than in the app
    // widget because opening a screen needs a Navigator, and the app widget
    // sits above the one this route lives in.
    widget.services.reminders.onOpenUpdate = _openUpdate;
    if (widget.services.reminders.takeLaunchedFromUpdate()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openUpdate());
    }
    unawaited(_loadTimeline());
    unawaited(_model.loadFilterTags());
    unawaited(_model.loadCommitments());
    // After the first frame, because every stop measures a real widget and
    // none of them has been laid out yet at this point.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartTour();
      // Also here, not only where the recap resolves: the notification is
      // scheduled for people with no AI provider too, and for them nothing
      // else on this screen would ever re-arm it.
      _refreshDailyNudge();
      // Housekeeping, deliberately last and deliberately unawaited: it walks
      // the media directory, and nothing on this screen depends on the
      // answer. Throttled to once a day inside — see the service — so the
      // cost is not paid on every launch. Here rather than at boot because
      // the app has to be usable first; here rather than on the trash screen
      // because most people never open it, and the files this is for belong
      // to notes deleted long before the purge learned to take them.
      unawaited(widget.services.sweepOrphanMediaIfDue());
    });
  }

  /// How often the recap may be regenerated.
  ///
  /// It used to be once a calendar day, which meant a recap written at nine
  /// in the morning still described nine in the morning at bedtime. An hour
  /// is the other end of what is reasonable: it is a cadence somebody can
  /// predict, and it is nowhere near often enough to be felt in a battery or
  /// a bill.
  ///
  /// The interval is a floor, not a schedule. Nothing is asked for unless the
  /// notes being summarised have actually changed, so an app left open all
  /// afternoon with nothing written into it makes no requests at all.
  static const recapInterval = Duration(hours: 1);

  /// Whether the recap on file has stopped describing the notes it was made
  /// from, long enough ago to be worth asking again.
  ///
  /// Both halves matter and they are not interchangeable. Time alone would
  /// spend a provider call every hour on a library nobody has touched; change
  /// alone would spend one on every line typed into a long note. Asked for
  /// only when both are true, an app open all afternoon with nothing written
  /// into it makes no requests, and one being written into all afternoon
  /// makes one an hour.
  ///
  /// Static and given everything it needs, because it is the rule rather than
  /// a helper — a rule worth reading on its own and testing without a screen.
  static bool recapNeedsRefresh({
    required DateTime? at,
    required String? text,
    required String? storedSource,
    required String fingerprint,
    required DateTime now,
  }) {
    // Nothing on file, or nothing that says when — either way there is
    // nothing to measure against.
    if (at == null || text == null || text.isEmpty) return true;
    if (storedSource == fingerprint) return false;
    return !now.difference(at).isNegative &&
        now.difference(at) >= recapInterval;
  }

  /// A stable fingerprint of what a recap was written from.
  ///
  /// FNV-1a rather than `hashCode`, which Dart does not promise to keep
  /// stable between runs — and a fingerprint that changes when the process
  /// restarts would ask the provider for a new recap on every cold launch,
  /// which is the opposite of the point.
  @visibleForTesting
  static String recapFingerprint(String source) {
    var hash = 0x811c9dc5;
    for (final unit in source.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return '${source.length}:${hash.toRadixString(16)}';
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
    setState(() {
      _searching = true;
      _selected.clear();
    });
    _searchStarted = Stopwatch()..start();
    // After the frame: with the field switched off it is not in the list
    // until this setState puts it there, and a focus request aimed at a node
    // no widget has attached yet is simply dropped.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _searchFocus.requestFocus();
    unawaited(_search.run());
  }

  void _exitSearch() {
    _searchStarted = null;
    _searchFocus.unfocus();
    _search.clear();
    setState(() => _searching = false);
    // No scroll on the way out. Leaving search used to push the list back down
    // past the field to re-hide it; the field lives at the top now, so that
    // would just be the timeline jumping for no reason a user could name.
  }

  Future<void> _loadTimeline() async {
    // Both sides of this matter and neither replaces the other: the model's
    // failure state is what a read that never returns needs, and the tour
    // check is what a read that *does* return can make due.
    final loaded = await _model.load();
    if (!mounted || loaded == null) return;
    _requestAiHeader(loaded);
    _tourWhenReady();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => NexMetrics.shared.recordTimelineShown(),
    );
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  /// [setState], for the extensions in `timeline/` that carry this screen's
  /// behaviour by topic (W4.2): an extension is not a subclass, so it cannot
  /// call the protected method itself.
  void _rebuild(VoidCallback change) => setState(change);

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
    await Future.wait([
      widget.services.refreshTimeline(),
      _model.loadFilterTags(),
    ]);
    if (widget.preferences.syncBaseUrl == null) return;
    try {
      await widget.services.syncNow();
    } catch (error) {
      if (!mounted) return;
      banner?.show(
        message: '${l10n.syncFailed} (${NexServices.describeFailure(error)})',
        kind: NexBannerKind.failed,
      );
    }
  }

  Future<void> _selectTags(Set<String> tagIds) async {
    _tick();
    await _model.selectTags(tagIds);
  }

  Future<void> _selectType(NoteType? type) async {
    _tick();
    await _model.selectType(type);
  }

  Future<void> _selectOnlyReminders(bool only) async {
    _tick();
    await _model.selectOnlyReminders(only);
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
    _updateStickyDay();
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
    await _model.clearFilters();
  }

  /// Grows the timeline window when the list is close to its end.
  ///
  /// Not while searching — search results are their own query, not
  /// [NexServices.loadMoreTimeline]'s window.
  void _maybeLoadMore() {
    if (_searching) return;
    _model.loadMore();
  }

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
  void didPushNext() => unawaited(_model.retireSpentReminders());

  /// The timeline is back in front, so the walk-through may be due again.
  ///
  /// It is due exactly when this screen is the one being looked at, and the
  /// two moments that can make it due — the first note arriving, and a cold
  /// launch finishing its read — can both land while somebody is in Settings
  /// or the Library. [_maybeStartTour] now declines in that case, which would
  /// leave the tour never shown at all without somewhere to ask again.
  @override
  void didPopNext() => _tourWhenReady();

  /// Leaving the app counts as leaving the timeline.
  ///
  /// `didPushNext` only fires when another *route* covers this one, and the
  /// way a spent reminder is actually met is nothing like that: the
  /// notification arrives, the app is opened to read the note, and then the
  /// app is put away — no route is ever pushed. So a spent reminder was
  /// retired only for someone who happened to open Settings or the Library on
  /// the way out, and for everyone else it sat on the note until it was
  /// deleted by hand, which is the report.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_model.retireSpentReminders());
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
    _model.removeListener(_onModelChanged);
    _model.dispose();
    _swipe.removeListener(_onSwipeChanged);
    _swipe.dispose();
    _guard.dispose();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _searchFocus.dispose();
    _scroll.removeListener(_onAiSummaryScroll);
    _scroll.dispose();
    _stickyDay.dispose();
    super.dispose();
  }

  Future<void> openCapture() async {
    String? committed;
    // The three-second promise, timed the way a person lives it: from the
    // sheet opening to the note existing (W3.4).
    final opened = Stopwatch()..start();
    await nexShowSheet<void>(
      context: context,
      builder: (sheetContext) => CaptureSheet(
        services: widget.services,
        preferences: widget.preferences,
        onCommitted: (id) {
          committed = id;
          landedId = id;
          NexMetrics.shared
            ..record(NexMetric.capture, opened.elapsed)
            ..markCapture();
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
    // Once the sheet is closed, not at the first keystroke that created the
    // note: only then is there a whole note to compare.
    if (committed case final id?) unawaited(_offerThread(id));
  }

  /// The post-capture offer on its own, for tests that cannot drive a
  /// capture sheet to its close.
  @visibleForTesting
  Future<void> offerThreadFor(String noteId) => _offerThread(noteId);

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

  /// Notes already asked about, so one capture is never offered twice.
  final _threadOffered = <String>{};

  @override
  Widget build(BuildContext context) =>
      NexTapGuard(controller: _guard, child: _screen(context));

  /// Wraps the timeline in a pull-to-refresh that rewrites the recap, or
  /// hands [child] straight back when there is no recap on screen.
  ///
  /// The `enabled` branch is not a nicety. A pull that does nothing is worse
  /// than no pull — this screen has the scar to prove it — so the gesture is
  /// only attached where it has something to do.
  final _pinchPointers = <int, Offset>{};
  double? _pinchDistance;
  bool _pinchApplied = false;

  /// Whether this touch belongs to closing an open card or menu rather than
  /// to what it landed on.
  ///
  /// The controls inside the list are made inert structurally — see
  /// [NexTapGuarded]. The capture button and the app bar are `Scaffold` slots
  /// that ask instead.
  bool _claimedByOverlay() => _guard.claim();
}
