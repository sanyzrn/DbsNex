import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/image_pdf.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../../platform/sharing.dart';
import '../../widgets/nex_banner.dart';
import 'cycle_format.dart';

/// A one-page summary of the cycle to show a doctor, saved or shared as a
/// PDF.
///
/// What is on the page is what is on the screen: it is drawn here, on a
/// white A4 sheet whatever the theme, and captured into the PDF
/// ([nexImagePdf]) — so the Persian reads exactly as it does in the app.
class CycleReportScreen extends StatefulWidget {
  const CycleReportScreen({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<CycleReportScreen> createState() => _CycleReportScreenState();
}

class _CycleReportScreenState extends State<CycleReportScreen> {
  final _page = GlobalKey();
  _ReportData? _data;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final periods = await widget.services.cyclePeriods();
    final logs = await widget.services.cycleDays(DateTime(2000), today);
    final prediction = CyclePredictor.predict(
      periods: periods,
      today: CycleDate.of(today),
      typicalCycle: widget.preferences.cycleTypicalLength,
      typicalPeriod: widget.preferences.cycleTypicalPeriod,
    );
    final since = CycleDate.of(today).addDays(-182);
    final counts = <CycleSymptom, int>{};
    for (final log in logs) {
      if (log.day.isBefore(since)) continue;
      for (final s in log.symptoms) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
    }
    if (!mounted) return;
    setState(
      () => _data = _ReportData(
        today: today,
        periods: periods,
        prediction: prediction,
        symptoms: counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)),
        patterns: CyclePatterns.find(periods: periods, logs: logs),
      ),
    );
  }

  Future<File?> _pdf() async {
    final boundary =
        _page.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    final height = image.height;
    image.dispose();
    if (bytes == null) return null;
    final picture = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      numChannels: 4,
    );
    final jpeg = img.encodeJpg(picture, quality: 88);
    final pdf = nexImagePdf([(jpeg: jpeg, width: width, height: height)]);
    final folder = await Directory.systemTemp.createTemp('nex-report-');
    final file = File('${folder.path}${Platform.pathSeparator}report.pdf');
    await file.writeAsBytes(pdf, flush: true);
    return file;
  }

  Future<void> _export({required bool share}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final name = '${l10n.cycleReportTitle} ${CycleDate.of(DateTime.now())}.pdf';
    File? file;
    try {
      file = await _pdf();
      if (file == null) return;
      if (share) {
        await nexSendFileOut(
          file.path,
          suggestedName: name,
          mimeType: 'application/pdf',
        );
      } else {
        final outcome = await nexSaveFileToDevice(
          file.path,
          name: name,
          mimeType: 'application/pdf',
        );
        if (!mounted) return;
        if (outcome == SaveOutcome.saved) {
          nexShowBanner(
            context,
            message: l10n.cycleReportSaved,
            kind: NexBannerKind.done,
          );
        } else if (outcome == SaveOutcome.failed) {
          nexShowBanner(
            context,
            message: l10n.saveToDeviceFailed,
            kind: NexBannerKind.failed,
          );
        }
      }
    } finally {
      try {
        file?.parent.deleteSync(recursive: true);
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cycleReport),
        actions: [
          IconButton(
            tooltip: l10n.share,
            onPressed: data == null || _busy
                ? null
                : () => _export(share: true),
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(NexSpacing.md),
                        child: FittedBox(
                          child: RepaintBoundary(
                            key: _page,
                            child: _ReportPage(
                              data: data,
                              mode: widget.preferences.cycleMode,
                              solar: widget.services.solarCalendar,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(NexSpacing.md),
                    child: FilledButton.icon(
                      key: const ValueKey('cycle-report-save'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _busy ? null : () => _export(share: false),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(l10n.cycleReportSave),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReportData {
  const _ReportData({
    required this.today,
    required this.periods,
    required this.prediction,
    required this.symptoms,
    required this.patterns,
  });

  final DateTime today;
  final List<CyclePeriod> periods;
  final CyclePrediction? prediction;
  final List<MapEntry<CycleSymptom, int>> symptoms;
  final List<CyclePattern> patterns;
}

/// The A4 sheet itself: 595 × 842 logical pixels, black on white.
class _ReportPage extends StatelessWidget {
  const _ReportPage({
    required this.data,
    required this.mode,
    required this.solar,
  });

  final _ReportData data;
  final CycleMode mode;
  final bool solar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final light = nexLightTheme();
    final text = light.textTheme.apply(
      bodyColor: Colors.black87,
      displayColor: Colors.black87,
    );
    final rose = cyclePeriodColor(Brightness.light);
    String digits(Object v) => cycleDigits(context, v);
    String day(CycleDate d) => cycleDayMonth(context, d.local, solar: solar);
    String year(CycleDate d) {
      final y = solar ? nexPersianDate(d.local).year : d.year;
      return digits(y);
    }

    final p = data.prediction;
    final recent = data.periods.reversed.take(8).toList();
    Widget heading(String s) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        s,
        style: text.titleSmall?.copyWith(
          color: rose,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    Widget cell(String s, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: Text(
        s,
        style: text.bodySmall?.copyWith(
          fontWeight: bold ? FontWeight.w700 : null,
        ),
      ),
    );

    return Theme(
      data: light,
      child: Container(
        width: 595,
        height: 842,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(40, 36, 40, 28),
        child: DefaultTextStyle(
          style: text.bodyMedium!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.water_drop, color: rose, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.cycleReportTitle,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    l10n.cycleReportMade(
                      '${day(CycleDate.of(data.today))} '
                      '${year(CycleDate.of(data.today))}',
                    ),
                    style: text.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
              const Divider(height: 20),
              Text('${l10n.cycleMode}: ${cycleModeLabel(l10n, mode)}'),
              if (p != null) ...[
                heading(l10n.cycleInsights),
                Wrap(
                  spacing: 28,
                  runSpacing: 6,
                  children: [
                    Text(
                      '${l10n.cycleReportCycleLength}: '
                      '${digits(l10n.cycleDays(p.averageCycle))}',
                    ),
                    Text(
                      '${l10n.cycleLegendPeriod}: '
                      '${digits(l10n.cycleDays(p.averagePeriod))}',
                    ),
                    Text(
                      '${l10n.cycleReportVariation}: '
                      '± ${digits(p.variability.toStringAsFixed(1))}',
                    ),
                    Text('${l10n.cycleCyclesCounted}: ${digits(p.cyclesUsed)}'),
                  ],
                ),
                if (p.alerts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final alert in p.alerts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${cycleAlertText(l10n, alert)}',
                        style: text.bodySmall,
                      ),
                    ),
                ],
              ],
              heading(l10n.cycleReportPeriods),
              if (recent.isEmpty)
                Text(l10n.cycleNothingLogged)
              else
                Table(
                  border: TableBorder(
                    horizontalInside: BorderSide(color: Colors.black12),
                  ),
                  children: [
                    TableRow(
                      children: [
                        cell(l10n.cycleStart, bold: true),
                        cell(l10n.cycleEnd, bold: true),
                        cell(l10n.cycleLegendPeriod, bold: true),
                        cell(l10n.cycleReportCycleLength, bold: true),
                      ],
                    ),
                    for (var i = 0; i < recent.length; i++)
                      TableRow(
                        children: [
                          cell(
                            '${day(recent[i].start)} ${year(recent[i].start)}',
                          ),
                          cell(
                            recent[i].end == null
                                ? l10n.cycleOngoing
                                : day(recent[i].end!),
                          ),
                          cell(
                            recent[i].length == null
                                ? '—'
                                : digits(l10n.cycleDays(recent[i].length!)),
                          ),
                          cell(
                            i == 0
                                ? '—'
                                : digits(
                                    l10n.cycleDays(
                                      recent[i - 1].start.daysSince(
                                        recent[i].start,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                  ],
                ),
              heading(l10n.cycleReportSymptoms),
              if (data.symptoms.isEmpty)
                Text(l10n.cycleNothingLogged)
              else
                Wrap(
                  spacing: 18,
                  runSpacing: 4,
                  children: [
                    for (final entry in data.symptoms.take(10))
                      Text(
                        '${cycleSymptomLabel(l10n, entry.key)}: '
                        '${digits(l10n.cycleDays(entry.value))}',
                      ),
                  ],
                ),
              if (data.patterns.isNotEmpty) ...[
                heading(l10n.cyclePatterns),
                for (final pattern in data.patterns.take(6))
                  Text('• ${cyclePatternText(context, pattern)}'),
              ],
              const Spacer(),
              const Divider(),
              Text(
                l10n.cycleDisclaimer,
                style: text.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
