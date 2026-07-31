import 'package:flutter/material.dart';

import 'package:nex_ui/nex_ui.dart';

/// Wraps dialog content at a stable width.
///
/// `AlertDialog` sizes itself to its content's intrinsic width, so a dialog
/// holding a text field started as a narrow box and widened with every word
/// typed into it. Every dialog in the app is the same width now, capped so it
/// does not stretch across a desktop window.
class NexDialogBody extends StatelessWidget {
  const NexDialogBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      // maxFinite lets the dialog take the width its own constraints allow,
      // which is the platform's dialog width rather than the content's.
      width: width < 420 ? double.maxFinite : 380,
      child: child,
    );
  }
}

/// Opens a bottom sheet the way every bottom sheet in Nex opens.
///
/// The nine call sites had drifted into nine different presentations: some
/// declared `useSafeArea`, some wrapped a `SafeArea` by hand inside the
/// builder, and the tag merge sheet did neither — so on a device with gesture
/// navigation its last row sat under the system bar. `showDragHandle` was set
/// on most but not all, which meant the affordance telling you a sheet can be
/// dragged away appeared on some sheets and not others, with no rule behind
/// which.
///
/// `isScrollControlled` is on for all of them. It does not force a tall sheet —
/// content that sizes itself still does — it only lifts the half-screen cap
/// that would otherwise clip a long list instead of scrolling it.
///
/// [dismissible] is the one real axis of difference: the recording sheet must
/// not be swiped away mid-recording, and a sheet that cannot be dragged away
/// must not advertise a drag handle.
///
/// **The bottom `SafeArea` is not redundant with `useSafeArea`.** Flutter
/// applies `SafeArea(bottom: false)` for that flag — it guards the status bar
/// and nothing else, and its own documentation says so: "the bottom sheet
/// extends all the way to the bottom of the screen, including any system
/// intrusions." Every sheet has to inset its own bottom edge, and the ones
/// that remembered to did it three different ways. On a phone using gesture
/// navigation the intrusion is small enough to look like padding; switch the
/// same phone to three-button navigation and the sheet's last control — Delete
/// on a note, Save on a picker — sits under the navigation bar.
Future<T?> nexShowSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: dismissible,
  enableDrag: dismissible,
  showDragHandle: dismissible,
  builder: (context) => SafeArea(top: false, child: builder(context)),
);

/// A bottom sheet body that always fills the sheet's width.
class NexSheetBody extends StatelessWidget {
  const NexSheetBody({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: padding ?? const EdgeInsets.all(NexSpacing.lg),
      child: child,
    ),
  );
}
