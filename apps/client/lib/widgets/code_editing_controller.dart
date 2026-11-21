import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

typedef _HighlightRequest = ({
  String source,
  NexCodeLanguage language,
  ColorScheme scheme,
});

List<TextSpan> _highlight(_HighlightRequest request) => nexHighlightCode(
  request.source,
  request.language,
  style: const TextStyle(),
  scheme: request.scheme,
);

/// Draws syntax in the field while keeping its text and selection unmodified.
class NexCodeEditingController extends TextEditingController {
  NexCodeEditingController({required String text, required this.language})
    : super(text: text);

  NexCodeLanguage language;
  _HighlightRequest? _requested;
  _HighlightRequest? _cached;
  List<TextSpan> _spans = const [];
  Timer? _debounce;
  bool _running = false;
  bool _disposed = false;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (language == NexCodeLanguage.plainText || text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final request = (
      source: text,
      language: language,
      scheme: Theme.of(context).colorScheme,
    );
    if (request != _requested) {
      _requested = request;
      _debounce?.cancel();
      if (request.source.length <= 4000) {
        _spans = _highlight(request);
        _cached = request;
      } else if (_cached != request && !_running) {
        _debounce = Timer(const Duration(milliseconds: 90), _runHighlight);
      }
    }
    if (_cached != request) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    // Retain the keyboard's composing underline over the syntax colours.
    final composing = value.composing;
    if (!withComposing ||
        !value.isComposingRangeValid ||
        composing.isCollapsed) {
      return TextSpan(style: style, children: _spans);
    }
    var start = 0;
    final styled = <TextSpan>[];
    for (final span in _spans) {
      final piece = span.text!;
      final end = start + piece.length;
      if (end <= composing.start || start >= composing.end) {
        styled.add(span);
      } else {
        final from = (composing.start - start).clamp(0, piece.length);
        final to = (composing.end - start).clamp(from, piece.length);
        if (from > 0) {
          styled.add(
            TextSpan(text: piece.substring(0, from), style: span.style),
          );
        }
        styled.add(
          TextSpan(
            text: piece.substring(from, to),
            style: (span.style ?? const TextStyle()).copyWith(
              decoration: TextDecoration.underline,
            ),
          ),
        );
        if (to < piece.length) {
          styled.add(TextSpan(text: piece.substring(to), style: span.style));
        }
      }
      start = end;
    }
    return TextSpan(style: style, children: styled);
  }

  Future<void> _runHighlight() async {
    final request = _requested;
    if (request == null || _cached == request) return;
    _running = true;
    List<TextSpan> result;
    try {
      result = await compute(_highlight, request);
    } catch (_) {
      result = [TextSpan(text: request.source)];
    }
    _running = false;
    if (_disposed) return;
    if (_requested == request &&
        text == request.source &&
        language == request.language) {
      _cached = request;
      _spans = result;
      notifyListeners();
    } else if (_requested != request && _requested != _cached) {
      _debounce = Timer(const Duration(milliseconds: 90), _runHighlight);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
