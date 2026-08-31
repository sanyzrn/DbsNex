import 'package:flutter/cupertino.dart' show CupertinoPageTransition;
import 'package:flutter/material.dart';

/// A page route that keeps the route below paintable during a full-width
/// back-swipe. An opaque route lets the Navigator skip painting everything
/// below it once its entrance animation finishes; translating only its child
/// then reveals the Navigator's black backing rather than the previous page.
class NexPageRoute<T> extends PageRoute<T> {
  NexPageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;
  bool _opaque = false;

  @override
  bool get opaque => _opaque;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  void install() {
    super.install();
    animation?.addStatusListener(_handleAnimationStatus);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    _setOpaque(status == AnimationStatus.completed);
  }

  void revealPrevious() => _setOpaque(false);

  void coverPrevious() {
    if (animation?.status == AnimationStatus.completed) _setOpaque(true);
  }

  void _setOpaque(bool value) {
    if (_opaque == value) return;
    _opaque = value;
    if (animation?.status == AnimationStatus.completed &&
        overlayEntries.isNotEmpty) {
      overlayEntries.first.opaque = value;
    }
    changedInternalState();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => CupertinoPageTransition(
    primaryRouteAnimation: animation,
    secondaryRouteAnimation: secondaryAnimation,
    linearTransition: false,
    child: _NexSwipeBack(child: child),
  );

  @override
  void dispose() {
    animation?.removeStatusListener(_handleAnimationStatus);
    super.dispose();
  }
}

/// The Cupertino slide transition, with a back-swipe that can start anywhere
/// on the page rather than only at its leading edge.
///
/// The Cupertino page transition gives every pushed route a drag-to-pop, and
/// it is the convention this app follows — a horizontal drag
/// away from the leading edge takes you back, mirrored under RTL so a Persian
/// reader drags the way the text runs. What it does not give is *reach*: the
/// gesture is only recognised inside a 20-logical-pixel strip at the very
/// edge, which on a large phone is the one part of the screen a thumb has to
/// stretch for. The back arrow is at the same far corner, so a screen with a
/// long list had two ways back and both of them were in the corner.
///
/// So the Cupertino transition is kept exactly as it is — it owns the motion,
/// and its own edge gesture keeps working — and the page it wraps gains a
/// second recogniser spanning the whole width. Anything horizontally
/// scrollable inside the page still wins the gesture arena against it: a
/// recogniser closer to the pointer beats one further up the tree, which is
/// why dragging a row of tag chips still scrolls the chips.
class NexSwipeBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const NexSwipeBackPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: false,
      // The first route has nothing behind it, and a full-screen route that
      // says it is not popped by a back gesture — a form guarding unsaved
      // work — must not be popped by this one either.
      child: route.isFirst ? child : _NexSwipeBack(child: child),
    );
  }
}

/// Follows a back-swipe with the page, and pops when it has gone far enough.
class _NexSwipeBack extends StatefulWidget {
  const _NexSwipeBack({required this.child});

  final Widget child;

  @override
  State<_NexSwipeBack> createState() => _NexSwipeBackState();
}

