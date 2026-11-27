import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Horizontal arrow keys that move where the eye moves.
///
/// Flutter moves the caret in *logical* order: the right arrow always moves
/// to the next character in the string, whichever way the characters are
/// drawn. That is correct for a left-to-right paragraph and backwards for a
/// right-to-left one: in «سلام» the next character is drawn to the left, so
/// the arrow labelled right moved the caret left, and the arrow labelled left
/// moved it right. Every platform's own text view moves by what is seen
/// instead, and so does this.
///
/// The movement is decided by the **laid-out caret geometry**, not by a guess
/// from the script. [RenderEditable.getLocalRectForCaret] says where each
/// candidate sits on screen, and [RenderEditable.getPositionForPoint] answers
/// which character is under a point — the same machinery selection handles
/// use. So a Persian paragraph, an English one, and an English word inside a
/// Persian sentence all move correctly, including the two visual positions a
/// caret can have where a right-to-left run meets a left-to-right one.
///
/// This is the part of AppFlowy's arrow-key handling that is worth having —
/// arrows follow reading direction — done from the framework's own layout
/// rather than from a per-block direction, which cannot see a run inside a
/// paragraph.
///
/// The framework still owns everything else about the keys: word and line
/// movement, vertical movement and every platform shortcut. Only the
/// one-character horizontal move — with Shift held or not — is handled here,
/// and only while the field itself holds the focus.
///
/// At the edge of a line there is no caret to the left or right to move to,
/// so the framework's own intent runs instead and crosses the line the way it
/// always has. Shift is the same move with the selection's other end held.
class NexVisualCaretKeys extends StatelessWidget {
  const NexVisualCaretKeys({super.key, required this.child});

  final Widget child;

  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): NexVisualCaretIntent(
          forward: false,
          expand: false,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): NexVisualCaretIntent(
          forward: true,
          expand: false,
        ),
        SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            NexVisualCaretIntent(forward: false, expand: true),
        SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            NexVisualCaretIntent(forward: true, expand: true),
      };

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: _shortcuts,
    child: Actions(
      actions: <Type, Action<Intent>>{
        NexVisualCaretIntent: NexVisualCaretAction(),
      },
      child: child,
    ),
  );
}

/// A horizontal caret move toward the visual right or left.
@immutable
class NexVisualCaretIntent extends Intent {
  const NexVisualCaretIntent({required this.forward, required this.expand});

  /// Toward the right edge of the screen, not toward the end of the string.
  final bool forward;

  /// Keep the selection's anchor where it is and move its other end.
  final bool expand;
}

/// Moves the focused editor's caret by [nexVisualCaretTarget].
///
/// The field's own `EditableTextState` is found from the primary focus, which
/// is inside the field this widget wraps. Nothing is rebuilt and the keyboard
/// is not touched: the same editor keeps its focus and only its selection
/// moves, so a key repeat cannot make the field blink.
class NexVisualCaretAction extends Action<NexVisualCaretIntent> {
  @override
  Object? invoke(NexVisualCaretIntent intent) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null || !focusContext.mounted) return null;
    final state = focusContext.findAncestorStateOfType<EditableTextState>();
    if (state == null) return null;
    final editable = state.renderEditable;
    if (!editable.attached || !editable.hasSize) return null;
    final value = state.textEditingValue;
    final selection = value.selection;
    if (!selection.isValid || !state.widget.selectionEnabled) return null;

    // A plain arrow over a selection collapses it to the side the arrow
    // points at. Flutter collapses to the logical end, which in a
    // right-to-left paragraph is the *left* end of the selection — the
    // opposite side from the key that was pressed.
    if (!intent.expand && !selection.isCollapsed) {
      final edge = _visualSelectionEdge(
        editable,
        selection,
        forward: intent.forward,
      );
      if (edge != null) {
        _write(state, value, TextSelection.fromPosition(edge));
        return null;
      }
      // A selection that spans visual lines has no one side of the screen to
      // collapse toward: its start and end can both be on the right of one
      // line and the left of another. Collapse by reading order instead —
      // the framework's own collapse — with the visible direction mapped to
      // the logical one for this field's base direction.
      return Actions.maybeInvoke(
        focusContext,
        ExtendSelectionByCharacterIntent(
          forward: _logicalForward(state, intent.forward),
          collapseSelection: true,
        ),
      );
    }

    final target = nexVisualCaretTarget(
      editable,
      selection.extent,
      forward: intent.forward,
    );
    if (target == null) {
      // The line has no character in that direction. Let the framework
      // cross the line boundary, in the logical direction the visible one
      // means for a paragraph laid out this way.
      return Actions.maybeInvoke(
        focusContext,
        ExtendSelectionByCharacterIntent(
          forward: _logicalForward(state, intent.forward),
          collapseSelection: !intent.expand,
        ),
      );
    }
    _write(
      state,
      value,
      intent.expand
          ? selection.extendTo(target)
          : TextSelection.fromPosition(target),
    );
    return null;
  }

  void _write(
    EditableTextState state,
    TextEditingValue value,
    TextSelection selection,
  ) {
    state.userUpdateTextEditingValue(
      value.copyWith(selection: selection),
      SelectionChangedCause.keyboard,
    );
  }

  /// The logical direction a visible move means for this field.
  ///
  /// Only used where the visible move has nowhere to go — the edge of a line
  /// — so the framework's own line crossing continues in reading order.
  bool _logicalForward(EditableTextState state, bool visualForward) {
    final rightToLeft = state.renderEditable.textDirection == TextDirection.rtl;
    return rightToLeft ? !visualForward : visualForward;
  }
}

