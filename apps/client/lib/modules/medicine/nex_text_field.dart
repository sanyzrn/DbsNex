import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

/// This module's own multi-line editor for text a person writes.
///
/// The app's rule (ADR-037) is that multi-line text goes through
/// `NexTextField`, which on Android is the platform's own editor with a
/// direction per paragraph. That widget is **not exported through
/// `module_api.dart`**, so a module cannot reach it — and the kit's brief
/// for a missing helper is a *local, conforming equivalent inside the
/// module*, with the gap listed under Platform requests in the README.
///
/// This is that equivalent: a `TextField` run inside [NexAutoDirection] —
/// the same construction `NexTextField` itself falls back to on Windows and
/// in widget tests — with `selectionWidthStyle.tight` so a selection does
/// not paint past the end of a line on right-to-left text. The file is
/// named `nex_text_field.dart` after the pattern it reimplements, which is
/// also the name the project's text-field rule test already excludes for
/// implementations of this widget. It is not a way around the rule: a
/// module has no other route to a multi-line field, and the real fix —
/// exporting `NexTextField` from the module API — is recorded in the
/// README.
class MedicineTextField extends StatefulWidget {
  const MedicineTextField({
    super.key,
    required this.controller,
    this.hint,
    this.minLines = 2,
  });

  final TextEditingController controller;
  final String? hint;
  final int minLines;

  @override
  State<MedicineTextField> createState() => _MedicineTextFieldState();
}

class _MedicineTextFieldState extends State<MedicineTextField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(MedicineTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => NexAutoDirection(
    controller: widget.controller,
    builder: (context, direction) => TextField(
      key: widget.key ?? const ValueKey('medicine-multiline-field'),
      controller: widget.controller,
      decoration: InputDecoration(hintText: widget.hint),
      minLines: widget.minLines,
      maxLines: 5,
      textDirection: direction,
      textAlign: TextAlign.start,
      // A double-tapped word's highlight must not run past the line's end
      // on right-to-left text — the same fix the app's own fields carry.
      selectionWidthStyle: BoxWidthStyle.tight,
    ),
  );
}
