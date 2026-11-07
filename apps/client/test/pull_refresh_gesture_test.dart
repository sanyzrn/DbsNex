import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_pull_refresh.dart';

void main() {
  for (final parent in [
    const ClampingScrollPhysics(),
    const BouncingScrollPhysics(),
  ]) {
    testWidgets('$parent continuous reversal closes pull before scrolling', (
      tester,
    ) async {
      final scroll = ScrollController();
      final pull = NexPullRefreshController();
      addTearDown(scroll.dispose);
      var refreshed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexPullRefresh(
              controller: pull,
              onRefresh: () async {
                refreshed++;
              },
              child: ListView.builder(
                controller: scroll,
                physics: pull.physics(
                  parent: AlwaysScrollableScrollPhysics(parent: parent),
                ),
                itemCount: 100,
                itemBuilder: (_, i) =>
                    SizedBox(height: 60, child: Text('Note $i')),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(const Offset(200, 180));
      await gesture.moveBy(const Offset(0, 230));
      await tester.pump();
      expect(pull.extent, greaterThan(100));
      expect(scroll.offset, 0);
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump();
      expect(pull.extent, greaterThan(0));
      expect(scroll.offset, 0);
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      expect(pull.extent, greaterThan(0));
      expect(scroll.offset, 0);
      await gesture.moveBy(const Offset(0, -180));
      await tester.pump();
      expect(pull.extent, 0);
      expect(scroll.offset, greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(refreshed, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final kind in [
    'short',
    'success',
    'failure',
    'cancelled',
    'multitouch',
  ]) {
    testWidgets('$kind pull has the correct completion behavior', (
      tester,
    ) async {
      var calls = 0;
      var successes = 0;
      final pull = NexPullRefreshController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexPullRefresh(
              controller: pull,
              completion: () => kind == 'cancelled'
                  ? NexRefreshOutcome.cancelled
                  : NexRefreshOutcome.success,
              onSettled: () {
                successes++;
              },
              onRefresh: () async {
                calls++;
                if (kind == 'failure') throw StateError('offline');
              },
              child: ListView(
                physics: pull.physics(
                  parent: const AlwaysScrollableScrollPhysics(),
                ),
                children: const [SizedBox(height: 1000)],
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(const Offset(200, 150));
      await gesture.moveBy(Offset(0, kind == 'short' ? 60 : 240));
      await tester.pump();
      if (kind == 'multitouch') {
        // Let the tester allocate a fresh pointer ID. A fixed ID can
        // collide with the first gesture after randomized test ordering.
        final other = await tester.startGesture(const Offset(250, 200));
        await tester.pump();
        await other.up();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, kind == 'short' || kind == 'multitouch' ? 0 : 1);
      expect(successes, kind == 'success' ? 1 : 0);
      expect(pull.extent, closeTo(0, 0.01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('completion respects reduced motion without a ticker', (
    tester,
  ) async {
    final pulse = ValueNotifier(0);
    addTearDown(pulse.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: NexRefreshCompletion(
            pulse: pulse,
            child: const SizedBox(height: 200),
          ),
        ),
      ),
    );
    pulse.value++;
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion repaints without moving or remounting its child', (
    tester,
  ) async {
    final pulse = ValueNotifier(0);
    addTearDown(pulse.dispose);
    var mounts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NexRefreshCompletion(
            pulse: pulse,
            child: _MountCounter(
              onMount: () {
                mounts++;
              },
            ),
          ),
        ),
      ),
    );
    final before = tester.getRect(find.byKey(const ValueKey('stable-card')));
    pulse.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getRect(find.byKey(const ValueKey('stable-card'))), before);
    expect(mounts, 1);
    await tester.pumpAndSettle();
    expect(mounts, 1);
  });
}

class _MountCounter extends StatefulWidget {
  const _MountCounter({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: ValueKey('stable-card'), height: 160, width: 300);
}
