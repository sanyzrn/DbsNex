import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../platform/display_date.dart';

/// Age of the successful text on screen, never the start of a request.
String nexSummaryAge(AppLocalizations l, DateTime at, DateTime now) {
  final age = now.difference(at);
  if (age.inMinutes < 1) return l.timeNow;
  if (age.inHours < 1) return l.briefUpdatedMinutes(age.inMinutes);
  if (age.inDays < 1) {
    return age.inMinutes % 60 == 0
        ? l.briefUpdatedHours(age.inHours)
        : l.briefUpdatedHoursMinutes(age.inHours, age.inMinutes % 60);
  }
  return l.briefUpdatedDaysHours(age.inDays, age.inHours % 24);
}

/// A minute clock confined to one label. It cannot refresh the brief or AI.
class SummaryUpdatedTime extends StatefulWidget {
  const SummaryUpdatedTime({
    super.key,
    required this.at,
    this.solarCalendar = false,
    this.clock = DateTime.now,
  });
  final DateTime at;
  final bool solarCalendar;
  final DateTime Function() clock;

  @override
  State<SummaryUpdatedTime> createState() => _SummaryUpdatedTimeState();
}

class _SummaryUpdatedTimeState extends State<SummaryUpdatedTime>
    with WidgetsBindingObserver {
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void _schedule() {
    _minute?.cancel();
    final age = widget.clock().difference(widget.at);
    final wait = age.isNegative
        ? const Duration(minutes: 1)
        : Duration(milliseconds: 60000 - age.inMilliseconds % 60000);
    _minute = Timer(wait, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void didUpdateWidget(SummaryUpdatedTime old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at || old.clock != widget.clock) _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _schedule();
    } else {
      _minute?.cancel();
    }
  }

  @override
  void dispose() {
    _minute?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final age = nexSummaryAge(l, widget.at, widget.clock());
    return Tooltip(
      excludeFromSemantics: true,
      message: l.briefLastUpdated(
        nexReadableDate(
          widget.at,
          solar: widget.solarCalendar,
          persian: l.localeName == 'fa',
          time: true,
        ),
      ),
      child: Semantics(
        label: l.briefLastUpdated(age),
        excludeSemantics: true,
        child: Text(
          age,
          key: const ValueKey('brief-updated-age'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
