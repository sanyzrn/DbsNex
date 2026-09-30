part of '../timeline_screen.dart';

/// Arriving from outside the list: the first-run tour, a tapped reminder,
/// widget or notification, and the update screen.
extension _TimelineNavigation on TimelineScreenState {
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
    // Null is "not loaded yet" rather than "empty" — see [_model.all]. Either way
    // there is nothing to point at, and the next load comes back here.
    if (_model.all?.isEmpty ?? true) return;
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
    _rebuild(() {
      if (_searching) _exitSearch();
      _spotlightId = noteId;
    });
    unawaited(_revealSpotlight(noteId));
  }

  Future<void> _revealSpotlight(String noteId) async {
    // The group is expanded before the frame that would have to contain the
    // card is built, or the anchor below has nothing to find. Everything that
    // reads context happens here, ahead of the first await.
    final note = _model.byId(noteId);
    final now = DateTime.now();
    final key = note == null
        ? null
        : _bucketFor(
            note,
            DateTime(now.year, now.month, now.day),
            AppLocalizations.of(context),
          ).$1;
    if (key != null && _model.collapsedGroups.contains(key)) {
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

  /// A quick-capture notification button: straight to the kind it names.
  void _captureFromOs(OsCaptureMode mode) {
    if (!mounted) return;
    _surfaceTimeline();
    switch (mode) {
      case OsCaptureMode.text:
        unawaited(openCapture());
      case OsCaptureMode.voice:
        unawaited(captureVoice());
      case OsCaptureMode.photo:
        unawaited(capturePhoto(ImageSource.camera));
    }
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
}
