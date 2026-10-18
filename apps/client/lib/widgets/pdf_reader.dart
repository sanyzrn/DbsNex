import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/pdf_preview.dart';
import 'nex_dialog.dart';

/// A complete document, one bounded page at a time, inside the note sheet.
/// The current page stays visible until its replacement is decoded. Only the
/// current and outgoing page are retained during the short transition.
///
/// Pages turn by swiping, the way every reader turns them (2.1.6), and by the
/// two arrows in the capsule over the bottom of the page. The capsule's
/// count opens a sheet of page numbers to jump to. It replaced a slider under
/// the page, which cost the card a row of its own, was hard to land on one
/// page out of many with a thumb, and put the thing you touch to move through
/// the document somewhere other than the document.
class NexPdfReader extends StatefulWidget {
  const NexPdfReader({super.key, required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  State<NexPdfReader> createState() => _NexPdfReaderState();
}

class _NexPdfReaderState extends State<NexPdfReader>
    with SingleTickerProviderStateMixin {
  NexPdfPage? _page;
  int _index = 0;
  int _count = 0;
  int _generation = 0;
  bool _loading = true;
  bool _failed = false;
  bool _turning = false;
  int _requestedIndex = 0;
  bool _forward = true;
  Timer? _turnEnd;
  final _retired = <MemoryImage>{};
  bool _zoomed = false;
  final _transform = TransformationController();

  /// Where the page has been dragged to, in pixels along the reading
  /// direction. Unbounded, so it can follow the finger and spring back.
  late final AnimationController _drag;
  Offset _doubleTapAt = Offset.zero;

  /// One page asked for ahead of time: the one a swipe is heading to, or the
  /// next one in the direction somebody is reading. The rendered bytes only —
  /// decoding still waits for the turn — so it costs one compressed page.
  /// Nothing is asked ahead on opening: a document that is only glanced at
  /// renders one page and no more.
  int? _aheadIndex;
  Future<NexPdfPage?>? _ahead;

  @override
  void initState() {
    super.initState();
    _drag = AnimationController.unbounded(vsync: this);
    _transform.addListener(_onZoom);
    unawaited(_load(0));
  }

  @override
  void didUpdateWidget(NexPdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path) return;
    _turnEnd?.cancel();
    _turning = false;
    _forgetPage();
    _count = 0;
    _index = 0;
    _aheadIndex = null;
    _ahead = null;
    unawaited(_load(0));
  }

  void _onZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
  }

  void _forgetPage() {
    final page = _page;
    _page = null;
    if (page != null) unawaited(MemoryImage(page.bytes).evict());
    for (final image in _retired) {
      unawaited(image.evict());
    }
    _retired.clear();
  }

  void _prefetch(int index) {
    if (index < 0 || index >= _count || index == _index) return;
    if (_aheadIndex == index) return;
    _aheadIndex = index;
    _ahead = NexPdfPreview.page(widget.path, index: index);
  }

  bool get _busy => _loading || _turning;

  Future<void> _load(int index) async {
    final generation = ++_generation;
    setState(() {
      _requestedIndex = index;
      _loading = true;
      _failed = false;
    });
    final ahead = _aheadIndex == index ? _ahead : null;
    _aheadIndex = null;
    _ahead = null;
    var page = await (ahead ?? NexPdfPreview.page(widget.path, index: index));
    if (!mounted || generation != _generation) return;
    if (page != null) {
      var decoded = true;
      await precacheImage(
        MemoryImage(page.bytes),
        context,
        onError: (_, __) => decoded = false,
      );
      if (!mounted || generation != _generation) {
        unawaited(MemoryImage(page.bytes).evict());
        return;
      }
      if (!decoded) {
        unawaited(MemoryImage(page.bytes).evict());
        page = null;
      }
    }
    final previous = _page;
    final duration = NexMotion.of(context, NexMotion.standard);
    setState(() {
      _loading = false;
      _failed = page == null;
      if (page != null) {
        _forward = index >= _index;
        _index = index;
        _page = page;
        _count = page.pageCount;
        _turning = previous != null && duration > Duration.zero;
      }
    });
    if (page != null) {
      _transform.value = Matrix4.identity();
      if (previous != null) {
        // Somebody is reading through: the next page that way is likely next.
        _prefetch(_forward ? index + 1 : index - 1);
        _turnEnd?.cancel();
        final retired = MemoryImage(previous.bytes);
        _retired.add(retired);
        _turnEnd = Timer(duration, () {
          // The old Image keeps its stream until the switch finishes.
          _retired.remove(retired);
          unawaited(retired.evict());
          if (mounted) setState(() => _turning = false);
        });
      }
    }
  }