/// The caret position one character to the visual right (or left) of [from].
///
/// Null when there is no caret on that side of the line: the edge of a
/// paragraph, an empty line, or a selection that ends there.
///
/// The answer comes from the laid-out text, so it is right for a right-to-left
/// paragraph, a left-to-right one, and every boundary between them. A caret
/// at the join of two directions has two visual positions; the one nearest
/// the move is chosen, which is the one the person sees the caret at.
///
/// A move stays on the line it started on. At a soft wrap the same logical
/// offset has a caret at the end of one line and at the start of the next, and
/// a horizontal move that took the farther one would jump a line without the
/// person asking. When there is no caret on this line in that direction, the
/// line's edge has been reached and the framework crosses it.
@visibleForTesting
TextPosition? nexVisualCaretTarget(
  RenderEditable editable,
  TextPosition from, {
  required bool forward,
}) {
  final current = editable.getLocalRectForCaret(from);
  final y = current.center.dy;
  final originX = current.left;
  final direction = forward ? 1.0 : -1.0;
  // A glyph is narrower than this even at the largest text scale; the bound
  // only stops a search that found nothing from walking the whole line.
  final limit = math.max(48.0, current.height * 2);
  for (var distance = 1.0; distance <= limit; distance += 1.0) {
    final probe = editable.localToGlobal(
      Offset(originX + direction * distance, y),
    );
    final found = editable.getPositionForPoint(probe);
    if (found.offset == from.offset) continue;
    final target = _nearestCaret(
      editable,
      found.offset,
      originX: originX,
      line: current,
      forward: forward,
    );
    if (target != null) return target;
  }
  return null;
}

/// [offset] with the affinity that puts its caret nearest [originX], on the
/// side the move is going and on [line]. Null when neither affinity qualifies.
///
/// Both affinities matter only where directions or lines meet. A logical
/// boundary there has two places on screen — one at each end of the run, or
/// one at the end of a wrapped line and one at the start of the next — and
/// the person means the one the move is heading toward, on the line they are
/// already on.
TextPosition? _nearestCaret(
  RenderEditable editable,
  int offset, {
  required double originX,
  required Rect line,
  required bool forward,
}) {
  final downstream = editable.getLocalRectForCaret(
    TextPosition(offset: offset),
  );
  final upstream = editable.getLocalRectForCaret(
    TextPosition(offset: offset, affinity: TextAffinity.upstream),
  );
  bool onTheWay(double x) =>
      forward ? x > originX + _epsilon : x < originX - _epsilon;
  final candidates = <({double x, TextPosition position})>[
    if (onTheWay(downstream.left) && _sameLine(line, downstream))
      (x: downstream.left, position: TextPosition(offset: offset)),
    if (onTheWay(upstream.left) && _sameLine(line, upstream))
      (
        x: upstream.left,
        position: TextPosition(offset: offset, affinity: TextAffinity.upstream),
      ),
  ];
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => forward ? a.x.compareTo(b.x) : b.x.compareTo(a.x));
  return candidates.first.position;
}

/// Whether [a] and [b] are drawn on the same visual line.
///
/// Caret rectangles are as tall as their line. The centres of two different
/// lines are at least half a line apart, so half the taller rectangle plus a
/// pixel for rounding is a bound the next line cannot fit inside.
bool _sameLine(Rect a, Rect b) {
  final tolerance = math.max(a.height, b.height) / 2 + 1.0;
  return (a.center.dy - b.center.dy).abs() <= tolerance;
}

const double _epsilon = 0.5;

/// The end of [selection] on the side [forward] points at, or null when the
/// selection spans visual lines and has no one side to collapse toward.
TextPosition? _visualSelectionEdge(
  RenderEditable editable,
  TextSelection selection, {
  required bool forward,
}) {
  ({double x, Rect rect, TextPosition position}) edge(int offset) {
    final downstream = editable.getLocalRectForCaret(
      TextPosition(offset: offset),
    );
    final upstream = editable.getLocalRectForCaret(
      TextPosition(offset: offset, affinity: TextAffinity.upstream),
    );
    final downstreamWins = forward
        ? downstream.left >= upstream.left
        : downstream.left <= upstream.left;
    return downstreamWins
        ? (
            x: downstream.left,
            rect: downstream,
            position: TextPosition(offset: offset),
          )
        : (
            x: upstream.left,
            rect: upstream,
            position: TextPosition(
              offset: offset,
              affinity: TextAffinity.upstream,
            ),
          );
  }

  final start = edge(selection.start);
  final end = edge(selection.end);
  // X alone is not a side of the screen when the selection spans lines: a
  // start near the right edge of line one can be to the right of an end at
  // the left edge of line two, and the arrow would collapse to the wrong one.
  if (!_sameLine(start.rect, end.rect)) return null;
  return forward
      ? (start.x >= end.x ? start.position : end.position)
      : (start.x <= end.x ? start.position : end.position);
}
