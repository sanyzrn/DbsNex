import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import '../platform/photo_encoding.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../widgets/recording_sheet.dart';
import '../widgets/search_field_header.dart';
import '../widgets/sponsor_card.dart';
import '../widgets/search_filter_sheet.dart';
import '../widgets/search_results.dart';
import '../widgets/reminder_picker.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/tag_picker.dart';
import 'home_layout_sheet.dart';
import 'intelligence_screen.dart';
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

  /// The first timeline read threw and there is nothing to show instead.
  /// Only ever true while `_all` is null: once data is on screen, a failed
  /// reload keeps the data it failed to replace.
  bool _loadFailed = false;
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

  /// Every tag the timeline is being narrowed to. Empty is "All".
  ///
  /// A set, because one pill could only ever answer "notes tagged work", and
  /// the question people actually have is "notes tagged work or home". They
  /// are OR-ed, not AND-ed: a note usually carries one of the tags somebody
  /// is thinking about, rarely all of them, and an AND across two tags is
  /// almost always empty.
  Set<String> selectedTagIds = const {};
  NoteType? selectedType;

  /// Show only notes with a reminder still ahead of them.
  ///
  /// A state, not a type, which is why it is its own field rather than a
  /// seventh entry in [selectedType]: a note is a photo *and* has a reminder,
  /// and a filter that made you choose between those two facts would be
  /// answering a question nobody asked. It layers on top of both other
  /// filters, the same way they layer on each other.
  ///
  /// "Still ahead" comes for free: a reminder that has rung and been seen is
  /// retired by `_retireSpentReminders`, so a note that still carries a
  /// `dueAt` is a note with something coming.
  bool onlyReminders = false;
  StreamSubscription<List<Note>>? subscription;
  String? landedId;

  /// Notes whose spent reminder has already had its one last showing.
  ///
  /// Read once into the frame rather than off preferences on every card: the
  /// set is rewritten when the timeline is covered, and a card that read it
  /// directly would change under a route transition.

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
  /// because holding the headline refreshes it — see [_refreshHeadline]. With
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
    _collapsedGroups = widget.preferences.collapsedTimelineGroups;
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
    subscription = widget.services.timelineStream.listen((value) {
      if (!mounted) return;
      setState(() {
        _loadFailed = false;
        _all = value;
        notes = _visible(value);
      });
      // The tour waits for a first note, and this is the path the note that
      // ends that wait arrives on.
      _tourWhenReady();
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
      _requestAiHeader(value);
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
            _openCaptureFromOs();
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
    unawaited(_loadFilterTags());
    unawaited(_loadCommitments());
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

  /// Says why a shared file was not kept.
  ///
  /// Names the file and its size next to the limit. "Too large" on its own
  /// invites the reader to think the app is broken; the numbers make it a
  /// rule they can work with, and the first sentence says plainly what kind
  /// of app is refusing.
  void _sayTooLarge(RejectedShare rejection) {
    if (!mounted) return;
    NexBannerHost.of(context)?.show(
      message: AppLocalizations.of(context).shareTooLarge(
        rejection.filename,
        nexFormatBytes(rejection.bytes),
        nexFormatBytes(rejection.limit),
      ),
      kind: NexBannerKind.failed,
    );
  }

  /// Shows the walk-through once, after the first note exists.
  ///
  /// It used to open on the first timeline after onboarding, which put two
  /// tutorials back to back: five pages of introduction, then four stops of
  /// overlay, and only then somewhere to write. For an app whose whole claim
  /// is capture in seconds, the first thing a new install did was ask to be
  /// read.
  ///
  /// Waiting for a note inverts that. The first thing that happens is the
  /// thing the app is for, and the tour arrives when it has something to
  /// point at and something to explain — where the note just written went,
  /// and how to find it again — rather than describing an empty screen to
  /// someone who has not used it yet.
  ///
  /// An install that already has notes still sees it once, so this changes
  /// when it opens and not whether.
  ///
  /// In an overlay rather than as part of this screen's tree: it has to paint
  /// over the app bar and the capture button, both of which the `Scaffold`
  /// draws above its own body.
  void _maybeStartTour() {
    // Switched off, deliberately and at the top, rather than deleted.
    //
    // A four-stop walkthrough that arrives before anybody has done anything
    // and asks to be clicked through is a toll on the first launch, and the
    // one thing this app promises is that capture costs nothing. It was also
    // the source of two separate bugs about *when* it appears, which is a
    // lot of correctness spent on a screen most people dismiss.
    //
    // Everything it needs is still here — the anchors, the stops, the
    // overlay — so bringing it back, or bringing it back as something
    // somebody asks for from the guide rather than something that happens to
    // them, is one line.
    if (!nexFirstRunTourEnabled) return;
    if (!mounted || widget.preferences.tourComplete || _tour != null) return;
    // Null is "not loaded yet" rather than "empty" — see [_all]. Either way
    // there is nothing to point at, and the next load comes back here.
    if (_all?.isEmpty ?? true) return;
    // And only while the timeline is the screen being looked at. Both things
    // that make the tour due — a first note arriving on the stream, a cold
    // launch finishing its read — can land seconds after launch, by which
    // time somebody may well have opened Settings. The tour went up over the
    // sheet anyway and pointed at four controls that were not on the screen:
    // its stops measure `GlobalKey`s on *this* screen's widgets, which are
    // still laid out underneath, so nothing failed loudly. [didPopNext] asks
    // again when the timeline comes back.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
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

  /// Whether the brief card is drawn at all.
  ///
  /// Not the same question as [_aiHeaderAvailable], which is about the
  /// greeting as well and is genuinely about whether a model can be reached.
  /// One of the brief's styles asks nothing of a model, and a card that works
  /// without one has no business being hidden because there is none — but
  /// only for somebody who chose that style. Left on the default, an app with
  /// intelligence switched off looks exactly as it did.
  bool get _briefAvailable =>
      _aiHeaderAvailable || !widget.preferences.briefStyle.usesModel;

  /// Builds an adapter with the user's chosen output language applied.
  ///
  /// Every call site here closes it; the caller owning the lifetime is why
  /// this is a factory and not a field.
  CloudAIAdapter _aiAdapter() => CloudAIAdapter(
    config: widget.preferences.aiProvider,
    outputLanguage: widget.preferences.aiOutputLanguage,
  );

  /// Fetches (or restores) the recap. Called on every timeline delivery; what
  /// keeps that from being a provider call per keystroke is [_recapIsStale].
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
    // Whatever is on file goes up first, stale or not. A recap from this
    // morning is worth reading while a newer one is being written, and it is
    // certainly worth more than an empty card.
    final cached = CloudAIAdapter.cleanDecorativeReply(prefs.aiDaySummaryText);
    if (mounted &&
        cached != null &&
        cached.isNotEmpty &&
        cached != _aiSummaryText) {
      setState(() => _aiSummaryText = cached);
    }
    final source = _aiRecapSource();
    if (source.isEmpty) return;
    final style = prefs.briefStyle;
    // Counted off the source rather than off the library — what the brief is
    // allowed to say follows what it was actually given — and then held to
    // whatever the reader asked for. The two are a floor and a ceiling, not
    // two opinions: a quiet day is short under "long", and a busy one does
    // not overflow under "short".
    final budget = nexBriefLines(
      '\n'.allMatches(source).length + 1,
    ).clamp(1, prefs.briefLength.lines);
    // What the app knows for itself. Written before anything is asked of
    // anybody, and under `report` it is the entire brief — which is why that
    // style needs no provider, no key and no signal.
    final written = style.statesFacts
        ? nexBriefReport(
            nexBriefFacts(_all ?? notes, commitments: _commitments),
            AppLocalizations.of(context),
            // One line kept back for the model to answer with, under the two
            // styles that ask it for one.
            maxLines: style.usesModel ? (budget - 1).clamp(1, budget) : budget,
          )
        : null;
    if (!style.usesModel) {
      if (!mounted) return;
      setState(() {
        _aiSummaryLoading = false;
        if (written != null && written.isNotEmpty) _aiSummaryText = written;
      });
      // Deliberately not filed and not pushed to the widget. This one is
      // rebuilt from the database every time the timeline moves, costs
      // nothing, and is never stale — storing it would only give the home
      // screen an older copy of something it can have fresh.
      _refreshDailyNudge();
      return;
    }
    // The settings that shape the brief are part of what it was made from,
    // exactly as the notes are. Without them on file, changing the style, the
    // tone, the length or the language left yesterday's brief on the card
    // until somebody happened to write a note — the setting appeared to do
    // nothing, because nothing asked for a new brief.
    //
    // The headline beside this one has always keyed its cache on the language
    // and so came back in English the moment it was chosen; the brief did
    // not, which is how an English greeting ended up sitting over a Persian
    // brief on the same screen.
    final fingerprint = recapFingerprint(
      nexBriefSignature(
        source: source,
        style: style,
        tone: prefs.briefTone,
        length: prefs.briefLength,
        language: prefs.aiOutputLanguage,
        instruction: prefs.briefInstruction,
      ),
    );
    if (!force && !_recapIsStale(fingerprint)) return;
    if (mounted) setState(() => _aiSummaryLoading = true);
    final adapter = _aiAdapter();
    String? text;
    // Kept apart from `text`, because under the styles that state their own
    // facts a failed request still leaves something on the card — and a tap
    // that quietly half-worked is the same broken control as one that did
    // nothing at all.
    var refused = false;
    try {
      final answer = await adapter.digest(
        source,
        lines: budget,
        style: style,
        tone: prefs.briefTone,
        instruction: prefs.briefInstruction,
        written: written ?? '',
        // A tap gets the full budget; the one that runs itself on launch does
        // not. On a network that is joined but not connected, ninety seconds
        // of spinner at the top of the timeline is what "the app loads slowly"
        // turns out to mean.
        timeout: force ? null : CloudAIAdapter.ambientTimeout,
      );
      // The app's lines stand whether or not the model answered. That is the
      // point of stating them separately: a brief that loses the rent being
      // overdue because a request timed out is a brief that cannot be relied
      // on for the one thing it is for.
      text = [
        if (written != null && written.isNotEmpty) written,
        if (answer != null && answer.isNotEmpty) answer,
      ].join('\n');
      if (text.isEmpty) text = null;
      refused = answer == null || answer.isEmpty;
    } catch (_) {
      text = written;
      refused = true;
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
    // Keeping the old line is right; saying nothing about the *tap* is not —
    // silence is what a broken button looks like. A quiet banner says the
    // refresh did not happen, and the old text stays.
    //
    // Only for the tap. This also runs once by itself, the first time the
    // timeline delivers any notes, and there the banner was an error nobody
    // asked for: it arrived seconds after launch, over whatever screen the
    // user had opened by then, about a card they may not even have looked at.
    // This method's own rule at the top says why that is wrong — the panel is
    // additive chrome, never a reason to show an error. A failure with no tap
    // behind it leaves yesterday's recap on the card and says nothing.
    if (force && (refused || text == null || text.isEmpty)) {
      if (!mounted) return;
      NexBannerHost.of(context)?.show(
        message: AppLocalizations.of(context).recapRefreshFailed,
        kind: NexBannerKind.failed,
      );
    }
    if (text != null && text.isNotEmpty) {
      unawaited(
        prefs
            .setAiDaySummary(
              text: text,
              dateKey: today,
              at: DateTime.now(),
              source: fingerprint,
            )
            // After it is on file, not before: the bridge reads the
            // preference rather than being handed the string, so pushing
            // first would write the snapshot from the old brief. This is the
            // whole of how a new recap reaches the home screen — the recap
            // is filed without notifying listeners, so nothing else would.
            .then((_) => widget.widgets?.refresh()),
      );
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
      final cached = CloudAIAdapter.cleanDecorativeReply(prefs.aiHeadlineText);
      if (mounted && cached != null && cached.isNotEmpty) {
        setState(() => _aiHeadlineText = cached);
        return;
      }
    }
    if (mounted) setState(() => _aiHeadlineLoading = true);
    final adapter = _aiAdapter();
    String? text;
    try {
      // Unlike the recap, an empty library is not a reason to skip this: the
      // line is a mood, and "you have not written anything yet" is a mood the
      // prompt handles on its own.
      text = await adapter.headline(
        _aiHeadlineSource(),
        language: language,
        // Same rule as the recap: a tap waits, a launch does not.
        timeout: force ? null : CloudAIAdapter.ambientTimeout,
      );
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

  /// Holding the headline explicitly asks for a new one.
  ///
  /// With no provider configured there is still something to refresh — the
  /// local greeting has three phrasings per time of day, and re-rolling one
  /// is what the same tap does. A tap target that does nothing on half the
  /// installs would be worse than not having it.
  void _refreshHeadline() {
    if (_aiHeadlineLoading) return;
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

  /// The screen where the assistant is switched on, from the notice that
  /// says it is not.
  ///
  /// Awaited, and the timeline rebuilds on the way back: turning intelligence
  /// on is exactly the change that makes the button this came from start
  /// doing something else.
  Future<void> _openIntelligence() async {
    await Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) => IntelligenceScreen(
          services: widget.services,
          preferences: widget.preferences,
        ),
      ),
    );
    if (mounted) setState(() {});
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

  bool _recapIsStale(String fingerprint) => recapNeedsRefresh(
    at: widget.preferences.aiDaySummaryAt,
    text: CloudAIAdapter.cleanDecorativeReply(
      widget.preferences.aiDaySummaryText,
    ),
    storedSource: widget.preferences.aiDaySummarySource,
    fingerprint: fingerprint,
    now: DateTime.now(),
  );

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

  /// The most recent notes' own text, newest first.
  ///
  /// The headline's source, and only the headline's. That line is a mood —
  /// it wants to know roughly what someone has been writing about and
  /// nothing else, and telling it what is due would turn a greeting into a
  /// second recap.
  String _aiHeadlineSource() {
    final recent = (_all ?? notes).take(20);
    final lines = <String>[
      for (final note in recent)
        (note.content ?? note.transcriptText ?? note.ocrText ?? '').trim(),
    ]..removeWhere((line) => line.isEmpty);
    return lines.join('\n');
  }

  /// The recap's source: the library's state, not a slice of its prose.
  ///
  /// Everything the recap can say about what is due or unfinished comes from
  /// here — see [nexRecapSource], which also explains why the twenty newest
  /// notes were the wrong twenty. The whole list goes in rather than a
  /// pre-cut slice, because the choosing is the part that matters and it
  /// needs everything to choose from.
  /// The standing obligations, as the brief last saw them.
  ///
  /// Held in a field rather than read inside [_aiRecapSource], because that
  /// method is synchronous and is called to *decide whether* to ask the model
  /// — a database read there would make the staleness check asynchronous and
  /// put a query on a path that mostly concludes "nothing has changed". They
  /// are refreshed when the screen loads and whenever the commitments screen
  /// closes, which is every moment they can have changed.
  List<NexCommitment> _commitments = const [];

  Future<void> _loadCommitments() async {
    try {
      final all = await widget.services.commitments();
      if (mounted) setState(() => _commitments = all);
    } catch (_) {
      // A brief without them is still a brief.
    }
  }

  String _aiRecapSource() =>
      nexRecapSource(_all ?? notes, commitments: _commitments);

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

  /// Clears one-off reminders that have already rung.
  ///
  /// A reminder is a thing to be reminded of, and once it has happened it is
  /// finished. It used to be kept on the note for ever and merely hidden from
  /// the card by a set of ids recorded here — so the note still carried a
  /// reminder, the detail sheet still offered to remove it, and removing it
  /// by hand was the only way to be rid of it. That was the report, three
  /// times: the trace stays on the item.
  ///
  /// Retired on the way out rather than the moment it lapses, so it gets
  /// exactly one more showing — a reminder that vanished while being read
  /// would be a reminder you never saw.
  ///
  /// A repeating one is never spent: its stored time is in the past by design
  /// after the first firing, and it is still going to ring again. Only a
  /// one-off can be finished with.
  Future<void> _retireSpentReminders() async {
    final now = DateTime.now().toUtc();
    final spent = [
      for (final note in _all ?? const <Note>[])
        if (note.dueRepeat == NoteRepeat.once)
          if (note.dueAt case final due?)
            if (!due.isAfter(now)) note.id,
    ];
    if (spent.isEmpty) return;
    var cleared = false;
    for (final id in spent) {
      // Re-read before clearing. `_all` is a snapshot, and the most likely
      // way to reach this code is by opening the note — which is also the
      // most likely place to push the reminder forward. Deleting a time the
      // reader has just chosen, because a list from a moment ago still said
      // it had lapsed, is the one mistake this must not make.
      final current = await widget.services.getById(id);
      if (current == null) continue;
      if (current.dueRepeat != NoteRepeat.once) continue;
      final due = current.dueAt;
      if (due == null || due.isAfter(DateTime.now().toUtc())) continue;
      // Null clears the repeat alongside the time, and cancels the alarm the
      // OS is still holding for it.
      await widget.services.setDueAt(id, null);
      cleared = true;
    }
    if (cleared) await widget.services.refreshTimeline();
  }

  /// Points at the note a reminder was about.
  ///
  /// A search or a filter left over from last time would hide the very note
  /// the reminder just named, so both are cleared first — and so is the
  /// collapsed state of whichever date group holds it, since a folded group
  /// is the other way for a card to be absent from a list that contains it.
  void _spotlight(String noteId) {
    if (!mounted) return;
    // A tapped reminder is an OS surface like any other: it means "show me
    // this note", and it cannot do that from underneath Settings.
    _surfaceTimeline();
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
  /// Asks for the header's recap and headline, once, as soon as there is
  /// anything to describe — from whichever delivery arrives first.
  ///
  /// This used to hang off the timeline stream alone, and that was a race the
  /// screen could lose without anything looking wrong. `_timelineController`
  /// is a broadcast controller, so an event fired before anyone is listening
  /// is not queued, it is gone — and `NexServices.bootstrap` fires one, from
  /// a `unawaited(refreshTimeline())`, long before this screen exists. The
  /// notes themselves were never at risk, because [_loadTimeline] fetches
  /// them directly rather than waiting to be told; only the recap was, and it
  /// then sat blank until the *next* event happened to come along — a
  /// capture, or leaving the app and coming back. That could be minutes, and
  /// what a person saw in the meantime was a card saying there was nothing to
  /// summarise on a library full of notes.
  ///
  /// So the trigger goes where the data does. Both paths call this, the flag
  /// makes it once, and whichever gets there first wins.
  void _requestAiHeader(List<Note> delivered) {
    if (delivered.isEmpty) return;
    // The recap is allowed to re-ask. Its own gate decides whether the notes
    // have moved on and whether an hour has passed, so calling it on every
    // delivery costs a hash and buys a recap that keeps up with the day.
    unawaited(_loadAiSummary());
    // The headline is not. It is a mood for the day with a day key of its
    // own, and re-rolling it on every capture would make the top of the
    // screen restless.
    if (_aiSummaryRequested) return;
    _aiSummaryRequested = true;
    unawaited(_loadAiHeadline());
  }

  Future<void> _loadTimeline() async {
    // Both sides of this matter and neither replaces the other: the failure
    // state below is what a read that never returns needs, and the tour check
    // is what a read that *does* return can make due.
    try {
      final loaded = await widget.services.timeline(limit: 200);
      if (!mounted) return;
      setState(() {
        _loadFailed = false;
        _all = loaded;
        notes = _visible(loaded);
      });
      _requestAiHeader(loaded);
      _tourWhenReady();
    } on Object {
      // A read that never comes back used to look identical to one still
      // coming: skeletons for as long as the app was open, with nothing to
      // tap. When there is nothing on screen yet the failure *is* the state;
      // once data is showing, keep it — a reload that fails must not blank
      // the screen it failed on.
      if (!mounted) return;
      setState(() => _loadFailed = _all == null);
    }
  }

  /// Re-checks whether the walk-through is due, after the frame.
  ///
  /// Called from both paths that can produce the first note: the initial load
  /// for an install that already has some, and the stream for the capture
  /// that has just made one. After the frame because each stop measures a
  /// real widget, which has to have been laid out first.
  void _tourWhenReady() {
    if (widget.preferences.tourComplete || _tour != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartTour());
  }

  /// FR-4 filter chips. TagFilterRow shipped in packages/ui, complete and
  /// covered by its own test, but nothing ever imported it — the timeline had
  /// no way to filter at all.
  ///
  /// Built from usage counts rather than the bare tag list: a tag nothing is
  /// tagged with anymore (its last note deleted, or created and never used)
  /// was still showing up as a pill that filtered to an empty list.
  /// Opens the update screen, from a tap on the download's notification.
  ///
  /// The installer is already on disk by then, so this lands on Install —
  /// which is the whole point of the notification saying it is ready.
  void _openUpdate() {
    final service = widget.updates;
    if (service == null || !mounted) return;
    // From a notification, so the same rule as every other OS surface: the
    // sheet opens on the timeline, not on top of wherever the app was left.
    _surfaceTimeline();
    unawaited(
      UpdateSheet.show(
        context,
        haptics: widget.preferences.haptics,
        service: service,
      ),
    );
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
    setState(() => selectedTagIds = tagIds);
    await _applyFilters();
  }

  Future<void> _selectType(NoteType? type) async {
    _tick();
    setState(() => selectedType = type);
    await _applyFilters();
  }

  Future<void> _selectOnlyReminders(bool only) async {
    _tick();
    setState(() => onlyReminders = only);
    await _applyFilters();
  }

  /// The content filter, behind the mockup's icon button.
  Future<void> _pickFilters() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await nexShowSheet<_FilterChoice>(
      context: context,
      // Scrollable, because the sheet's own body is `Flexible`: eight rows
      // fit a phone at the default text size and stop fitting a few notches
      // up, and a list that overflows is a list whose last row cannot be
      // reached at all.
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l10n.filters,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
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
            // The rows above answer "which kind of thing is it", and each of
            // them rules the others out. This one is not one of those: it is
            // a fact about a note rather than a kind of note, and it layers
            // on top of whichever kind is chosen. The line is what says so.
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.alarm),
              title: Text(l10n.filterHasReminder),
              trailing: onlyReminders ? const Icon(Icons.check) : null,
              selected: onlyReminders,
              // Tapping closes the sheet and applies, exactly like every row
              // above it — a switch that stayed put while the rest dismissed
              // would be two interaction models in one list.
              onTap: () =>
                  Navigator.pop(ctx, _ReminderChoice(only: !onlyReminders)),
            ),
          ],
        ),
      ),
    );
    switch (chosen) {
      case null:
        return;
      case _TypeChoice(:final type):
        await _selectType(type);
      case _ReminderChoice(:final only):
        await _selectOnlyReminders(only);
    }
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
      selectedTagIds = const {};
      selectedType = null;
      onlyReminders = false;
    });
    await _applyFilters();
  }

  bool get _filtering =>
      selectedTagIds.isNotEmpty || selectedType != null || onlyReminders;

  /// FR-4.5: the content-type filter layers on top of the tag filter — it is
  /// not a separate mode, so both selections resolve into one view.
  List<Note> _visible(List<Note> source) {
    final tagIds = selectedTagIds;
    final type = selectedType;
    return source.where((note) {
      if (onlyReminders && note.dueAt == null) return false;
      if (type != null && note.type != type) return false;
      if (tagIds.isNotEmpty && !note.tags.any((t) => tagIds.contains(t.id))) {
        return false;
      }
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
  void didPushNext() => unawaited(_retireSpentReminders());

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
      unawaited(_retireSpentReminders());
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
      dismissible: false,
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
      dismissible: false,
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
      final summary = await adapter.summarizeText(source);
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
      final encoded = identical(cropped, original)
          ? cropped
          : await compute(encodeEditedPhoto, (
              bytes: cropped,
              wasJpeg:
                  original.length > 2 &&
                  original[0] == 0xff &&
                  original[1] == 0xd8,
            ));
      final isPng =
          cropped.length >= 8 &&
          cropped[0] == 0x89 &&
          cropped[1] == 0x50 &&
          cropped[2] == 0x4E &&
          cropped[3] == 0x47;
      final dest = p.join(
        widget.services.mediaDir,
        'photo-${DateTime.now().microsecondsSinceEpoch}${identical(cropped, original) ? (isPng ? '.png' : p.extension(picked.path)) : photoExtension(encoded)}',
      );
      await File(dest).writeAsBytes(encoded, flush: true);
      final note = await widget.services.capturePhoto(
        mediaUri: dest,
        // The bytes are already in hand and a photo fits in memory, so hash
        // them here rather than re-reading the file. The share path cannot:
        // what arrives there is whatever was shared, up to a video.
        mediaHash: sha256OfBytes(encoded),
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
      actionLabel: failure == CaptureFailure.permission
          ? l10n.openSettings
          : l10n.retry,
      onAction: () => unawaited(
        failure == CaptureFailure.permission
            ? openCaptureSettings()
            : capturePhoto(source),
      ),
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
        actionLabel: AppLocalizations.of(context).openSettings,
        onAction: () => unawaited(openCaptureSettings()),
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
    // A recording this app made itself, so its length is bounded by how long
    // someone held the button — reading it back to hash is safe here in a way
    // it is not for a file that arrived from somewhere else.
    final bytes = await File(recorded).readAsBytes();
    final note = await widget.services.captureVoice(
      mediaUri: recorded,
      mediaHash: sha256OfBytes(bytes),
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

  /// The brief, as the first card above the notes.
  ///
  /// It has the note card's insets and corner, and none of its height rule.
  /// The sponsor card the slot was built for is pinned to exactly one card's
  /// height on purpose — a banner taller than the things around it has
  /// stopped being an item in a list and started being an interruption — but
  /// that reasoning is about a card selling something. This one is the app
  /// reading the day back, and how long it is depends entirely on how much
  /// there was to say. So it grows with its text.
  ///
  /// No icon, and no heading. The sparkle used to sit at the top of this and
  /// it was naming something already named: it is the only generated surface
  /// on the timeline, and the light going round its edge says so without
  /// spending a row of the screen.
  Widget _briefCard(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    const corner = BorderRadius.all(Radius.circular(NexRadius.lg));
    return Padding(
      padding: nexCardInsets,
      child: NexBorderBeam(
        borderRadius: corner,
        colors: [
          scheme.primary.withValues(alpha: 0.08),
          scheme.primary,
          scheme.primary.withValues(alpha: 0.08),
        ],
        thickness: 0.6,
        strength: _aiSummaryLoading ? 0.4 : 0.25,
        active: !_aiSummaryCollapsed,
        token: _aiSummaryLoading ? '…' : _aiSummaryText,
        child: NexGlassSurface(
          borderRadius: corner,
          showShadow: false,
          fallbackColor: scheme.surfaceContainerLowest,
          child: _AiDaySummaryPanel(
            // Keyed so a test can say "the brief is on screen" without
            // reaching for a glyph. It used to be found by its sparkle,
            // which is a thing any other surface could start wearing.
            key: const ValueKey('timeline-recap'),
            loading: _aiSummaryLoading,
            text: _aiSummaryText,
            emptyLabel: l10n.aiDaySummaryEmpty,
            collapsed: _aiSummaryCollapsed,
            semanticLabel: l10n.aiDaySummarySemanticLabel,
            toggleTooltip: _aiSummaryCollapsed
                ? l10n.aiDaySummaryExpand
                : l10n.aiDaySummaryCollapse,
            onToggle: _toggleAiSummary,
          ),
        ),
      ),
    );
  }

  /// The sponsor card, when there is one to show.
  ///
  /// Null on every path that means "nothing to show" — no file, an
  /// unparseable one, dates that have passed, another language, or one this
  /// person has already dismissed. Absence is silent by design: there is no
  /// placeholder and no error, because a card that failed to arrive and a
  /// day with no campaign are the same thing to the reader.
  ///
  /// Held back while searching or filtering: those are moments when somebody
  /// is looking for one specific note, and a card in the way of the answer is
  /// the worst possible time to ask for attention.
  Widget? _sponsorCard() {
    if (_searching || _filtering) return null;
    final sponsor = _sponsor.visible(
      languageCode: Localizations.localeOf(context).languageCode,
    );
    if (sponsor == null) return null;
    return SponsorCard(
      sponsor: sponsor,
      image: _sponsor.image,
      onOpen: () => unawaited(_openSponsor(sponsor)),
      onDismiss: () => unawaited(_dismissSponsor(sponsor)),
    );
  }

  Future<void> _openSponsor(NexSponsor sponsor) async {
    final url = sponsor.url;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    // Only the two schemes a card has any business using. A file:// or
    // intent:// url in a document fetched from a server is not a link, it is
    // an attempt at something else.
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser, or one that refused. Nothing to say about it.
    }
  }

  Future<void> _dismissSponsor(NexSponsor sponsor) async {
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    await _sponsor.dismiss(sponsor.id);
    if (mounted) setState(() {});
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
  String? _greeting(AppLocalizations interface, {String? aiPhrase}) {
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
    // Words only. There used to be a mark on the end of this line — a sun, a
    // moon, an owl, picked by the hour and animated in — and it is gone by
    // request. It was the one piece of decoration on the first screen, and
    // decoration is what this app is against everywhere else: the line is
    // already the softest thing on the timeline, and an emoji beside it made
    // it read as an app being cheerful at somebody rather than as somebody's
    // own notes greeting them.
    final text = switch (DateTime.now().hour) {
      >= 5 && < 12 => [
        l10n.greetingMorning,
        l10n.greetingMorningB,
        l10n.greetingMorningC,
      ],
      >= 12 && < 17 => [
        l10n.greetingAfternoon,
        l10n.greetingAfternoonB,
        l10n.greetingAfternoonC,
      ],
      >= 17 && < 23 => [
        l10n.greetingEvening,
        l10n.greetingEveningB,
        l10n.greetingEveningC,
      ],
      _ => [l10n.greetingNight, l10n.greetingNightB, l10n.greetingNightC],
    };
    // A comma in the script the name is written in — the phrase came back in
    // that language, so an ASCII comma in front of a Persian name is the same
    // seam this used to have between two half-sentences.
    if (aiPhrase != null && aiPhrase.isNotEmpty) {
      final comma = nexDirectionOf(name) == TextDirection.rtl ? '،' : ',';
      return '$aiPhrase$comma $name';
    }
    return text[v](name);
  }

  /// Everything above the search field: the greeting, the generated headline,
  /// and the recap card.
  ///
  /// Which of those appear depends on what is configured, and the four cases
  /// are the whole design:
  ///
  /// - nothing set up at all — no header, just the search field, as before;
  /// - a name but no AI — the greeting *is* the headline, at headline size,
  ///   and holding it re-rolls the phrasing;
  /// - AI but no name — the generated line alone;
  /// - both — the greeting small above, the generated line large below.
  ///
  /// The whole text block is one tap target rather than two: they read as one
  /// paragraph, and a refresh that only fires on the second of two adjacent
  /// lines is a refresh people report as broken.
  Widget _header(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final showGreeting = widget.preferences.showGreeting;
    final greeting = showGreeting
        ? _greeting(l10n, aiPhrase: _aiHeadlineText)
        : null;
    // The line is there either because there is a greeting to say or because
    // a provider is going to write one — the slot is a skeleton first and
    // text second, rather than appearing from nowhere later and pushing the
    // card below it down.
    final showLine = showGreeting && (greeting != null || _aiHeaderAvailable);
    // The brief used to live here too. It is its own card now, in the slot
    // above the notes — see [_briefCard].
    if (!showLine) return const SizedBox.shrink();
    final headlineStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: MediaQuery.sizeOf(context).height < 700 ? 20 : null,
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
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        MediaQuery.sizeOf(context).height < 700 ? NexSpacing.xs : NexSpacing.sm,
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
              onTap: () {},
              onLongPress: _refreshHeadline,
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
                  text: greeting ?? _aiHeadlineText ?? '',
                  loading: hasHeadlineSlot && _aiHeadlineLoading,
                  style: hasHeadlineSlot ? generatedStyle : headlineStyle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final glass = context.nexVisualStyle.liquidGlass;
    // The same condition the header uses to decide whether to draw the recap
    // at all. It decides here whether the pull is wired up, because the pull
    // exists to rewrite the recap and nothing else.
    final showSummary =
        !_searching && _briefAvailable && widget.preferences.showDaySummary;
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
          // First, so it never moves. The icons after it come and go with
          // settings — the search icon appears only when the field is off —
          // and a control that locks the library is the wrong one to have
          // slide under a thumb that was aiming at something else.
          if (widget.preferences.appLockEnabled && widget.onLock != null)
            IconButton(
              tooltip: l10n.securityLockNow,
              icon: const Icon(Icons.lock_outline),
              onPressed: () {
                if (widget.preferences.haptics) HapticFeedback.mediumImpact();
                widget.onLock!.call();
              },
            ),
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
            icon: const Icon(Icons.view_quilt_outlined),
            onPressed: () async {
              await nexShowSheet<void>(
                context: context,
                builder: (_) =>
                    HomeLayoutSheet(preferences: widget.preferences),
              );
              if (mounted) setState(() {});
            },
          ),
          // The library and the gear used to be here. They are the two things
          // on this screen somebody reaches for with a thumb rather than with
          // their eyes, and the top-right corner of a phone is the one place
          // a thumb cannot go — see [_bottomBar], which is where they live
          // now.
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
                  // the window edge while the cards sat in a narrower column — two
                  // things that belong to each other, visibly unaligned.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _timelineColumnWidth,
                    ),
                    // The pull rewrites the recap, and that is the only thing
                    // it does.
                    //
                    // For a long time there was no pull here at all, and the
                    // reasoning held: the timeline is a broadcast stream that
                    // every mutation path already re-fires, the filter row
                    // reloads on the same event, and "Sync now" lives in
                    // Settings where a sync server is configured. A pull that
                    // re-reads data which is already current does nothing,
                    // and this screen's own history says why that is worse
                    // than no gesture — the pull used to be "reveal the
                    // search field", and it was replaced precisely because it
                    // never revealed anything.
                    //
                    // The recap is the one thing on this screen that does not
                    // refresh itself: it is asked for at most once an hour,
                    // and until now the only way to ask sooner was a button
                    // sitting on the card. With the card gone, the gesture
                    // inherits the job — and it is still attached to a real
                    // one, so it is only wired up when there is a recap on
                    // screen to rewrite.
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: _wrapInRefresh(
                        // Only where a pull has something to ask for. The
                        // plain report is rebuilt from the database every
                        // time this screen moves, so there is nothing a
                        // gesture could refresh that is not already there.
                        enabled:
                            showSummary &&
                            widget.preferences.briefStyle.usesModel,
                        child: CustomScrollView(
                          controller: _scroll,
                          // Build nearby cards before they enter the viewport
                          // so local photo decoding happens during the scroll,
                          // not after the thumbnail is already on screen.
                          cacheExtent: 900,
                          // Always scrollable, so a short list still bounces rather
                          // than feeling locked.
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // The headline and the recap card, above the search
                            // field. Both collapse to nothing rather than leaving
                            // the list, the same reason the two headers below do.
                            SliverToBoxAdapter(
                              key: const ValueKey('timeline-header'),
                              child: NexInertWhileSwiped(
                                controller: _swipe,
                                child: AnimatedSize(
                                  duration: NexMotion.slow,
                                  curve: NexMotion.curve,
                                  alignment: Alignment.topCenter,
                                  child: _searching
                                      ? const SizedBox.shrink()
                                      : _header(l10n),
                                ),
                              ),
                            ),
                            // Both headers are always in the list, keyed, and collapse
                            // to zero extent rather than leaving it. A sliver list that
                            // changes length while another sliver changes its pinning
                            // leaves the viewport painting a child it never laid out.
                            // Kept in the list while a search is running even
                            // when it is switched off, or the field the app bar
                            // icon just asked for would not exist.
                            if (widget.preferences.showSearchField ||
                                _searching)
                              SliverPersistentHeader(
                                key: const ValueKey('search-header'),
                                delegate: SearchFieldHeader(
                                  extent:
                                      math.max(
                                        nexMinTapTarget,
                                        MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(16) *
                                                1.5 +
                                            16,
                                      ) +
                                      NexSpacing.xs +
                                      NexSpacing.sm,
                                  anchor: _searchAnchor,
                                  controller: _search.query,
                                  focusNode: _searchFocus,
                                  searching: _searching,
                                  onTap: () => unawaited(revealSearch()),
                                  onChanged: (_) => _search.schedule(),
                                  onClear: _exitSearch,
                                  filterCount: _search.activeFilterCount,
                                  onShowFilters: () => unawaited(
                                    nexShowSearchFilterSheet(
                                      context,
                                      search: _search,
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.preferences.showTagRow)
                              SliverPersistentHeader(
                                key: const ValueKey('filter-header'),
                                pinned: true,
                                delegate: _FilterRowHeader(
                                  visible: !_searching,
                                  extent:
                                      math.max(
                                        nexMinTapTarget,
                                        MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(14) *
                                                1.5 +
                                            16,
                                      ) +
                                      NexSpacing.md +
                                      NexSpacing.sm,
                                  child: NexInertWhileSwiped(
                                    controller: _swipe,
                                    child: TagFilterRow(
                                      tags: filterTags,
                                      hasOtherFilters:
                                          selectedType != null || onlyReminders,
                                      activeFilterLabel: [
                                        if (selectedType != null)
                                          l10n.noteType(selectedType!.wireName),
                                        if (onlyReminders)
                                          l10n.filterHasReminder,
                                      ].join(' · '),
                                      onOpenActiveFilter: () =>
                                          unawaited(_pickFilters()),
                                      onClearAll: () =>
                                          unawaited(_clearFilters()),
                                      selectedTagIds: selectedTagIds,
                                      allLabel: l10n.all,
                                      tagLabel: (tag) => nexTagLabel(tag, l10n),
                                      leading: _FilterButton(
                                        active:
                                            selectedType != null ||
                                            onlyReminders,
                                        onPressed: () =>
                                            unawaited(_pickFilters()),
                                      ),
                                      onSelected: (value) =>
                                          unawaited(_selectTags(value)),
                                    ),
                                  ),
                                ),
                              ),
                            // Above the list rather than spliced into it.
                            // `SliverList` matches its children by index — the
                            // fold animation depends on that — so a card that
                            // comes and goes inside it would renumber every row
                            // under it. Its own sliver has no such problem, and
                            // "the first card" is an honest place for something
                            // that is not a note.
                            //
                            // What sits here is the brief. The slot was built
                            // for the sponsor card and it is the right shape
                            // for the wrong thing: the first card on the
                            // screen should be the app's own reading of the
                            // day, not an advertisement.
                            if (showSummary)
                              SliverToBoxAdapter(child: _briefCard(l10n)),
                            ..._bodySlivers(l10n),
                            // And the sponsor goes last, under the notes.
                            // Nothing about a card that pays for itself earns
                            // the top of somebody's own page.
                            if (_sponsorCard() case final card?)
                              SliverToBoxAdapter(child: card),
                            // The capture button floats over the list, and on a
                            // device with a three-button navigation bar the system's
                            // own bar sits under that — the last card has to clear
                            // both, or it cannot be read or tapped.
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height:
                                    nexFabClearance + nexBottomInset(context),
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
            // Fade moving cards into the page tone before they pass beneath
            // the dock. This keeps the actions readable without a black band
            // cutting across the bottom of the light or Comfort appearance.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: nexBottomScrim + nexBottomInset(context),
              child: const IgnorePointer(child: _BottomScrim()),
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
      // The whole bottom bar goes in the Scaffold's floating slot, not in
      // `bottomNavigationBar`. A navigation bar is laid out *beside* the
      // body, so the list would stop at its top edge and the glass would
      // have nothing behind it but the page — the same mistake documented on
      // [NexGlassBar] for the top. Floating keeps the timeline running under
      // it, which is the only arrangement in which any of this is glass.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // Capture is a timeline action. Left up while searching, the bar read
      // as part of the search flow itself rather than what it actually still
      // did — open a fresh note, unrelated to whatever was just searched.
      floatingActionButton: _searching ? null : _bottomBar(l10n),
    );
  }

  /// One dock along the bottom, with capture lifted above its quieter actions.
  ///
  /// Recurring items and the assistant stay to one side, library and settings
  /// to the other. The four destinations share a surface so the raised capture
  /// button is unmistakably the primary action.
  ///
  /// It does not mirror in Persian. Every other row in the app does, and
  /// should, because it is made of words; this one is made of four fixed
  /// places at the bottom edge of the screen, and which thumb reaches which
  /// is not a fact about the language being read.
  Widget _bottomBar(AppLocalizations l10n) {
    return NexNavigationDock(
      leading: [
        NexDockAction(
          icon: Icons.event_repeat_outlined,
          tooltip: l10n.commitmentsTitle,
          onPressed: () async {
            if (_claimedBySwipe()) return;
            _tick();
            await CommitmentsSheet.show(context, services: widget.services);
            await _loadCommitments();
          },
        ),
        // Always drawn, even with nothing configured to answer. It used
        // to appear only when the assistant was usable, which left the
        // leading group one slot wide on most installs and two on
        // some: the bar visibly lopsided, and its buttons in different
        // places on different phones. A place in a bar is a promise
        // about where to put a thumb, and a place that comes and goes
        // is not one.
        //
        // What changes is the answer, not the button. With no provider
        // a tap says so and offers the screen that fixes it, which is
        // better than both of the things this used to do — open a chat
        // that cannot reply, or show nothing at all.
        NexDockAction(
          icon: Icons.auto_awesome,
          tooltip: l10n.assistant,
          onPressed: () {
            if (_claimedBySwipe()) return;
            if (AiChatSheet.availableFor(widget.preferences)) {
              _openAssistant();
              return;
            }
            _tick();
            nexShowBanner(
              context,
              // `ai`, because that is what it is about. There is no
              // `info` kind and this is not a failure: nothing was
              // attempted and nothing went wrong.
              kind: NexBannerKind.ai,
              haptics: widget.preferences.haptics,
              message: l10n.assistantNeedsIntelligence,
              actionLabel: l10n.assistantTurnOnIntelligence,
              onAction: () => unawaited(_openIntelligence()),
            );
          },
        ),
      ],
      // Hold capture to reach the assistant. The gesture stays even
      // though the assistant now has a button of its own: it has been
      // the way in for long enough that removing it would cost
      // somebody a habit, and it costs nothing to keep.
      //
      // Not the accent. Tapping this button and holding it are
      // different things, and lighting the same blue for both said
      // they were the same. Every assistant with an entrance uses a
      // spectrum for this reason — see [nexAssistantSpectrum].
      capture: NexLongPressGlow(
        colors: nexAssistantSpectrum,
        onHoldStart: _tick,
        onTriggered: () {
          if (_claimedBySwipe()) return;
          _openAssistant();
        },
        child: FloatingActionButton(
          key: _captureAnchor,
          onPressed: () {
            if (_claimedBySwipe()) return;
            openCapture();
          },
          tooltip: l10n.capture,
          child: const Icon(Icons.add, size: 32),
        ),
      ),
      trailing: [
        NexDockAction(
          key: _libraryAnchor,
          icon: Icons.inventory_2_outlined,
          tooltip: l10n.libraryTitle,
          // Awaited, and the timeline reloads on the way back. Tags
          // and Trash both live behind here and both change what this
          // screen shows, and neither refreshes it on its own.
          onPressed: () async {
            if (_claimedBySwipe()) return;
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
        NexDockAction(
          key: _settingsAnchor,
          icon: Icons.settings_outlined,
          tooltip: l10n.settings,
          badge: _updateDot(l10n),
          // Awaited so the commitments can be re-read on the way
          // back: they are not on the timeline stream that refreshes
          // everything else, and a brief that had not noticed the one
          // just added would look broken to whoever just added it.
          onPressed: () async {
            if (_claimedBySwipe()) return;
            await nexShowSheet<void>(
              context: context,
              builder: (_) => SettingsSheet(
                services: widget.services,
                preferences: widget.preferences,
                updates: widget.updates,
              ),
            );
            await _loadCommitments();
          },
        ),
      ],
    );
  }

  /// Wraps the timeline in a pull-to-refresh that rewrites the recap, or
  /// hands [child] straight back when there is no recap on screen.
  ///
  /// The `enabled` branch is not a nicety. A pull that does nothing is worse
  /// than no pull — this screen has the scar to prove it — so the gesture is
  /// only attached where it has something to do.
  Widget _wrapInRefresh({required bool enabled, required Widget child}) {
    if (!enabled) return child;
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerLowest,
      // Not `force: true` on a request already in flight: two in flight means
      // whichever finishes last wins, which is not necessarily the one the
      // pull asked for. The spinner still runs, and it is the honest picture
      // — something is being written, just not a second something.
      onRefresh: () async {
        if (_aiSummaryLoading) return;
        nexBump();
        await _loadAiSummary(force: true);
      },
      child: child,
    );
  }

  /// The dot on the gear, or nothing.
  ///
  /// Rebuilt from the update service rather than from this screen's state, so
  /// a check that finishes while the timeline is idle still shows.
  Widget? _updateDot(AppLocalizations l10n) {
    final service = widget.updates;
    if (service == null) return null;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => service.hasUpdate
          // TalkBack users get the one fact the dot carries — the only
          // update signal in the app was invisible to them.
          ? Semantics(
              label: l10n.updateAvailableBadge,
              child: const ExcludeSemantics(child: NexBadgeDot()),
            )
          : const SizedBox.shrink(),
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
      // A failed first read is a fourth state: skeletons that never resolve
      // are a hang the user can only interpret as "the app is broken".
      if (_loadFailed) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: NexEmptyState(
              icon: Icons.error_outline,
              message: l10n.timelineLoadFailed,
              action: FilledButton(
                onPressed: () {
                  setState(() => _loadFailed = false);
                  unawaited(_loadTimeline());
                },
                child: Text(l10n.tryAgain),
              ),
            ),
          ),
        ];
      }
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
            // Inert while a card is open: the fold, the menu and Ask all sit
            // in the same list as the swiped card, and the tap that puts it
            // away must not also do one of them.
            return NexInertWhileSwiped(
              controller: _swipe,
              child: _GroupHeader(
                label: group.label,
                count: group.notes.length,
                collapsed: _collapsedGroups.contains(group.key),
                onToggle: () => unawaited(_toggleGroup(group.key)),
                onAsk: AiChatSheet.availableFor(widget.preferences)
                    ? () => unawaited(_askAboutGroup(group))
                    : null,
                onDelete: () => unawaited(_deleteGroup(group, l10n)),
              ),
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
                  child: NoteContextMenu(
                    onOpen: () => _tapNote(note),
                    onAddTag: () => unawaited(_addTagTo(note)),
                    onDelete: () => unawaited(deleteWithUndo(note)),
                    child: NoteCard(
                      note: note,
                      strings: nexCardStrings(context),
                      onTap: () => _tapNote(note),
                      expanded: widget.preferences.isNoteExpanded(note.id),
                    ),
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
    if (_claimedBySwipe()) return;
    unawaited(_openNote(note));
  }

  /// Whether this touch belongs to closing an open card rather than to what
  /// it landed on.
  ///
  /// The controls inside the list are made inert structurally — see
  /// [NexInertWhileSwiped] — because a touch there falls through to the
  /// handler that closes. The capture button and the app bar are `Scaffold`
  /// slots outside that handler's reach, so ignoring their pointers would
  /// leave the card open with the tap going nowhere. They ask instead.
  bool _claimedBySwipe() {
    if (_swipe.openCard == null) return false;
    _swipe.closeAll();
    return true;
  }

  /// Brings the timeline itself to the front, before an OS surface acts on
  /// it.
  ///
  /// Every path below arrives from outside the app — a widget, a
  /// notification — and lands on this screen because this is where the
  /// answer lives. But "this screen" was not necessarily what was on screen:
  /// Android resumes a task exactly as it was left, so somebody whose last
  /// act in Nex was opening Settings tapped a widget and arrived in Settings,
  /// with the sheet the tap asked for opening behind it or not at all.
  ///
  /// So anything stacked over the timeline is dismissed first. That is the
  /// same thing the system back gesture does to those routes, one at a time,
  /// and it discards nothing the back gesture would have kept — a capture in
  /// progress is already saved, and an editor that has not been saved is
  /// already thrown away by a back press. Nothing is dismissed when the
  /// timeline is already what is showing, which is the ordinary case.
  void _surfaceTimeline() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.popUntil((route) => route.isFirst);
  }

  /// A plain tap on a widget: no errand, just the app.
  ///
  /// It does exactly the surfacing above and nothing else — which is the
  /// whole of what was missing, and why this looks like an empty method.
  void _openTimelineFromOs() {
    if (!mounted) return;
    _surfaceTimeline();
  }

  void _openCaptureFromOs() {
    if (!mounted) return;
    _surfaceTimeline();
    unawaited(openCapture());
  }

  void _openNoteFromOs(String noteId) {
    if (!mounted) return;
    _surfaceTimeline();
    unawaited(_openNoteById(noteId));
  }

  /// The Recap widget's refresh button, landing where it was always going to
  /// land: this screen's own refresh, forced past the cache exactly as the
  /// recap card's button forces it.
  ///
  /// The app comes to the front to do it, and that is the feature rather
  /// than a compromise. A brief is a model call, the home screen has no
  /// engine to make one with, and a button that silently opened an app would
  /// be worse than one that visibly does — so the tap lands on the timeline,
  /// the card spins where the reader can see it, and the new brief reaches
  /// the widget through the snapshot a moment later.
  void _refreshRecapFromOs() {
    if (!mounted) return;
    // The card that is about to spin has to be the card in front of you.
    _surfaceTimeline();
    unawaited(_loadAiSummary(force: true));
  }

  /// One note by id, the way a card tap opens it.
  ///
  /// A Timeline widget row *is* a card, so tapping it lands on the same
  /// sheet. The lookup is the only thing the ordinary path does not need: a
  /// row that cold-started the app is asking for a note this screen has not
  /// loaded yet. When it is already here this is exactly a card tap, undo
  /// toast and all; when it is not, the sheet loads the note by id itself
  /// and the only thing missing is the undo a delete would have offered —
  /// which is honest, since there is nothing on this screen to undo it back
  /// into.
  Future<void> _openNoteById(String noteId) async {
    final known = _all?.where((note) => note.id == noteId).firstOrNull;
    if (known != null) return _openNote(known);
    await nexShowSheet<DetailResult>(
      context: context,
      builder: (_) => NoteDetailSheet(
        services: widget.services,
        preferences: widget.preferences,
        noteId: noteId,
      ),
    );
    await widget.services.refreshTimeline();
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
    required this.style,
    this.loading = false,
  });

  final String text;
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
        // A Text, not a Row of one. The Row existed to place a mark at the
        // trailing end of the words; with the mark gone it was a layout
        // holding a single child and deciding nothing.
        child: Text(
          text,
          style: style,
          // The greeting is written in the language of the user's name, which
          // is not necessarily the interface's, and a Persian sentence laid
          // out left-to-right puts its full stop at the wrong end.
          textDirection: nexDirectionOf(text),
          // Two, because the generated half joined on the end of a greeting is
          // regularly longer than one line and cutting it mid-phrase reads as
          // a bug.
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// The brief: the first card above the notes, in the slot the sponsor card
/// used to have.
///
/// It went through being a grey card with three buttons on it, then a bare
/// paragraph with a rule down its edge, and it is a card again — but not the
/// same one. What the first version got wrong was the chrome, not the shape:
/// a heading naming something already named, a sparkle, and three controls
/// for things that belong elsewhere. Those are all gone and they are what is
/// staying gone. What it has instead is a light travelling round its border,
/// which says a model wrote this without spending a row of the screen saying
/// it in words.
///
/// It does not take a card's fixed height. That rule exists so a sponsor
/// card cannot become an interruption; this one is the app reading the day
/// back, and how tall it is depends on how much there was to say.
///
/// Nothing here is a button any more, and none of the three that left was
/// lost:
///   * the recurring items are in the bottom bar, next to the assistant;
///   * refresh is the pull, which now has something to do — see the comment
///     on the timeline's `RefreshIndicator`;
///   * folding it away is still a tap, on the text itself.
class _AiDaySummaryPanel extends StatelessWidget {
  const _AiDaySummaryPanel({
    super.key,
    required this.loading,
    required this.text,
    required this.emptyLabel,
    required this.collapsed,
    required this.semanticLabel,
    required this.toggleTooltip,
    required this.onToggle,
  });

  final bool loading;
  final String? text;
  final String emptyLabel;
  final bool collapsed;
  final String semanticLabel;
  final String toggleTooltip;
  final VoidCallback onToggle;

  /// What the first line is set at, relative to the rest.
  ///
  /// A lede, not a heading: the same face and the same weight, one step up in
  /// size. Anything more and it becomes the title this deliberately does not
  /// have.
  static const _ledeScale = 1.12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      button: true,
      // What the tap does, which used to be a tooltip on a chevron that no
      // longer exists. A screen reader is the one place the affordance still
      // has to be spelled out: sighted readers get a paragraph that folds,
      // and there is nothing about a paragraph that needs explaining.
      hint: toggleTooltip,
      child: GestureDetector(
        // Not a [NexTappable]: its pressed fill is drawn on the shape it is
        // given, and the shape here belongs to the glass surface outside it,
        // which would end up with a grey wash over its own material.
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Padding(
          // A card's inset now that this is a card. It used to be a
          // paragraph loose on the page, where the only thing keeping it off
          // the edge was the header's own margin.
          padding: const EdgeInsets.all(NexSpacing.cardInset),
          child: AnimatedSize(
            duration: NexMotion.slow,
            curve: NexMotion.curve,
            alignment: Alignment.topCenter,
            // No rule down the edge any more, and still no heading. The
            // light going round the card says the same thing the rule did —
            // a model wrote this — and two marks for one fact is one mark
            // too many.
            child: collapsed
                ? _CollapsedRecap(label: _firstLine ?? emptyLabel)
                : _body(theme),
          ),
        ),
      ),
    );
  }

  /// The recap's opening sentence, for the folded state.
  String? get _firstLine {
    final value = text?.trim();
    if (value == null || value.isEmpty) return null;
    final end = value.indexOf('\n');
    return end == -1 ? value : value.substring(0, end);
  }

  Widget _body(ThemeData theme) {
    final value = text;
    // Defaulted rather than carried around as a nullable: the lede's size is
    // this one's times a factor, and `base?.copyWith(base.fontSize ...)` does
    // not compile — a `?.` does not promote its own receiver inside its
    // arguments.
    final base = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final body = base.copyWith(height: 1.45);
    if (value == null) {
      // No skeleton bars. They were the last thing in here shaped like a
      // box, and two grey rectangles at the top of a first launch could be
      // anything; the sentence that says there is nothing to summarise yet
      // is the same sentence either way, so it is simply dimmed while the
      // first one is being written.
      return AnimatedOpacity(
        opacity: loading ? 0.5 : 1,
        duration: NexMotion.slow,
        curve: NexMotion.curve,
        child: Text(
          emptyLabel,
          style: body.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.start,
          textDirection: nexDirectionOf(emptyLabel),
        ),
      );
    }
    final lines = value.trim().split('\n');
    final lede = lines.first;
    final rest = lines.skip(1).join('\n').trim();
    // Cross-faded rather than dimmed and left in place: a rewrite replaces
    // the text, and a paragraph that goes translucent and comes back with
    // different words in it is the honest picture of that.
    return AnimatedOpacity(
      opacity: loading ? 0.45 : 1,
      duration: NexMotion.slow,
      curve: NexMotion.curve,
      child: Column(
        // Min, because this sits in an [IntrinsicHeight] row: a column that
        // asks for all the height there is has no intrinsic height to give.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lede,
            style: body.copyWith(fontSize: (base.fontSize ?? 14) * _ledeScale),
            textDirection: nexDirectionOf(lede),
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.sm),
            // Per line, because the recap is written in the language of the
            // notes and the notes are the one place in this app most likely
            // to be in both at once — see [NexBodyText].
            //
            // Not selectable, unlike the note body in the detail sheet. The
            // whole card is one button — a tap anywhere on it folds the brief
            // away — and a `SelectionArea` would claim that tap for clearing
            // a selection. A paragraph you can select inside a card that
            // stops responding is the worse of the two trades.
            NexBodyText(rest, style: body),
          ],
        ],
      ),
    );
  }
}

/// The recap folded away: one line, truncated, with no rule beside it.
///
/// The rule stays behind on purpose. Open, it marks a block of generated
/// prose; closed, there is no block, and a two-pixel accent stripe next to a
/// single grey line reads as a status colour on a row — which is a different
/// claim than the one it is there to make.
class _CollapsedRecap extends StatelessWidget {
  const _CollapsedRecap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      textDirection: nexDirectionOf(label),
    );
  }
}

