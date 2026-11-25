import '../platform/crash_reporter.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        ClipRectLayer,
        OffsetLayer,
        PaintingContext,
        PipelineOwner,
        RenderAbstractViewport,
        RenderObject,
        RenderProxySliver,
        RenderRepaintBoundary,
        ScrollCacheExtent,
        ScrollDirection,
        SliverGeometry;
import 'package:flutter/foundation.dart'
    show ValueListenable, compute, listEquals, setEquals;

import '../documents/text_import.dart';
import '../platform/cycle_reminders.dart';
import '../platform/reminders.dart';
import '../platform/module_notification_route.dart';
import '../platform/note_copy.dart';
import '../platform/file_opener.dart';
import '../platform/hold_menu.dart';
import '../widgets/card_audio.dart';
import '../platform/tile_previews.dart';
import '../widgets/card_link.dart';
import '../widgets/nex_fold_pill.dart';
import '../widgets/nex_pull_refresh.dart';
import '../widgets/route_probe.dart';
import '../widgets/translate_sheet.dart';
import '../platform/photo_encoding.dart';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import '../platform/display_date.dart' show nexReadableDate;
import '../l10n/app_localizations.dart';

import 'package:nex_ai/cloud.dart';

import '../platform/capture_failure.dart';
import '../platform/daily_nudge.dart';
import '../platform/download_notice.dart';
import '../platform/model_install_controller.dart';
import '../platform/link_art.dart';
import '../platform/link_reader.dart';
import '../platform/nex_preferences.dart';
import '../platform/metrics.dart';
import 'timeline/timeline_model.dart';
import 'set_aside_screen.dart';
import 'cycle_screen.dart';
import 'update_sheet.dart';
import '../platform/brief_report.dart';
import '../platform/brief_refresh.dart';
import '../platform/nex_services.dart';
import '../platform/nex_widget.dart';
import '../platform/sponsor.dart';
import '../platform/route_observer.dart';
import '../platform/note_search.dart';
import '../platform/os_capture_bridge.dart';
import '../platform/sharing.dart';
import '../platform/update_service.dart';
import '../widgets/ai_chat_sheet.dart';
import '../widgets/summary_updated_time.dart';

import '../widgets/capture_sheet.dart';
import '../widgets/capture_flick.dart';
import '../widgets/card_strings.dart';
import '../widgets/copy_feedback.dart';
import '../widgets/tag_label.dart';
import '../widgets/note_context_menu.dart';
import '../widgets/note_grid_card.dart';
import '../widgets/commit_receipt.dart';
import '../widgets/commitments_sheet.dart';
import '../widgets/note_spotlight.dart';
import '../widgets/empty_timeline.dart';
import '../widgets/first_run_tour.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_banner.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/nex_brand.dart';
import '../widgets/search_field_header.dart';
import '../widgets/set_aside_flow.dart';
import '../widgets/sponsor_card.dart';
import '../widgets/search_filter_sheet.dart';
import '../widgets/search_results.dart';
import '../widgets/reminder_picker.dart';
import '../widgets/due_label.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/tag_picker.dart';
import '../desktop/desktop_note_card.dart';
import 'home_layout_sheet.dart';
import 'camera_sheet.dart';
import 'tools_screen.dart';
import 'guide_screen.dart';
import '../widgets/tips/home_tip.dart';
import '../widgets/tool_dates.dart';
import '../widgets/tips/nex_tips.dart';
import 'tools/pinned_tools.dart';
import 'intelligence_screen.dart';
import 'library_screen.dart';
import 'note_detail_sheet.dart';
import 'threads_screen.dart';
import 'photo_preview_screen.dart';
import 'settings_sheet.dart';

part 'timeline/timeline_screen_ties.dart';

part 'timeline/timeline_ai_brief.dart';

