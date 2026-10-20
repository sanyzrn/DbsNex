import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart' show NexSpacing;
import '../platform/display_date.dart';
import '../widgets/nex_time_picker.dart';

/// The app's time picker, for a module's own reminder rows.
Future<TimeOfDay?> nexPickModuleTime(
  BuildContext context, {
  required TimeOfDay initial,
}) => nexPickTime(context, initial: initial);

class NexModuleCalendar extends InheritedWidget {
  const NexModuleCalendar({
    super.key,
    required this.solar,
    required super.child,
  });
  final bool solar;
  static bool solarOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NexModuleCalendar>()?.solar ??
      (Localizations.localeOf(context).languageCode == 'fa');
  @override
  bool updateShouldNotify(NexModuleCalendar oldWidget) =>
      solar != oldWidget.solar;
}

Future<DateTime?> nexPickModuleDate(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) => nexPickDate(
  context,
  initial: initial,
  first: first,
  last: last,
  solar: NexModuleCalendar.solarOf(context),
);

String nexModuleDateLabel(BuildContext context, DateTime date) =>
    nexDisplayDate(
      date,
      solar: NexModuleCalendar.solarOf(context),
      persian: Localizations.localeOf(context).languageCode == 'fa',
    );

/// Existing civil text entry remains available. The calendar button lets a
/// person choose a Jalali day without changing record formats or parsers.
class NexModuleDateEntry extends StatelessWidget {
  const NexModuleDateEntry({
    super.key,
    required this.controller,
    required this.child,
    this.hyphenated = false,
  });
  final TextEditingController controller;
  final Widget child;
  final bool hyphenated;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: child),
      // Beside the field, not under it: a calendar button on a row
      // of its own read as belonging to nothing, and cost every form 48dp.
      Padding(
        padding: const EdgeInsetsDirectional.only(start: NexSpacing.xs, top: 4),
        child: IconButton(
          tooltip: MaterialLocalizations.of(context).datePickerHelpText,
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () async {
            final parsed = DateTime.tryParse(
              controller.text.replaceAll('/', '-'),
            );
            final first = DateTime(1900), last = DateTime(2100, 12, 31);
            final candidate = parsed ?? DateTime.now();
            final picked = await nexPickModuleDate(
              context,
              initial: candidate.isBefore(first)
                  ? first
                  : candidate.isAfter(last)
                  ? last
                  : candidate,
              first: first,
              last: last,
            );
            if (picked == null || !context.mounted) return;
            final separator = hyphenated ? '-' : '/';
            controller.text =
                '${picked.year}$separator${picked.month.toString().padLeft(2, '0')}$separator${picked.day.toString().padLeft(2, '0')}';
          },
        ),
      ),
    ],
  );
}
