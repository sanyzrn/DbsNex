import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps the line breaks when a selection spanning several text widgets is
/// copied.
///
/// A [SelectionArea] copies by joining what each selected widget holds,
/// with nothing in between. A note drawn as one [Text] is unaffected, but two
/// kinds of note are drawn as several: one that mixes Persian and English
/// lines, where each line is its own widget so each can take its own
/// direction, and anything rendered as Markdown, where each paragraph, list
/// item and heading is. Copying either and pasting it elsewhere gave one long
/// run-on line — "sometimes", because it depended on how the note happened
/// to be drawn.
///
/// Wrap the column of widgets in this. Pieces that sit on separate rows are
/// joined with a newline; pieces side by side on one row (a list bullet and
/// its text) with a space.
class NexSelectableLines extends StatefulWidget {
  const NexSelectableLines({super.key, required this.child});

  final Widget child;

  @override
  State<NexSelectableLines> createState() => _NexSelectableLinesState();
}

class _NexSelectableLinesState extends State<NexSelectableLines> {
  final _delegate = NexLineBreakingSelectionDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

/// The [StaticSelectionContainerDelegate] behind [NexSelectableLines]: the
/// same selection behaviour, with separators in what is copied.
class NexLineBreakingSelectionDelegate
    extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final buffer = StringBuffer();
    Rect? row;
    for (final selectable in selectables) {
      final content = selectable.getSelectedContent();
      if (content == null) continue;
      final rect = MatrixUtils.transformRect(
        selectable.getTransformTo(null),
        Offset.zero & selectable.size,
      );
      if (row == null) {
        row = rect;
      } else if (rect.top >= row.bottom - 1) {
        buffer.write('\n');
        row = rect;
      } else {
        buffer.write(' ');
        row = row.expandToInclude(rect);
      }
      buffer.write(content.plainText);
    }
    return row == null ? null : SelectedContent(plainText: buffer.toString());
  }
}