part 'timeline/timeline_brief_widgets.dart';
part 'timeline/timeline_header_widgets.dart';
part 'timeline/timeline_desktop.dart';
part 'timeline/timeline_grid.dart';
part 'timeline/timeline_filter_widgets.dart';
part 'timeline/timeline_groups.dart';
part 'timeline/timeline_list.dart';
part 'timeline/timeline_list_cards.dart';
part 'timeline/timeline_ai_header.dart';
part 'timeline/timeline_brief_sources.dart';
part 'timeline/timeline_capture.dart';
part 'timeline/timeline_note_actions.dart';
part 'timeline/timeline_navigation.dart';
part 'timeline/timeline_layout.dart';
part 'timeline/timeline_home_chrome.dart';
part 'timeline/timeline_dock_slot.dart';
part 'timeline/timeline_scroll.dart';
part 'timeline/timeline_sticky_day.dart';
part 'timeline/timeline_body.dart';
part 'timeline/timeline_selection.dart';
part 'timeline/timeline_commands.dart';
part 'timeline/timeline_rows.dart';
part 'timeline/timeline_shelves.dart';
part 'timeline/timeline_view_fade.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.services,
    required this.preferences,
    this.osCapture,
    this.updates,
    this.onLock,
    this.widgets,
    this.locked = false,
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

  /// Whether the app lock is covering this screen.
  final bool locked;

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
    with RouteAware, WidgetsBindingObserver, TickerProviderStateMixin {
  /// What the timeline shows: the notes, the filters, paging and the folded
  /// groups (W4.2). This State keeps only what is about showing it.
  late final TimelineModel _model = TimelineModel(
    services: widget.services,
    preferences: widget.preferences,
  );

  @visibleForTesting
  TimelineModel get model => _model;

  /// Groups and their rows, reused when only a group's fold state changes.
  final _rowsCache = _TimelineRowsCache();

  /// Built rows, reused across timeline deliveries that did not change them
  /// — see [_RowWidgetCache]. One note's save should not rebuild every card
  /// on the screen for it.
  final _rowWidgets = _RowWidgetCache();
  final _gridRowLayouts = Expando<NexGridRows>();
  NexGridRowSizing? _gridRowSizing;

  /// How many times the rows have been assembled — a test handle only.
  @visibleForTesting
  int get debugRowBuilds => _rowsCache.builds;

  /// How many row rebuilds the row cache skipped — a test handle only.
  @visibleForTesting
  int get debugRowReuse => _rowWidgets.hits;

  /// Keeps one card open at a time and lets a scroll close it.
  final NexSwipeController _swipe = NexSwipeController();

  /// The screen's one "a tap while something is open only closes it" rule
  /// (W4.5): a swiped card and a card's hold menu both register here, and
  /// every control that must not act meanwhile is a [NexTapGuarded].
  final NexTapGuardController _guard = NexTapGuardController();

  /// One controller per moving group, shared by list and grid.
  final _groupFolds = <String, AnimationController>{};

  /// Lets group slivers react to folds without rebuilding the timeline.
  final _groupFoldPulse = ValueNotifier<int>(0);
  String? landedId;

  /// The note a tapped reminder is about, until its border has finished
  /// pulsing.
  ///
  /// A tapped reminder used to open the app and stop there: the notification
  /// named the note, and the timeline then showed the same list it always
  /// shows, leaving the reader to find it.
  String? _spotlightId;
  bool _spotlightReady = false;
  int _revealGeneration = 0;
  Timer? _sponsorReturn;

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

  /// What is under the field fading in, each time search opens or closes:
  /// the results arrive as the header folds away, and the timeline comes
  /// back the same way, instead of one list replacing the other on a frame.
  late final AnimationController _searchFade = AnimationController(
    vsync: this,
    duration: NexMotion.enter,
    value: 1,
  );
  late final Animation<double> _searchFadeIn = CurvedAnimation(
    parent: _searchFade,
    curve: NexMotion.curve,
  );

  /// The dock's four destinations stepping back while someone reads down
  /// the list, and returning — see `_followDock`. Capture never moves.
  late final AnimationController _dockRecede = AnimationController(
    vsync: this,
    duration: NexMotion.exit,
    reverseDuration: NexMotion.enter,
  );
  late final Animation<double> _dockReceded = CurvedAnimation(
    parent: _dockRecede,
    curve: NexMotion.moveCurve,
    reverseCurve: NexMotion.moveCurve,
  );

  /// The dock's own run of it: it opens back out with a little give, which
  /// takes the value just under 0 (see [NexNavigationDock.recede]). Kept
  /// apart because what fades with the dock cannot fade past whole.
  late final Animation<double> _dockMorph = CurvedAnimation(
    parent: _dockRecede,
    curve: NexMotion.moveCurve,
    reverseCurve: const Cubic(0.34, 1.3, 0.64, 1).flipped,
  );
  final ValueNotifier<bool> _dockAway = ValueNotifier(false);

  /// How far the finger has carried the list one way since it last turned.
  double _dockTravel = 0;

  /// Whether this launch's first notes have been shown — see
  /// `_onModelChange`.
  bool _firstNotesShown = false;

  /// The old view's last frame, fading out over the new — see
  /// [_ViewDissolve].
  final _ViewDissolve _dissolve = _ViewDissolve();

  /// The note rows on screen, and the day of the one passing under the
  /// filter row — see [TimelineStickyDay].
  final Set<_DayMarkState> _dayMarks = {};

  /// The notes picked while picking several — see [_TimelineSelection].
  /// Empty is not picking.
  final Set<String> _selected = {};
  final ValueNotifier<String?> _stickyDay = ValueNotifier(null);
  final GlobalKey _stickyLine = GlobalKey();

  /// A sticky-day pass is waiting for this frame's layout — see
  /// `_queueStickyDay`.
  bool _stickyQueued = false;

  /// When the current search began, for [NexMetric.searchToOpen]. Null
  /// outside a search, and after its first note has been opened: the
  /// question is how long finding took, not how long the reading went on.
  Stopwatch? _searchStarted;

  /// The AI-generated recap under the headline — see [_loadAiSummary].
  String? _aiSummaryText;
  String _habitBriefSource = '';
  bool _habitBriefDirty = false;
  bool _aiSummaryHasHabits = false;
  StreamSubscription<String>? _habitBriefChanges;
  bool _aiSummaryLoading = false;

  /// The brief's candidate set, read from the library itself on each pass
  /// before fingerprinting — never the timeline's loaded page.
  List<Note> _briefCandidates = const [];

  /// The running brief flight, shared with a manual pull.
  Future<void>? _aiSummaryInFlight;
  Timer? _aiSummaryWake;

  /// The next instant the brief's facts change on their own — an item's
  /// moment passing, a recurring item's window opening, the day turning.
  ///
  /// Recomputed on every pass over the library and kept so the wake-up timer
  /// can be armed for it: a status is not a row, so nothing else would tell
  /// the card that it is out of date.
  DateTime? _briefBoundary;
  Timer? _ringingSync;

  /// Bumped when a pull-to-refresh finishes: the completion accent plays once.
  final _refreshPulse = ValueNotifier<int>(0);
  final _pullRefresh = NexPullRefreshController();
  bool _lastBriefRefreshFailed = false;
  bool _pullCancelled = false;
  bool _aiSummaryManualRequested = false;

  /// Whether this flight queried a model; used to honor manual pulls.
  bool _aiSummaryFlightAsked = false;
  bool _briefPreferencesQueued = false;
  String? _briefSettingsKey;
  int _setAsideTotal = 0; // read only while the home screen is empty
  bool _recurringArrivalHeld = false;
  String? _arrivalHeld; // a note a tap named while the lock was up
  NexModuleTarget? _moduleArrivalHeld;
  Locale? _briefLocale;
  late final Future<void> _briefCommitmentsReady;

  /// The AI-generated line across the top — see [_loadAiHeadline].
  String? _aiHeadlineText;

  /// The moment the line above was written for (`date|part|language`).
  ///
  /// Kept beside the words rather than trusted from the cache: the greeting
  /// must not outlive its hour even when nothing rewrites the cache.
  String? _aiHeadlineMoment;
  bool _aiHeadlineLoading = false;

  /// Fires at the next greeting boundary — see [_scheduleGreetingRollover].
  Timer? _greetingRollover;

  /// Folds the brief down to its first lines; the heading and its arrow
  /// stay. Persisted in [NexPreferences.daySummaryFolded], and changed by a
  /// tap alone: a scroll used to fold it too, which moved every card under
  /// a finger that was only trying to read them (2.8.0).
  late bool _aiSummaryCollapsed = widget.preferences.daySummaryFolded;

  /// Which note each line the app wrote in the brief is about, so a tap on
  /// the line opens it — see `_rememberBriefLines`.
  final Map<String, String> _briefLineNotes = {};
  int _aiSummaryExpansion = 0;
  bool _aiSummaryBeamPending = false;

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

  /// The same, in a wide window, where the notes are a grid.
  static const _desktopColumnWidth = 1240.0;

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
  /// never pops in under a thumb, then refreshed at most hourly — see
  /// [NexSponsorService].
  late final NexSponsorService _sponsor = NexSponsorService(
    preferences: widget.preferences,
  );

  @override
  void didUpdateWidget(TimelineScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locked && !widget.locked) _resumeHeldArrival();
  }

  @override
  void initState() {
    super.initState();
    _briefCommitmentsReady = _model.loadCommitments();
    unawaited(_releaseSetAside());
    _swipe.addListener(_onSwipeChanged);
    _model.addListener(_onModelChanged);
    _wireRinging();
    // A first return from a read-only sheet is not a settings change.
    _briefSettingsKey = _briefSettingsSignature();
    widget.preferences.addListener(_onBriefPreferencesChanged);
    _habitBriefChanges = widget.services.moduleChanges.listen((module) {
      if (module == 'habits' &&
          widget.preferences.briefHabitsAllowed &&
          mounted) {
        _habitBriefDirty = true;
        unawaited(_loadAiSummary());
      }
    });
    // Fire and forget, and deliberately not awaited anywhere: the card that
    // is already cached draws on this frame, and a fetch that never comes
    // back changes nothing on screen.
    // The picture from last time first, so a card fetched yesterday draws on
    // this frame instead of a second later; then the network, at most hourly.
    unawaited(
      _sponsor
          .restoreCachedImage()
          .then((_) {
            if (mounted) setState(() {});
            return _sponsor.refresh();
          })
          .then((_) {
            if (mounted) {
              _armSponsorReturn();
              setState(() {});
            }
          }),
    );
    _model.listen((delivered) {
      if (!mounted) return;
      _tourWhenReady();
      _requestAiHeader(delivered);
      // The library moved; tags may have moved with it. Guarded in loadTags.
      unawaited(_search.loadTags());
    }, onUnchanged: _refreshExternalBriefIfChanged);
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearchChanged);
    // The search's tag list; nothing ever loaded it (see note_search.dart).
    unawaited(_search.loadTags());
    // Both halves of a tapped reminder: one for a tap while the app is up,
    // one for the tap that started it.
    //
    // A scheduled note's notification names a note that is not in the
    // library until it is released, so release comes first.
    // «Cycle»'s alarms follow its prediction, which moves as the days pass
    // and does not survive a reinstall: re-armed once per launch.
    if (widget.preferences.cycleEnabled && widget.preferences.cycleSetUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          CycleReminders.apply(
            context: context,
            services: widget.services,
            preferences: widget.preferences,
          ),
        );
      });
    }
    widget.services.reminders.onOpenModule = _openModuleFromNotification;
    final launchedModule = widget.services.reminders.takeLaunchModule();
    if (launchedModule != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openModuleFromNotification(launchedModule),
      );
    }
    widget.services.reminders.onOpenNote = _openArrived;
    final launched = widget.services.reminders.takeLaunchNoteId();
    if (launched != null) _openArrived(launched, cold: true);
    widget.services.reminders.onOpenRecurring = _openRecurring;
    if (widget.services.reminders.takeLaunchedFromRecurring()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRecurring());
    }
    _wireOsRequests();
    // And both halves of a tapped download. Here rather than in the app
    // widget because opening a screen needs a Navigator, and the app widget
    // sits above the one this route lives in.
    widget.services.reminders.onOpenUpdate = _openUpdate;
    if (widget.services.reminders.takeLaunchedFromUpdate()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openUpdate());
    }
    unawaited(_loadTimeline());
    unawaited(_model.loadFilterTags());
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
  static const recapInterval = NexBriefRefresh.successInterval;

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
    return NexBriefRefresh.needsRefresh(
      at: at,
      text: text,
      storedSource: storedSource,
      fingerprint: fingerprint,
      now: now,
    );
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

  /// Marks a note as the one just captured, the way the capture paths do.
  ///
  /// Exposed so a test can exercise the receipt without driving the camera or
  /// the recorder; the production callers set [landedId] directly.
  @visibleForTesting
  void markLanded(String id) => setState(() => landedId = id);

  /// [setState], for the extensions in `timeline/` that carry this screen's
  /// behaviour by topic (W4.2): an extension is not a subclass, so it cannot
  /// call the protected method itself.
  void _rebuild(VoidCallback change) => setState(change);

  /// Where the list was when it last buzzed.
  ///
  /// A tick every [_scrollTickDistance] of travel — the trick the Windscribe
  /// app uses — rather than of time: a slow drag should tick slowly and a
  /// fling fast, and only distance does both without a state machine.
  double _lastTickOffset = 0;
  static const _scrollTickDistance = 64.0;
  static const _trimBelow = 1500.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_briefLocale == null) {
      // The first resolution is where the locale becomes known, not a
      // change to it. Seeding the key here keeps "learning the locale"
      // from reading as "the settings moved" — which would force a fresh
      // brief on every cold launch the moment the signature started to
      // name the locale.
      _briefLocale = locale;
      _briefSettingsKey = _briefSettingsSignature();
    } else if (_briefLocale != locale) {
      _briefLocale = locale;
      _onBriefPreferencesChanged();
    }
  }

  /// This screen's route, as [NexRouteProbe] last reported it; see
  /// `_onRoute` in timeline_navigation.dart.
  ModalRoute<Object?>? _route;

  /// Something has covered the timeline — another screen, or a sheet.
  ///
  /// That is the moment a reminder that has already rung stops having
  /// anything left to say: it was delivered as a notification, and it has now
  /// been on screen once more with the reader looking at it. Written here
  /// rather than on the way back, so that the return is the first frame
  /// without it.
  @override
  void didPushNext() => unawaited(_model.retireSpentReminders());

  /// Recheck the first-run tour when the timeline becomes visible.
  @override
  void didPopNext() {
    _tourWhenReady();
    // Back on the home screen: its destinations are where they are expected.
    _setDockAway(false);
    // Avoid re-rendering all cards on an unchanged route return.
    if (_briefSettingsKey != _briefSettingsSignature()) {
      _onBriefPreferencesChanged();
    }
  }

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
      _aiSummaryWake?.cancel();
      _ringingSync?.cancel();
      _greetingRollover?.cancel();
      unawaited(_model.retireSpentReminders());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _syncRinging();
      unawaited(_loadAiSummary());
      // A night phrase must not survive a night in the background: returning
      // to the app is one of the moments the greeting has to be looked at
      // again, even though nothing in the database changed.
      _onGreetingMomentChanged();
      _scheduleGreetingRollover();
      unawaited(_releaseSetAside());
      // A failed sponsor fetch is retried on a real return to the app rather
      // than by leaving timers behind in the timeline. The service's
      // 30-minute failure cool-off and hourly success interval still apply.
      // Only a card that actually changed redraws the timeline: a resume is
      // usually a no-op here, and rebuilding the whole list for it is not.
      unawaited(
        _sponsor.refresh().then((changed) {
          if (mounted) {
            _armSponsorReturn();
            setState(() {});
          }
        }),
      );
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
    _sponsorReturn?.cancel();
    _aiSummaryWake?.cancel();
    _greetingRollover?.cancel();
    widget.preferences.removeListener(_onBriefPreferencesChanged);
    unawaited(_habitBriefChanges?.cancel());
    _model.removeListener(_onModelChanged);
    _unwireRinging();
    _refreshPulse.dispose();
    _model.dispose();
    _swipe.removeListener(_onSwipeChanged);
    _swipe.dispose();
    _guard.dispose();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _searchFade.dispose();
    _dissolve.dispose();
    _dockRecede.dispose();
    _dockAway.dispose();
    for (final fold in _groupFolds.values) {
      fold.dispose();
    }
    _groupFoldPulse.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _stickyDay.dispose();
    super.dispose();
  }

  /// Notes already asked about, so one capture is never offered twice.
  final _threadOffered = <String>{};

  @override
  Widget build(BuildContext context) => NexRouteProbe(
    onRoute: _onRoute,
    child: NexTapGuard(controller: _guard, child: _screen(context)),
  );

  /// The pinch's fingers, while they are down. See `_pinchMove`.
  final _pinchPointers = <int, Offset>{};

  /// More than one finger has touched the list since it was last empty of
  /// fingers. Pull-to-refresh ignores the list while this holds.
  bool _multiTouch = false;

  double? _pinchDistance;

  bool _pinchApplied = false;
}