  void _turn(int delta) {
    final target = _index + delta;
    if (_busy || target < 0 || target >= _count) return;
    unawaited(_load(target));
  }

  /// +1 when a drag of [dx] pixels is heading for the next page. The next
  /// page lies the way the interface reads, as in every swiping list in the
  /// app: to the right in English, so the finger moves left; to the left in
  /// Persian.
  int _towards(double dx) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return (dx < 0) != rtl ? 1 : -1;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    final next = _drag.value + delta;
    final target = _index + _towards(next);
    final open = target >= 0 && target < _count;
    if (open) _prefetch(target);
    // Past the first or the last page the page still moves, a little, so the
    // swipe is answered and the end of the document is felt rather than
    // guessed at.
    _drag.value = open ? next : _drag.value + delta * 0.25;
  }

  void _onDragEnd(DragEndDetails details) {
    final width = context.size?.width ?? 320;
    final velocity = details.primaryVelocity ?? 0;
    final dx = _drag.value;
    final flung = velocity.abs() > 600 && velocity.sign == dx.sign;
    if (dx != 0 && (dx.abs() > width * 0.22 || flung)) _turn(_towards(dx));
    unawaited(
      _drag.animateTo(
        0,
        duration: NexMotion.of(context, NexMotion.standard),
        curve: NexMotion.curve,
      ),
    );
  }

  void _toggleZoom([Offset? at]) {
    if (_page == null) return;
    if (_zoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    // Twice the size, around the point that was tapped: that point stays
    // under the finger. The button zooms around the middle of the page.
    final focus =
        at ??
        Offset((context.size?.width ?? 0) / 2, _viewportHeight(context) / 2);
    _transform.value = Matrix4.diagonal3Values(2, 2, 1)
      ..setTranslationRaw(-focus.dx, -focus.dy, 0);
  }

  double _viewportHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * 0.55).clamp(240.0, 600.0);

  Future<void> _pickPage() async {
    if (_count < 2 || _busy) return;
    final target = await nexShowSheet<int>(
      context: context,
      builder: (context) => _PdfPagePicker(count: _count, current: _index),
    );
    if (!mounted || target == null || target == _index) return;
    unawaited(_load(target));
  }

  @override
  void dispose() {
    ++_generation;
    _turnEnd?.cancel();
    _forgetPage();
    _transform.dispose();
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final page = _page;
    final persian = l10n.localeName == 'fa';
    final pageLabel = l10n.pdfPageCount(
      nexDigits('${_index + 1}', persian: persian),
      nexDigits('$_count', persian: persian),
    );
    final swipe = page != null && !_zoomed && _count > 1;
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Material(
        key: const ValueKey('inline-pdf'),
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf_outlined, color: scheme.primary),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: Text('PDF', style: theme.textTheme.labelLarge),
                  ),
                  IconButton(
                    tooltip: _zoomed ? l10n.resetZoom : l10n.zoomIn,
                    onPressed: page == null ? null : _toggleZoom,
                    icon: Icon(_zoomed ? Icons.zoom_out_map : Icons.zoom_in),
                  ),
                  IconButton(
                    tooltip: l10n.openInOtherApp,
                    onPressed: widget.onOpen,
                    icon: const Icon(Icons.open_in_new),
                  ),
                ],
              ),
            ),
            // Loading, success and failure share the same viewport. The
            // document and the controls over it never move between pages.
            SizedBox(
              key: const ValueKey('pdf-viewport'),
              height: _viewportHeight(context),
              child: ClipRect(
                // A shade behind the page, so a white page reads as a page
                // on a white card rather than as more card.
                child: ColoredBox(
                  color: Color.alphaBlend(
                    scheme.onSurface.withValues(alpha: 0.05),
                    scheme.surfaceContainerLow,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (page == null)
                        Center(
                          child: _loading
                              ? const NexSkeleton(height: 16)
                              : _failure(context),
                        )
                      else
                        GestureDetector(
                          key: const ValueKey('pdf-surface'),
                          // Only while the page is at its own size: zoomed in,
                          // a sideways drag is for moving around the page.
                          onHorizontalDragUpdate: swipe ? _onDragUpdate : null,
                          onHorizontalDragEnd: swipe ? _onDragEnd : null,
                          onDoubleTapDown: (details) =>
                              _doubleTapAt = details.localPosition,
                          onDoubleTap: () => _toggleZoom(_doubleTapAt),
                          child: InteractiveViewer(
                            transformationController: _transform,
                            minScale: 1,
                            maxScale: 4,
                            panEnabled: _zoomed,
                            child: AnimatedBuilder(
                              animation: _drag,
                              builder: (context, child) {
                                final width = MediaQuery.sizeOf(context).width;
                                final pulled = (_drag.value.abs() / width)
                                    .clamp(0.0, 1.0);
                                return Transform.translate(
                                  offset: Offset(_drag.value, 0),
                                  child: Opacity(
                                    opacity: 1 - pulled * 0.35,
                                    child: child,
                                  ),
                                );
                              },
                              child: SizedBox.expand(
                                child: _pageSwitcher(page, pageLabel),
                              ),
                            ),
                          ),
                        ),
                      if (_loading && page != null)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            value: MediaQuery.disableAnimationsOf(context)
                                ? 0.5
                                : null,
                          ),
                        ),
                      if (_failed && page != null)
                        Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.all(NexSpacing.sm),
                            child: Material(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(NexRadius.md),
                              child: _failure(context),
                            ),
                          ),
                        ),
                      if (_count > 0) ...[
                        Positioned(
                          left: NexSpacing.sm,
                          right: NexSpacing.sm,
                          bottom: NexSpacing.sm + 2,
                          child: Center(
                            // Fainter while zoomed in, where the part of the
                            // page it covers is what is being read — but still
                            // there: a turn resets the zoom.
                            child: AnimatedOpacity(
                              opacity: _zoomed ? 0.55 : 1,
                              duration: NexMotion.of(context, NexMotion.fast),
                              curve: NexMotion.curve,
                              child: _capsule(l10n, scheme, theme, pageLabel),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageSwitcher(NexPdfPage page, String pageLabel) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // The new page comes in from the side the swipe was heading for.
    final from = (_forward ? 0.06 : -0.06) * (rtl ? -1 : 1);
    return AnimatedSwitcher(
      duration: NexMotion.of(context, NexMotion.standard),
      switchInCurve: NexMotion.curve,
      switchOutCurve: NexMotion.curve,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [
          for (final child in previous)
            ExcludeSemantics(child: IgnorePointer(child: child)),
          if (current != null) current,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(from, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Center(
        key: ValueKey(page),
        // A hairline round the page itself — the image is sized to the page,
        // so the border is the paper's edge.
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.8),
              width: 0.5,
            ),
          ),
          child: Image.memory(
            page.bytes,
            fit: BoxFit.contain,
            semanticLabel: pageLabel,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  /// Previous, the page count, next — over the page, where the thumb already
  /// is. The count opens the page picker.
  Widget _capsule(
    AppLocalizations l10n,
    ColorScheme scheme,
    ThemeData theme,
    String pageLabel,
  ) {
    final persian = l10n.localeName == 'fa';
    // A one-page document still says so — "1 / 1" answers whether there is
    // more — but has nothing to turn to or pick from.
    final single = _count < 2;
    final count = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: single ? NexSpacing.md : NexSpacing.sm,
        vertical: single ? NexSpacing.sm : NexSpacing.xs,
      ),
      child: Text(
        l10n.pdfPageShort(
          nexDigits('${_index + 1}', persian: persian),
          nexDigits('$_count', persian: persian),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.94),
      shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: single
          ? Semantics(label: pageLabel, excludeSemantics: true, child: count)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('pdf-previous'),
                  tooltip: l10n.previousPdfPage,
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy || _index == 0 ? null : () => _turn(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Flexible(
                  child: Tooltip(
                    message: l10n.pdfGoToPage,
                    child: InkWell(
                      key: const ValueKey('pdf-page-counter'),
                      customBorder: const StadiumBorder(),
                      onTap: _busy ? null : _pickPage,
                      child: Semantics(
                        button: true,
                        label: pageLabel,
                        hint: l10n.pdfGoToPage,
                        excludeSemantics: true,
                        child: count,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('pdf-next'),
                  tooltip: l10n.nextPdfPage,
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy || _index + 1 >= _count
                      ? null
                      : () => _turn(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
    );
  }

  Widget _failure(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.inlineMediaUnavailable,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          TextButton.icon(
            onPressed: () => unawaited(_load(_requestedIndex)),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ],
      ),
    );
  }
}

/// Every page number, the open one marked, for jumping straight to a page.
///
/// Numbers rather than thumbnails: a thumbnail is a page rendered, and
/// rendering a hundred of them to show a sheet is the cost this reader is
/// built to avoid. Built lazily and opened scrolled to the current page.
class _PdfPagePicker extends StatefulWidget {
  const _PdfPagePicker({required this.count, required this.current});

  final int count;
  final int current;

  @override
  State<_PdfPagePicker> createState() => _PdfPagePickerState();
}

class _PdfPagePickerState extends State<_PdfPagePicker> {
  static const _cell = 56.0;
  static const _gap = NexSpacing.sm;
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.lg,
        NexSpacing.md,
        NexSpacing.lg,
        NexSpacing.lg,
      ),
      child: Column(
        key: const ValueKey('pdf-page-picker'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.pdfGoToPage, style: theme.textTheme.titleMedium),
          const SizedBox(height: NexSpacing.xs),
          Text(
            l10n.pdfPageCount(
              nexDigits('${widget.current + 1}', persian: persian),
              nexDigits('${widget.count}', persian: persian),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = ((constraints.maxWidth + _gap) / (_cell + _gap))
                  .floor()
                  .clamp(1, 12);
              final rows = (widget.count / columns).ceil();
              final rowExtent = _cell + _gap;
              final height = (rows * rowExtent - _gap).clamp(_cell, maxHeight);
              final row = widget.current ~/ columns;
              _scroll ??= ScrollController(
                initialScrollOffset: ((row - 1) * rowExtent).clamp(
                  0.0,
                  (rows * rowExtent - _gap - height).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
              );
              return SizedBox(
                height: height,
                child: GridView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: _gap,
                    crossAxisSpacing: _gap,
                    mainAxisExtent: _cell,
                  ),
                  itemCount: widget.count,
                  itemBuilder: (context, index) {
                    final open = index == widget.current;
                    return Material(
                      key: ValueKey('pdf-page-${index + 1}'),
                      color: open
                          ? scheme.primary
                          : scheme.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(NexRadius.md),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(index),
                        child: Semantics(
                          button: true,
                          selected: open,
                          label: l10n.pdfPageCount(
                            nexDigits('${index + 1}', persian: persian),
                            nexDigits('${widget.count}', persian: persian),
                          ),
                          excludeSemantics: true,
                          child: Center(
                            child: Text(
                              nexDigits('${index + 1}', persian: persian),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: open
                                    ? scheme.onPrimary
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