class _FilterRowHeader extends SliverPersistentHeaderDelegate {
  const _FilterRowHeader({
    required this.child,
    required this.visible,
    required this.extent,
  });

  final Widget child;

  /// Searching hides it, by collapsing rather than by leaving the sliver list.
  final bool visible;

  // The row's own height: a 48px target plus the padding TagFilterRow carries.
  final double extent;

  @override
  double get minExtent => visible ? extent : 0;

  @override
  double get maxExtent => visible ? extent : 0;

  /// Opaque from the first frame, so glass or patterned content cannot leak
  /// through the pinned strip or change its tone during scrolling.
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);

  /// Always, and for the same reason as [SearchFieldHeader].
  ///
  /// This one happened to rebuild anyway, because `child` is a fresh
  /// `TagFilterRow` on every build and the comparison is by identity — so it
  /// escaped the stale-theme bug by accident rather than by design. Relying on
  /// that is relying on a widget never gaining an `operator ==`.
  @override
  bool shouldRebuild(_FilterRowHeader old) => true;
}

/// What the filter sheet came back with.
///
/// Wrapped rather than returned bare so that "All" survives the trip back
/// through `Navigator.pop`, which cannot distinguish a null result from a
/// dismissal — and sealed because the sheet now answers on two axes, and a
/// switch over it is what keeps a third from being forgotten at the call
/// site.
sealed class _FilterChoice {
  const _FilterChoice();
}

