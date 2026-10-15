import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../tokens/nex_contrast.dart';
import '../tokens/nex_text_direction.dart';
import 'nex_selectable_lines.dart';
import 'nex_selection_menu.dart';

/// The URL and where its hold menu should open.
typedef NexLinkHold = void Function(String href, Offset globalPosition);

/// Both gestures on the same inline span. The platform's recognizers compete
/// normally: scrolling cancels them; a hold wins over text selection on this
/// link alone and cannot also fire a tap when the finger lifts.
class NexLinkGestureRecognizer extends TapGestureRecognizer {
  NexLinkGestureRecognizer() : _hold = LongPressGestureRecognizer();

  final LongPressGestureRecognizer _hold;

  void configure(VoidCallback? open, GestureLongPressStartCallback? hold) {
    onTap = open;
    _hold.onLongPressStart = hold;
    onSecondaryTapUp = hold == null
        ? null
        : (details) => hold(
            LongPressStartDetails(
              globalPosition: details.globalPosition,
              localPosition: details.localPosition,
            ),
          );
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _hold.gestureSettings = gestureSettings;
    // Registered at the span, before the surrounding SelectionArea.
    _hold.addPointer(event);
    super.addAllowedPointer(event);
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }
}

/// Recognizers remain valid across rebuilds and are released with their owner.
class NexLinkRecognizers {
  final _links = <String, NexLinkGestureRecognizer>{};
  ValueChanged<String>? onTap;
  NexLinkHold? onHold;

  NexLinkGestureRecognizer forHref(String href) {
    return (_links[href] ??= NexLinkGestureRecognizer())..configure(
      onTap == null ? null : () => onTap!(href),
      onHold == null
          ? null
          : (details) => onHold!(href, details.globalPosition),
    );
  }

  void dispose() {
    for (final recognizer in _links.values) {
      recognizer.dispose();
    }
    _links.clear();
  }
}

/// Plain text with web addresses made interactive. Nothing is parsed as
/// Markdown: stars, underscores, indentation and line breaks stay literal.
class NexLinkText extends StatefulWidget {
  const NexLinkText(
    this.text, {
    super.key,
    this.style,
    this.onTapLink,
    this.onHoldLink,
    this.selectable = true,
  });

  final String text;
  final TextStyle? style;
  final ValueChanged<String>? onTapLink;
  final NexLinkHold? onHoldLink;
  final bool selectable;

  @override
  State<NexLinkText> createState() => _NexLinkTextState();
}

class _NexLinkTextState extends State<NexLinkText> {
  final _recognizers = NexLinkRecognizers();

  @override
  void dispose() {
    _recognizers.dispose();
    super.dispose();
  }

  Widget _paragraph(String text) {
    final scheme = Theme.of(context).colorScheme;
    final tint = nexReadableOn(scheme.primary, scheme.surface);
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final link in nexTextLinks(text)) {
      if (link.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, link.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(link.start, link.end),
          style: TextStyle(color: tint, decoration: TextDecoration.underline),
          recognizer: _recognizers.forHref(link.url),
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      cursor = link.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    final direction = nexDirectionOf(text);
    return NexTextDirection(
      text: text,
      child: SizedBox(
        width: double.infinity,
        child: Text.rich(
          TextSpan(
            children: spans.isEmpty ? [const TextSpan(text: '\u200B')] : spans,
          ),
          style: widget.style ?? Theme.of(context).textTheme.bodyLarge,
          textDirection: direction,
          textAlign: direction == TextDirection.rtl
              ? TextAlign.right
              : TextAlign.start,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _recognizers
      ..onTap = widget.onTapLink
      ..onHold = widget.onHoldLink;
    if (nexTextLinks(widget.text).isEmpty) {
      return NexTextSurface(
        widget.text,
        style: widget.style,
        selectable: widget.selectable,
      );
    }
    final lines = widget.text.split('\n');
    final directions = lines
        .map(nexDirectionOf)
        .whereType<TextDirection>()
        .toSet();
    final body = directions.length <= 1
        ? _paragraph(widget.text)
        : NexSelectableLines(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final line in lines) _paragraph(line)],
            ),
          );
    return widget.selectable ? NexSelectionArea(child: body) : body;
  }
}
