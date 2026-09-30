import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/camera_sheet.dart';

const _back = CameraDescription(
  name: '0',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const _front = CameraDescription(
  name: '1',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);

/// Opens the camera from a button and records how it ended.
class _Opener extends StatefulWidget {
  const _Opener({required this.cameras, required this.onDone});

  final Future<List<CameraDescription>> Function() cameras;
  final void Function(Object? outcome) onDone;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () async {
        try {
          widget.onDone(await showNexCamera(context, cameras: widget.cameras));
        } on NexCameraUnavailable catch (error) {
          widget.onDone(error);
        }
      },
      child: const Text('open'),
    ),
  );
}

Future<List<Object?>> _open(
  WidgetTester tester,
  Future<List<CameraDescription>> Function() cameras,
) async {
  final outcomes = <Object?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: _Opener(cameras: cameras, onDone: outcomes.add),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return outcomes;
}

/// Lets the panel's give-up timer run out, so no test ends with it pending.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 9));

void main() {
  testWidgets('no camera at all falls back to the camera app', (tester) async {
    final outcomes = await _open(tester, () async => []);
    expect(outcomes.single, isA<NexCameraUnavailable>());
    expect(find.byType(NexCameraSheet), findsNothing);
    await _drain(tester);
  });

  testWidgets('a camera lookup that fails falls back too', (tester) async {
    final outcomes = await _open(tester, () async => throw StateError('x'));
    expect(outcomes.single, isA<NexCameraUnavailable>());
    await _drain(tester);
  });

  testWidgets('a camera that will not open offers the camera app', (
    tester,
  ) async {
    // No camera plugin under test: opening it never answers, and the panel
    // gives up on it.
    final outcomes = await _open(tester, () async => [_back]);
    expect(find.textContaining("Nex can't open the camera"), findsNothing);
    await tester.pump(const Duration(seconds: 9));
    expect(find.byType(NexCameraSheet), findsOneWidget);
    expect(find.textContaining("Nex can't open the camera"), findsOneWidget);
    await tester.tap(find.text('Use the camera app'));
    await tester.pumpAndSettle();
    expect(outcomes.single, isA<NexCameraUnavailable>());
    await _drain(tester);
  });

  testWidgets('back closes the panel without a photo', (tester) async {
    final outcomes = await _open(tester, () async => [_back]);
    await tester.tap(find.byTooltip('Close camera'));
    await tester.pumpAndSettle();
    expect(find.byType(NexCameraSheet), findsNothing);
    expect(outcomes, [null]);
    await _drain(tester);
  });

  testWidgets('the menu switches camera and cycles the flash', (tester) async {
    await _open(tester, () async => [_back, _front]);
    await tester.tap(find.byTooltip('Camera options'));
    await tester.pumpAndSettle();
    expect(find.text('Switch camera'), findsOneWidget);
    expect(find.text('Flash off'), findsOneWidget);

    await tester.tap(find.text('Flash off'));
    await tester.pumpAndSettle();
    expect(find.text('Flash auto'), findsOneWidget);
    await tester.tap(find.text('Flash auto'));
    await tester.pumpAndSettle();
    expect(find.text('Flash on'), findsOneWidget);
    await tester.tap(find.text('Flash on'));
    await tester.pumpAndSettle();
    expect(find.text('Flash off'), findsOneWidget);

    // Tapping anywhere else on the panel puts the menu away.
    await tester.tapAt(tester.getCenter(find.byType(NexCameraSheet)));
    await tester.pumpAndSettle();
    final menu = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.text('Flash off'),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(menu.ignoring, isTrue);
    await _drain(tester);
  });

  testWidgets('one camera means no switch in the menu', (tester) async {
    await _open(tester, () async => [_back]);
    await tester.tap(find.byTooltip('Camera options'));
    await tester.pumpAndSettle();
    expect(find.text('Switch camera'), findsNothing);
    await _drain(tester);
  });

  testWidgets('pulled down, the panel closes', (tester) async {
    final outcomes = await _open(tester, () async => [_back]);
    await tester.fling(find.byType(NexCameraSheet), const Offset(0, 300), 1500);
    await tester.pumpAndSettle();
    expect(find.byType(NexCameraSheet), findsNothing);
    expect(outcomes, [null]);
    await _drain(tester);
  });
}