class _TypeChoice extends _FilterChoice {
  const _TypeChoice(this.type);
  final NoteType? type;
}

class _ReminderChoice extends _FilterChoice {
  const _ReminderChoice({required this.only});
  final bool only;
}

/// The mockup's leading icon button on the filter row.
///
/// Carries its selected state whenever anything in the sheet behind it is
/// filtering, so an active filter is visible without opening it.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onPressed});

  /// Whether anything in the sheet is narrowing the timeline — a content
  /// type, the reminder filter, or both. A bool rather than the selection
  /// itself: what this button draws is "something is on", and it should not
  /// have to grow a parameter every time the sheet gains an axis.
  final bool active;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          // "No notes" was a lie: the library has notes, the filters are
          // what hides them. Search already had the honest sentence; the
          // timeline's filter-empty now uses it too.
          Text(l10n.filteredEmpty, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          TextButton(onPressed: onClear, child: Text(l10n.clearFilters)),
        ],
      ),
    );
  }
}

/// The fade behind the bottom bar.
///
/// Three stops rather than two. A straight ramp from black to nothing puts
/// its colour across the middle of the band, which is exactly where the last
/// note card sits; weighting it to the bottom leaves the cards alone.
class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    final base = context.nexVisualStyle.baseColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A near-opaque page tone masks stray text under the dock but retains the
    // chosen background's hue. In light mode a black scrim looked like dirt on
    // the warm page, particularly with Comfort Mode enabled.
    final ceiling = dark ? 0.90 : 0.84;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            base.withValues(alpha: ceiling),
            base.withValues(alpha: ceiling * 0.55),
            base.withValues(alpha: ceiling * 0.18),
            base.withValues(alpha: 0),
          ],
          // Four stops let the tail disappear without a visible line across
          // a card still scrolling behind it.
          stops: const [0, 0.3, 0.62, 1],
        ),
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
