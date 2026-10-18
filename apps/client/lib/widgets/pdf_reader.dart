import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/pdf_preview.dart';

/// A complete document, one bounded page at a time, inside the note sheet.
/// The current page stays visible until its replacement is decoded. Only the
/// current and outgoing page are retained during the short transition.
class NexPdfReader extends StatefulWidget {
  const NexPdfReader({super.key, required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  State<NexPdfReader> createState() => _NexPdfReaderState();
}

class _NexPdfReaderState extends State<NexPdfReader> {
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
  double? _scrub;
  final _transform = TransformationController();

  @override
  void initState() {
    super.initState();
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

  Future<void> _load(int index) async {
    final generation = ++_generation;
    setState(() {
      _requestedIndex = index;
      _scrub = null;
      _loading = true;
      _failed = false;
    });
    var page = await NexPdfPreview.page(widget.path, index: index);
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

  @override
  void dispose() {
    ++_generation;
    _turnEnd?.cancel();
    _forgetPage();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final page = _page;
    final pageLabel = l10n.pdfPageCount(
      nexDigits('${_index + 1}', persian: l10n.localeName == 'fa'),
      nexDigits('$_count', persian: l10n.localeName == 'fa'),
    );
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
                    onPressed: page == null
                        ? null
                        : () {
                            _transform.value = _zoomed
                                ? Matrix4.identity()
                                : Matrix4.diagonal3Values(2, 2, 1);
                          },
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
            // document and the controls below it never collapse between pages.
            SizedBox(
              key: const ValueKey('pdf-viewport'),
              height: (MediaQuery.sizeOf(context).height * 0.55).clamp(
                240.0,
                600.0,
              ),
              child: ClipRect(
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
                      InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1,
                        maxScale: 4,
                        panEnabled: _zoomed,
                        child: SizedBox.expand(
                          child: AnimatedSwitcher(
                            duration: NexMotion.of(context, NexMotion.standard),
                            switchInCurve: NexMotion.curve,
                            switchOutCurve: NexMotion.curve,
                            layoutBuilder: (current, previous) => Stack(
                              fit: StackFit.expand,
                              children: [
                                for (final child in previous)
                                  ExcludeSemantics(
                                    child: IgnorePointer(child: child),
                                  ),
                                if (current != null) current,
                              ],
                            ),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: Offset(
                                        _forward ? 0.025 : -0.025,
                                        0,
                                      ),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: Center(
                              key: ValueKey(page),
                              child: Image.memory(
                                page.bytes,
                                fit: BoxFit.contain,
                                semanticLabel: pageLabel,
                                filterQuality: FilterQuality.medium,
                              ),
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
                        alignment: Alignment.bottomCenter,
                        child: Material(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(NexRadius.md),
                          child: _failure(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_count > 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('pdf-previous'),
                      tooltip: l10n.previousPdfPage,
                      onPressed: _loading || _turning || _index == 0
                          ? null
                          : () => unawaited(_load(_index - 1)),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        pageLabel,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('pdf-next'),
                      tooltip: l10n.nextPdfPage,
                      onPressed: _loading || _turning || _index + 1 >= _count
                          ? null
                          : () => unawaited(_load(_index + 1)),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              if (_count > 1)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Slider(
                    key: const ValueKey('pdf-page-slider'),
                    // One stop per page, so the thumb lands on a page and
                    // the bubble above it says which one while dragging —
                    // a slider label is only shown when it has divisions.
                    divisions: _count - 1,
                    label: l10n.pdfPageCount(
                      nexDigits(
                        '${(_scrub ?? (_index + 1).toDouble()).round()}',
                        persian: l10n.localeName == 'fa',
                      ),
                      nexDigits('$_count', persian: l10n.localeName == 'fa'),
                    ),
                    semanticFormatterCallback: (value) => l10n.pdfPageCount(
                      nexDigits(
                        '${value.round()}',
                        persian: l10n.localeName == 'fa',
                      ),
                      nexDigits('$_count', persian: l10n.localeName == 'fa'),
                    ),
                    min: 1,
                    max: _count.toDouble(),
                    value: _scrub ?? (_index + 1).toDouble(),
                    onChanged: _loading || _turning
                        ? null
                        : (value) => setState(() => _scrub = value),
                    onChangeEnd: _loading || _turning
                        ? null
                        : (value) {
                            final target = value.round() - 1;
                            if (target == _index) {
                              setState(() => _scrub = null);
                              return;
                            }
                            unawaited(_load(target));
                          },
                  ),
                ),
            ],
          ],
        ),
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
