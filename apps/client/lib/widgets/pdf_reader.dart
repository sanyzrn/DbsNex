import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/pdf_preview.dart';

/// A complete document, one bounded page at a time, inside the note sheet.
/// The viewer owns only the current page; changing page releases its decoded
/// image too, instead of filling Flutter's global image cache with a document.
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
    _count = 0;
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
  }

  Future<void> _load(int index) async {
    final generation = ++_generation;
    setState(() {
      _index = index;
      _scrub = null;
      _loading = true;
      _forgetPage();
    });
    _transform.value = Matrix4.identity();
    final page = await NexPdfPreview.page(widget.path, index: index);
    if (!mounted || generation != _generation) return;
    setState(() {
      _page = page;
      if (page != null) _count = page.pageCount;
      _loading = false;
    });
  }

  @override
  void dispose() {
    ++_generation;
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
            if (_loading)
              const SizedBox(
                height: 240,
                child: Center(child: NexSkeleton(height: 16)),
              )
            else if (page == null)
              Padding(
                padding: const EdgeInsets.all(NexSpacing.md),
                child: Column(
                  children: [
                    Text(
                      l10n.inlineMediaUnavailable,
                      style: theme.textTheme.bodyMedium,
                    ),
                    TextButton.icon(
                      onPressed: () => unawaited(_load(_index)),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * 0.55).clamp(
                  240.0,
                  600.0,
                ),
                child: ClipRect(
                  child: InteractiveViewer(
                    key: ValueKey('pdf-page-$_index'),
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: 4,
                    panEnabled: _zoomed,
                    child: Center(
                      child: Image.memory(
                        page.bytes,
                        fit: BoxFit.contain,
                        semanticLabel: pageLabel,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => Padding(
                          padding: const EdgeInsets.all(NexSpacing.md),
                          child: Text(l10n.inlineMediaUnavailable),
                        ),
                      ),
                    ),
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
                      onPressed: _loading || _index == 0
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
                      onPressed: _loading || _index + 1 >= _count
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
                    label: pageLabel,
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
                    onChanged: _loading
                        ? null
                        : (value) => setState(() => _scrub = value),
                    onChangeEnd: _loading
                        ? null
                        : (value) => unawaited(_load(value.round() - 1)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
