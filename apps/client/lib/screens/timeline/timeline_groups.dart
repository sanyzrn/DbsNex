part of '../timeline_screen.dart';

/// One date run — or, arranged by kind or tag, one shelf (2.7.0): a heading
/// and the notes under it.
class _NoteGroup {
  _NoteGroup({
    required this.key,
    required this.label,
    required this.notes,
    this.shelf,
    this.echoes = const {},
  });

  /// The shelf this group shows, when the home is arranged by kind or tag.
  /// Null for a day.
  final NexShelf? shelf;

  /// Notes already shown under an earlier heading — by tag, a note carrying
  /// two tags sits on both shelves. Only its first appearance is the one a
  /// reveal scrolls to: a [GlobalKey] can be on one widget only.
  final Set<String> echoes;

  /// Whether the heading's count and actions cover the whole group: a shelf
  /// showing its newest few holds more than it shows, and deleting "Photos"
  /// must not quietly mean "these six photos".
  bool get complete => !(shelf?.more ?? false);

  /// The heading's count: everything the shelf holds, not just what it shows.
  int get count => shelf?.total ?? notes.length;

  /// Stable across days, unlike the label. "Last week" holds different notes
  /// tomorrow; the key is what a collapsed state is remembered against.
  final String key;
  final String label;
  final List<Note> notes;

  late final rows = [
    for (final note in notes)
      _TimelineRow.note(note, primary: !echoes.contains(note.id)),
    if (!complete) _TimelineRow.more(this),
  ];
}

/// A note or an arranged shelf's "See all", keyed within its group.
class _TimelineRow {
  const _TimelineRow.note(this.note, {required this.primary}) : moreOf = null;
  const _TimelineRow.more(this.moreOf) : note = null, primary = false;

  final Note? note;
  final _NoteGroup? moreOf;
  final bool primary;

  String get key => note == null ? 'more' : 'note-${note!.id}';
}

/// The total vertical room a group heading claims, split 60/40 above and below.
const _headerSpace = NexSpacing.lg;

/// Reveals the existing lazy sliver from its leading edge. Its cards keep
/// their own size and state as only the visible extent of the group changes.
class _GroupReveal extends SingleChildRenderObjectWidget {
  const _GroupReveal({
    super.key,
    required this.progress,
    required Widget sliver,
  }) : super(child: sliver);

  final Animation<double> progress;

  @override
  _RenderGroupReveal createRenderObject(BuildContext context) =>
      _RenderGroupReveal(progress);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGroupReveal renderObject,
  ) {
    renderObject.progress = progress;
  }
}

class _RenderGroupReveal extends RenderProxySliver {
  _RenderGroupReveal(this._progress);

  Animation<double> _progress;

  set progress(Animation<double> progress) {
    if (identical(_progress, progress)) return;
    if (attached) _progress.removeListener(markNeedsLayout);
    _progress = progress;
    if (attached) _progress.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void performLayout() {
    final progress = _progress.value;
    if (progress == 1) {
      super.performLayout();
      return;
    }
    // Limit the reveal to the viewport so it stays lazy for long groups.
    final budget = constraints.scrollOffset + constraints.remainingPaintExtent;
    final end = budget * progress;
    // The cache scales with the paint, but against its own full reach, so it
    // arrives complete at the same moment the paint does. The rows a fold
    // is about to uncover are then built a little ahead of the edge that
    // uncovers them, spread across the animation — instead of all at once
    // in the frame the reveal hands back to the viewport's own layout,
    // which was the most expensive frame of an open.
    final cache =
        (constraints.scrollOffset + constraints.remainingCacheExtent) *
        progress;
    child!.layout(
      constraints.copyWith(
        remainingPaintExtent: calculatePaintOffset(
          constraints,
          from: 0,
          to: end,
        ),
        remainingCacheExtent: calculateCacheOffset(
          constraints,
          from: 0,
          to: cache,
        ),
      ),
      parentUsesSize: true,
    );
    final childGeometry = child!.geometry!;
    if (childGeometry.scrollOffsetCorrection case final correction?) {
      geometry = SliverGeometry(scrollOffsetCorrection: correction);
      return;
    }
    final extent = math.min(childGeometry.scrollExtent, budget) * progress;
    final paint = calculatePaintOffset(constraints, from: 0, to: extent);
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: math.min(paint, childGeometry.paintExtent),
      maxPaintExtent: extent,
      // What the child actually covers, cache included, so the group below
      // is not asked to fill space this one has already built into.
      cacheExtent: childGeometry.cacheExtent,
      hasVisualOverflow: true,
    );
  }

