import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/metrics.dart';
import '../platform/nex_preferences.dart';

/// Settings → About → Speed and reliability (W3.4).
///
/// The switch, what it measures and what it never does, and — once there is
/// something to show — the numbers themselves: the usual time and the slow
/// end of each, and how many sessions with a capture ran without an error.
class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key, required this.preferences, this.metrics});

  final NexPreferences preferences;

  /// The store to show; [NexMetrics.shared] unless a test passes its own.
  final NexMetrics? metrics;

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  NexMetrics get _metrics => widget.metrics ?? NexMetrics.shared;

  Future<void> _toggle(bool value) async {
    await widget.preferences.setMetricsEnabled(value);
    await _metrics.setEnabled(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final on = widget.preferences.metricsEnabled;
    final sessions = _metrics.sessions;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.metricsTitle)),
      body: ListView(
        padding: EdgeInsets.only(
          top: NexSpacing.sm,
          bottom: NexSpacing.lg + nexBottomInset(context),
        ),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.speed_outlined),
            title: Text(l10n.metricsSwitch),
            value: on,
            onChanged: (value) => unawaited(_toggle(value)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.lg,
              NexSpacing.xs,
              NexSpacing.lg,
              NexSpacing.md,
            ),
            child: Text(l10n.metricsIntro, style: muted),
          ),
          if (on && _metrics.isEmpty)
            Padding(
              padding: const EdgeInsets.all(NexSpacing.xl),
              child: Text(
                l10n.metricsEmpty,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            )
          else if (on) ...[
            const Divider(height: 1),
            _MetricTile(
              icon: Icons.folder_open_outlined,
              title: l10n.metricsLaunch,
              stats: _metrics.stats(NexMetric.launch),
            ),
            _MetricTile(
              icon: Icons.view_agenda_outlined,
              title: l10n.metricsTimeline,
              hint: l10n.metricsTimelineHint,
              stats: _metrics.stats(NexMetric.timeline),
            ),
            _MetricTile(
              icon: Icons.edit_note_outlined,
              title: l10n.metricsCapture,
              stats: _metrics.stats(NexMetric.capture),
            ),
            _MetricTile(
              icon: Icons.search,
              title: l10n.metricsSearch,
              stats: _metrics.stats(NexMetric.searchToOpen),
            ),
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(l10n.metricsSessions),
              subtitle: Text(
                sessions.withCapture == 0
                    ? l10n.metricsNoData
                    : l10n.metricsSessionsValue(
                        _digits(context, '${sessions.clean}'),
                        _digits(context, '${sessions.withCapture}'),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.lg,
                NexSpacing.sm,
                NexSpacing.lg,
                0,
              ),
              child: Text(
                l10n.metricsFootnote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.title,
    required this.stats,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final NexMetricStats? stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = stats;
    final value = s == null
        ? l10n.metricsNoData
        : '${l10n.metricsValue(nexMetricDuration(context, s.median), nexMetricDuration(context, s.p90))}'
              ' · ${l10n.metricsCount(s.count)}';
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(hint == null ? value : '$value\n$hint'),
      isThreeLine: hint != null,
    );
  }
}

String _digits(BuildContext context, String text) => nexDigits(
  text,
  persian: Localizations.localeOf(context).languageCode == 'fa',
);

/// A duration the way the screen shows it: milliseconds under a second,
/// seconds with one decimal above, in the reader's digits.
String nexMetricDuration(BuildContext context, Duration d) {
  final l10n = AppLocalizations.of(context);
  if (d.inMilliseconds < 1000) {
    return l10n.metricsMs(_digits(context, '${d.inMilliseconds}'));
  }
  final seconds = (d.inMilliseconds / 1000).toStringAsFixed(1);
  final persian = Localizations.localeOf(context).languageCode == 'fa';
  return l10n.metricsSeconds(
    _digits(context, persian ? seconds.replaceAll('.', '٫') : seconds),
  );
}
