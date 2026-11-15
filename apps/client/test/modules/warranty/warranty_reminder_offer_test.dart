import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_reminder_offer.dart';

/// The reminder the editor offers at the moment the end date is saved: on
/// by default, with the lead times still in the future and the exact day it
/// will ring.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
    double scale = 1,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: home,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget offer({
    bool enabled = true,
    bool refreshing = false,
    List<int> choices = const [30, 7, 1],
    int? selected = 30,
    DateTime? moment,
    ValueChanged<bool>? onChanged,
    ValueChanged<int>? onDays,
  }) => _OfferHarness(
    enabled: enabled,
    refreshing: refreshing,
    choices: choices,
    selected: selected,
    moment: moment ?? DateTime(2027, 8, 21, 9),
    onChanged: onChanged,
    onDays: onDays,
  );

  testWidgets('a new purchase offers it on, with 30, 7 and 1 days before', (
    tester,
  ) async {
    await pump(tester, offer());
    expect(
      find.byKey(const ValueKey('warranty-remind-switch')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('warranty-remind-switch')))
          .value,
      isTrue,
    );
    expect(find.text('30 days before'), findsOneWidget);
    expect(find.text('7 days before'), findsOneWidget);
    expect(find.text('1 day before'), findsOneWidget);
    // The moment it rings, on the person's own calendar.
    expect(find.text('On 2027/08/21, at 9 in the morning'), findsOneWidget);
    // Nothing is promised beyond a device alert.
    expect(find.textContaining('notification permission'), findsOneWidget);
  });

  testWidgets('turning it off leaves only the offer line', (tester) async {
    await pump(tester, offer(enabled: false));
    expect(find.text('30 days before'), findsNothing);
    expect(find.byKey(const ValueKey('warranty-remind-at')), findsNothing);
    expect(find.text('Remind me before it ends'), findsOneWidget);
  });

  testWidgets('a saved purchase says an earlier reminder is left alone', (
    tester,
  ) async {
    await pump(tester, offer(enabled: false, refreshing: true));
    expect(
      find.textContaining('existing reminder is left as it is'),
      findsOneWidget,
    );
  });

  testWidgets('the switch and the lead-time chips answer taps', (tester) async {
    bool? switched;
    int? chosen;
    await pump(
      tester,
      offer(
        onChanged: (value) => switched = value,
        onDays: (days) => chosen = days,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('warranty-remind-7')));
    await tester.pump();
    expect(chosen, 7);
    await tester.tap(find.byKey(const ValueKey('warranty-remind-switch')));
    await tester.pump();
    expect(switched, isFalse);
  });

  testWidgets('Persian reads in Persian digits', (tester) async {
    await pump(tester, offer(), locale: const Locale('fa'));
    expect(find.text('۳۰ روز قبل'), findsOneWidget);
    expect(find.text('۷ روز قبل'), findsOneWidget);
    expect(find.text('در ۱۴۰۶/۰۵/۳۰، ساعت ۹ صبح'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('twice the text on a small phone does not overflow', (
    tester,
  ) async {
    await pump(tester, offer(), scale: 2, size: const Size(320, 480));
    expect(find.text('Remind me before it ends'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The offer is controlled: this keeps its switch and chips answering the
/// way the editor does.
class _OfferHarness extends StatefulWidget {
  const _OfferHarness({
    required this.enabled,
    required this.refreshing,
    required this.choices,
    required this.selected,
    required this.moment,
    this.onChanged,
    this.onDays,
  });

  final bool enabled;
  final bool refreshing;
  final List<int> choices;
  final int? selected;
  final DateTime moment;
  final ValueChanged<bool>? onChanged;
  final ValueChanged<int>? onDays;

  @override
  State<_OfferHarness> createState() => _OfferHarnessState();
}

class _OfferHarnessState extends State<_OfferHarness> {
  late bool _enabled = widget.enabled;
  late int? _selected = widget.selected;

  @override
  Widget build(BuildContext context) => WarrantyReminderOffer(
    enabled: _enabled,
    onChanged: (value) {
      widget.onChanged?.call(value);
      setState(() => _enabled = value);
    },
    moment: widget.moment,
    choices: widget.choices,
    selectedDays: _selected,
    onDays: (days) {
      widget.onDays?.call(days);
      setState(() => _selected = days);
    },
    refreshing: widget.refreshing,
  );
}