  // Timeline groups are vertical. Clipping the trailing edge leaves the
  // cards' own layout alone and bounds both painting and their semantics.
  Rect get _clip =>
      Rect.fromLTWH(0, 0, constraints.crossAxisExtent, geometry!.paintExtent);

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _progress.value == 1 ? null : _clip;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_progress.value == 1) {
      layer = null;
      super.paint(context, offset);
    } else {
      layer = context.pushClipRect(
        needsCompositing,
        offset,
        _clip,
        super.paint,
        oldLayer: layer as ClipRectLayer?,
      );
    }
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
    this.picking = false,
    this.compact = false,
    this.leading,
    this.alwaysCount = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  /// A shelf's mark before its name (2.7.0): the kind's icon in its colour,
  /// or the tag's own dot.
  final Widget? leading;

  /// A shelf names its count open as well as folded: it shows its newest few
  /// of more, and the number is how many more.
  final bool alwaysCount;

  /// A shelf's place among the others, a step at a time. Null for a day, or
  /// at the end it cannot move past.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// The desktop's: a small label, the count always, no side gutter.
  final bool compact;

  final String label;
  final int count;
  final bool collapsed;
  final bool picking;
  final VoidCallback onToggle;

  /// Null when there is no provider to answer — a menu entry that can only
  /// say "unavailable" is worse than one that is not there.
  final VoidCallback? onAsk;

  /// Null when the heading's notes are not all on screen — see
  /// [_NoteGroup.complete].
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final hasMenu =
        onAsk != null ||
        onDelete != null ||
        onMoveUp != null ||
        onMoveDown != null;
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
                padding: compact
                    ? const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 8)
                    : EdgeInsetsDirectional.fromSTEB(
                        NexSpacing.md,
                        _headerSpace * 0.6,
                        hasMenu ? 0 : NexSpacing.md,
                        _headerSpace * 0.4,
                      ),
                child: Row(
                  children: [
                    // The name and its count together, the chevron at the
                    // far end. The name's Flexible used to share the row's
                    // spare room with a Spacer, half each, which left every
                    // chevron at a different place along the row (2.7.1).
                    Expanded(
                      child: Row(
                        children: [
                          if (leading case final mark?) ...[
                            mark,
                            const SizedBox(width: NexSpacing.sm),
                          ],
                          // A day's name in the page's own ink, a step up from
                          // the small grey label it was: the headings are how a
                          // long timeline is read, and they were the faintest
                          // thing on it.
                          Flexible(
                            child: Text(
                              compact && !persian ? label.toUpperCase() : label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: compact
                                  // The desktop's: small, quiet, in capitals where
                                  // the script has them (letter-spacing would pull
                                  // Persian apart). At the theme's own caption floor —
                                  // nothing in the app is smaller (V-18).
                                  ? theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 12,
                                      letterSpacing: persian ? 0 : 0.8,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    )
                                  : theme.textTheme.titleSmall?.copyWith(
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                            ),
                          ),
                          const SizedBox(width: NexSpacing.sm),
                          // Only when folded. Open, the count is the list itself, and a
                          // number beside a heading you can already read is noise.
                          if (collapsed || compact || alwaysCount)
                            Text(
                              l10n.timelineGroupCount(count),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      // Folded, the chevron points along the line of
                      // reading: right in English, left in Persian.
                      turns: collapsed
                          ? (Directionality.of(context) == TextDirection.rtl
                                ? 0.25
                                : -0.25)
                          : 0,
                      duration: NexMotion.of(context, NexMotion.standard),
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
        if (hasMenu)
          Padding(
            // The same vertical padding the heading carries, so the two glyphs
            // sit on one line. Without it the menu centred itself in the row's
            // full height while the chevron sat inside the heading's 60/40
            // weighting, and the pair read as very slightly crooked — which is
            // the kind of thing you see before you can say what it is.
            padding: compact
                ? const EdgeInsetsDirectional.only(top: 4)
                : const EdgeInsetsDirectional.fromSTEB(
                    NexSpacing.xs,
                    _headerSpace * 0.6,
                    NexSpacing.md,
                    _headerSpace * 0.4,
                  ),
            // The menu and its tap target set the heading's size. Keep that
            // space when picking so the heading and chevron stay in place.
            child: Visibility(
              visible: !picking,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: NexPopupMenuButton<_GroupAction>(
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
                onSelected: (action) => switch (action) {
                  _GroupAction.ask => onAsk?.call(),
                  _GroupAction.delete => onDelete?.call(),
                  _GroupAction.moveUp => onMoveUp?.call(),
                  _GroupAction.moveDown => onMoveDown?.call(),
                },
                itemBuilder: (context) => [
                  if (onMoveUp != null)
                    nexMenuItem(
                      value: _GroupAction.moveUp,
                      icon: Icons.arrow_upward_rounded,
                      label: l10n.groupMoveUp,
                    ),
                  if (onMoveDown != null)
                    nexMenuItem(
                      value: _GroupAction.moveDown,
                      icon: Icons.arrow_downward_rounded,
                      label: l10n.groupMoveDown,
                    ),
                  if (onAsk != null)
                    nexMenuItem(
                      value: _GroupAction.ask,
                      icon: Icons.auto_awesome_outlined,
                      label: l10n.groupAsk,
                    ),
                  if (onDelete != null)
                    nexMenuItem(
                      value: _GroupAction.delete,
                      icon: Icons.delete_outline,
                      label: l10n.groupDelete,
                      destructive: true,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// What a date heading's menu can do to the whole run under it.
enum _GroupAction { moveUp, moveDown, ask, delete }

/// A fold invalidates its own heading and reveal, keeping the body widget
/// and its mounted cards by identity. A new screen build supplies fresh
/// builders for changes such as selection, locale, and note edits.
class _GroupSliver extends StatefulWidget {
  const _GroupSliver({
    super.key,
    required this.screen,
    required this.group,
    required this.folds,
    required this.heading,
    required this.body,
    this.tail,
  });

  /// The screen these groups belong to, for its fold state and its reveal.
  final TimelineScreenState screen;

  /// The group this sliver shows.
  final _NoteGroup group;

  /// The screen's [_GroupSliver]s all listen here; see
  /// [TimelineScreenState._groupFoldPulse].
  final Listenable folds;

  /// The group's heading, rebuilt when the group moves. Cheap by design: a
  /// chevron, a name, a count.
  final Widget Function() heading;

  /// The group's body — the list or grid under the heading. Built once per
  /// screen rebuild, and kept by identity across folds.
  final Widget Function() body;

  /// A sliver that follows the body whatever the fold, for the desktop's
  /// breathing room.
  final Widget? tail;

  @override
  State<_GroupSliver> createState() => _GroupSliverState();
}

class _GroupSliverState extends State<_GroupSliver> {
  Widget? _body;
  bool _wasCollapsed = false;
  bool _wasMoving = false;

  @override
  void initState() {
    super.initState();
    widget.folds.addListener(_moved);
  }

  @override
  void didUpdateWidget(_GroupSliver old) {
    super.didUpdateWidget(old);
    if (widget.folds != old.folds) {
      old.folds.removeListener(_moved);
      widget.folds.addListener(_moved);
    }
    _body = null;
  }

  @override
  void dispose() {
    widget.folds.removeListener(_moved);
    super.dispose();
  }

  /// Another group may have moved; this one rebuilds only if its own fold
  /// state did.
  void _moved() {
    final screen = widget.screen;
    final collapsed = screen._model.collapsedGroups.contains(widget.group.key);
    final moving = screen._groupFolds.containsKey(widget.group.key);
    if (collapsed == _wasCollapsed && moving == _wasMoving) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final screen = widget.screen;
    final group = widget.group;
    final collapsed = screen._model.collapsedGroups.contains(group.key);
    final moving = screen._groupFolds.containsKey(group.key);
    _wasCollapsed = collapsed;
    _wasMoving = moving;
    if (!collapsed || moving) {
      // A group opening builds its body for the reveal to uncover; a group
      // closing keeps the one it has, so its cards are never rebuilt for the
      // fold that is folding them.
      _body ??= widget.body();
    } else {
      _body = null;
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: widget.heading()),
        if (_body case final body?) screen._groupBody(group, body),
        ?widget.tail,
      ],
    );
  }
}

/// The list holds still while two fingers are on it (2.7.1).
///
/// A pinch folds or opens every heading; it used to scroll the list too —
/// one finger of a pinch is a drag to the scroll view — so the headings moved
/// away under the fingers that were folding them, and the fling at the end
/// threw the list somewhere else. While [holding], a drag moves nothing and
/// the release flings nothing; the overscroll still settles back.
class _PinchHoldPhysics extends ScrollPhysics {
  const _PinchHoldPhysics({required this.holding, super.parent});

  final bool Function() holding;

  @override
  _PinchHoldPhysics applyTo(ScrollPhysics? ancestor) =>
      _PinchHoldPhysics(holding: holding, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      holding() ? 0 : super.applyPhysicsToUserOffset(position, offset);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => super.createBallisticSimulation(position, holding() ? 0 : velocity);
}