class _NexSwipeBackState extends State<_NexSwipeBack>
    with SingleTickerProviderStateMixin {
  /// How much of the width has to be crossed for a slow drag to count.
  static const _commitFraction = 0.35;

  /// A flick counts at any distance. In logical pixels per second, the same
  /// order as the Cupertino gesture's own threshold.
  static const _commitVelocity = 700.0;

  /// Built in [initState] rather than lazily: a page whose back-swipe is
  /// never declined never touches this, and a `late final` would then run its
  /// initialiser inside [dispose] — asking a deactivated element for the
  /// TickerMode above it, which throws.
  late final AnimationController _settle;

  /// Where the page was when a declined drag let go, so the settle back to
  /// rest is a fraction of that rather than of the screen.
  double _settleFrom = 0;

  /// How far the page has been dragged back, in logical pixels, never
  /// negative: dragging the other way is the page staying where it is.
  double _drag = 0;
  bool _popping = false;

  /// True from the moment a back-swipe is recognised until the page is back
  /// at rest, whether or not it ever moved.
  ///
  /// Distinct from `_drag > 0` on purpose, and the difference is the bug this
  /// exists for. [_onStart] calls `revealPrevious`, which un-opaques the route
  /// so the page underneath begins painting — at a moment when the page has
  /// travelled nothing at all. Keying the surface off distance left two holes:
  /// a flicker on every swipe, for the frames between the gesture starting and
  /// the finger actually moving, and something worse for a drag the wrong way,
  /// which clamps to zero and stays there — so the page underneath showed
  /// through for the whole gesture. Both are the same mistake, that the page
  /// needs its surface from the moment something else can be seen behind it,
  /// not from the moment it has moved.
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _settle =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )
          ..addListener(
            () => setState(() => _drag = _settleFrom * (1 - _settle.value)),
          )
          ..addStatusListener((status) {
            if (status != AnimationStatus.completed || !mounted) return;
            // Back at rest. The route covers what is below it again, so this
            // page can stop carrying a surface of its own and let the app's
            // background through — which is the whole point of not simply
            // painting it opaque all the time.
            if (!_popping) _route?.coverPrevious();
            setState(() => _dragging = false);
          });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// +1 when back is to the right of the content, -1 when it is to the left.
  double get _sign =>
      Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;

  NexPageRoute<dynamic>? get _route {
    final route = ModalRoute.of(context);
    return route is NexPageRoute<dynamic> ? route : null;
  }

  /// This page's own entrance and exit, and the one belonging to a page
  /// pushed over it.
  ///
  /// Resolved once per dependency change rather than per build: a drag calls
  /// `setState` every frame, and rebuilding the merged listenable there would
  /// make [ListenableBuilder] drop and re-take its subscriptions every frame
  /// for a pair of animations that never change identity.
  ///
  /// The always-on constants are the resting values, so a widget somehow
  /// built outside a route reads as settled and on top rather than throwing.
  Animation<double> _primary = kAlwaysCompleteAnimation;
  Animation<double> _secondary = kAlwaysDismissedAnimation;
  Listenable _routeAnimations = Listenable.merge(const []);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _primary = route?.animation ?? kAlwaysCompleteAnimation;
    _secondary = route?.secondaryAnimation ?? kAlwaysDismissedAnimation;
    _routeAnimations = Listenable.merge([_primary, _secondary]);
  }

  /// Whether something is on screen beside this page right now, so that being
  /// see-through would let the two be read through each other.
  ///
  /// *In flight*, deliberately, rather than "not at rest". A settled sheet
  /// also parks this page's secondary animation away from zero, and treating
  /// that as movement would hold the page opaque for as long as the sheet
  /// stayed open — hiding the background pattern behind every sheet in the
  /// app, which is a worse bug than the one being fixed. Nothing overlaps
  /// dangerously once the motion has stopped: whatever is on top has settled
  /// and paints its own surface.
  bool get _moving =>
      _dragging || _drag > 0 || _inFlight(_primary) || _inFlight(_secondary);

  static bool _inFlight(Animation<double> animation) =>
      animation.status == AnimationStatus.forward ||
      animation.status == AnimationStatus.reverse;

  void _onStart(DragStartDetails details) {
    _settle.stop();
    // Set together, and before `revealPrevious`: the frame that first lets the
    // page underneath paint is the frame this page must already be opaque on.
    setState(() {
      _drag = 0;
      _dragging = true;
    });
    _route?.revealPrevious();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_popping) return;
    final delta = (details.primaryDelta ?? 0) * _sign;
    setState(() => _drag = (_drag + delta).clamp(0.0, double.infinity));
  }

  void _onEnd(DragEndDetails details) {
    if (_popping) return;
    final width = context.size?.width ?? 0;
    final velocity = details.velocity.pixelsPerSecond.dx * _sign;
    final committed =
        velocity > _commitVelocity ||
        (velocity > -_commitVelocity && _drag > width * _commitFraction);
    if (committed) {
      _popping = true;
      Navigator.of(context).maybePop();
      // The page comes back to rest either way. If the pop is taken this is
      // invisible under the route's own exit; if it is refused — a PopScope
      // guarding unsaved work — it is the difference between a page left
      // sitting 300 pixels over and one that simply did not go.
      _settleBack();
      // `maybePop`'s answer cannot be used for this: it reports whether the
      // *request* was handled, and a route that deliberately declines counts
      // as having handled it, so it returns true in exactly the case this
      // needs to detect. The route's own state is the honest signal — a route
      // that is really leaving stops being active.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isActive ?? false) _popping = false;
      });
      return;
    }
    // Not far enough. The page goes back where it was rather than snapping,
    // which is what tells you the gesture was seen and declined.
    _settleBack();
  }

  void _onCancel() {
    if (_popping) return;
    _settleBack();
  }

  void _settleBack() {
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onCancel,
      child: Transform.translate(
        offset: Offset(_drag * _sign, 0),
        // Opaque while it moves. Under the glass appearance a Scaffold is
        // deliberately transparent, so the app's background paints once at
        // the root and every page sits on it. That is right until a page
        // moves against the one behind it: two surfaceless pages overlap and
        // both of their contents are legible at once.
        //
        // A drag is not the only way that happens, which is what the first
        // version of this missed. It asked `_drag > 0` — a finger on the
        // screen — and a push or a pop is an *animation*, with `_drag` at
        // zero throughout. So the gesture was fixed and entering and leaving
        // a page were not: for the length of each transition the two pages
        // ran together, briefly and every time.
        //
        // The honest question is whether anything is moving beside this page:
        // arriving, leaving, being covered, uncovered, or dragged. At rest it
        // goes back to being see-through and the root background, pattern and
        // all, shows through as designed.
        //
        // `canvasColor` rather than the visual style's own base: it is the
        // same opaque background, it is already on ThemeData, and reaching for
        // it here keeps this widget out of the tokens/appearance import cycle.
        // `scaffoldBackgroundColor` is the one thing it cannot be — under
        // glass that is transparent, which is the whole bug.
        child: ListenableBuilder(
          listenable: _routeAnimations,
          // The wrap is unconditional and only the colour changes. Adding and
          // removing a `ColoredBox` around the page instead re-inflates
          // everything under it on the way in and again on the way out, which
          // costs the page its scroll position and its focus and shows as a
          // flicker at exactly the moment this is trying to look calm.
          builder: (context, child) => ColoredBox(
            color: _moving
                ? Theme.of(context).canvasColor
                : Colors.transparent,
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
