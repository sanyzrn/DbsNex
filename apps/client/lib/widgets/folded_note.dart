import 'package:nex_core/nex_core.dart';
import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'feature_label.dart';

class FoldedNote extends StatefulWidget {
  const FoldedNote({
    super.key,
    required this.text,
    this.onTapLink,
    this.onCopyCode,
  });
  final String text;
  final void Function(String)? onTapLink;
  final void Function(String)? onCopyCode;
  @override
  State<FoldedNote> createState() => _FoldedNoteState();
}

class _FoldedNoteState extends State<FoldedNote> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final chars = widget.text.characters;
    final lines = widget.text.split('\n');
    final long = chars.length > 900 || lines.length > 12;
    final text = !long || expanded
        ? widget.text
        : '${lines.take(12).join('\n').characters.take(900)}…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionArea(
          contextMenuBuilder: nexSelectionMenu,
          child: nexLooksLikeMarkdown(text)
              ? NexMarkdown(
                  text,
                  selectable: false,
                  onTapLink: widget.onTapLink,
                  onCopyCode: widget.onCopyCode,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.62),
                )
              : NexTextSurface(
                  text,
                  selectable: false,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.62),
                ),
        ),
        if (long)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => expanded = !expanded),
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                expanded
                    ? nexLabel(context, 'Less', 'کمتر')
                    : nexLabel(context, 'More', 'بیشتر'),
              ),
            ),
          ),
      ],
    );
  }
}
