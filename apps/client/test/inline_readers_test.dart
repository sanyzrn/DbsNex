import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/route_observer.dart';
import 'package:nex_client/widgets/pdf_reader.dart';
import 'package:nex_client/widgets/video_player.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  final events = <int, StreamController<VideoEvent>>{};
  final playing = <int>{};
  final disposed = <int>[];
  final speeds = <double>[];
  final volumes = <double>[];
  final positions = <int, Duration>{};
  bool delayInitialization = false;
  bool failInitialization = false;
  int created = 0;

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++created;
    events[id] = StreamController<VideoEvent>.broadcast();
    return id;
  }

  void initialize(int id) => events[id]!.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 3),
      size: const Size(1280, 720),
    ),
  );
  @override
  Stream<VideoEvent> videoEventsFor(int id) {
    if (failInitialization) {
      scheduleMicrotask(
        () => events[id]!.addError(
          PlatformException(code: 'unsupported', message: 'Unsupported codec'),
        ),
      );
    } else if (!delayInitialization) {
      scheduleMicrotask(() => initialize(id));
    }
    return events[id]!.stream;
  }

  @override
  Future<void> dispose(int id) async {
    disposed.add(id);
    playing.remove(id);
    await events[id]!.close();
  }

  @override
  Future<void> play(int id) async {
    playing.add(id);
  }

  @override
  Future<void> pause(int id) async {
    playing.remove(id);
  }

  @override
  Future<void> setLooping(int id, bool looping) async {}
  @override
  Future<void> setVolume(int id, double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {
    speeds.add(speed);
  }

  @override
  Future<void> seekTo(int id, Duration position) async {
    positions[id] = position;
  }

  @override
  Future<Duration> getPosition(int id) async => positions[id] ?? Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.blueGrey);
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

void readerTest(String description, WidgetTesterCallback body) {
  testWidgets(
    description,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nex/os_capture');
  final png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
    ),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _VideoPlatform platform;
  late VideoPlayerPlatform original;
  final pdfCalls = <Map<Object?, Object?>>[];

  setUp(() {
    original = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    pdfCalls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'videoPreview') return png;
      if (call.method == 'pdfPage') {
        pdfCalls.add(Map<Object?, Object?>.from(call.arguments as Map));
        return {'bytes': png, 'pageCount': 3};
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    VideoPlayerPlatform.instance = original;
  });

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    String language = 'en',
    double scale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(380, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [nexRouteObserver],
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: dark ? nexDarkTheme() : nexLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  readerTest(
    'PDF pages navigate inline, reset zoom, and do not preload the document',
    (tester) async {
      var external = 0;
      await show(
        tester,
        NexPdfReader(path: '/report.pdf', onOpen: () => external++),
      );
      expect(pdfCalls.map((call) => call['index']), [0]);
      expect(find.text('Page 1 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reset zoom'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-next')));
      await tester.pumpAndSettle();
      expect(pdfCalls.map((call) => call['index']), [0, 1]);
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('pdf-page-slider')),
      );
      slider.onChangeEnd!(3);
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('pdf-next')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Open in another app'));
      expect(external, 1);
    },
  );

  readerTest('PDF late result cannot overwrite a different path', (
    tester,
  ) async {
    final old = Completer<Object?>();
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => (call.arguments as Map)['path'] == '/old.pdf'
          ? old.future
          : {'bytes': png, 'pageCount': 2},
    );
    await show(tester, NexPdfReader(path: '/old.pdf', onOpen: () {}));
    await show(tester, NexPdfReader(path: '/new.pdf', onOpen: () {}));
    old.complete({'bytes': png, 'pageCount': 50});
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.textContaining('50'), findsNothing);
  });

  readerTest('PDF unavailable retains retry and external opening', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    var external = 0;
    await show(
      tester,
      NexPdfReader(path: '/protected.pdf', onOpen: () => external++),
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('cannot be shown'), findsOneWidget);
    await tester.tap(find.byTooltip('Open in another app'));
    expect(external, 1);
  });

  readerTest('video opens lazily, plays, seeks, mutes and changes speed', (
    tester,
  ) async {
    await show(tester, NexVideoPlayer(path: '/clip.mp4', onOpen: () {}));
    expect(platform.created, 0);
    await tester.tap(find.byKey(const ValueKey('video-cover-play')));
    await tester.pumpAndSettle();
    expect(platform.created, 1);
    expect(platform.playing, {1});
    await tester.tap(find.byKey(const ValueKey('video-speed')));
    await tester.pumpAndSettle();
    expect(platform.speeds.last, 1.5);
    await tester.tap(find.byTooltip('Mute video'));
    await tester.pumpAndSettle();
    expect(platform.volumes.last, 0);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('video-seek')),
    );
    slider.onChangeEnd!(45000);
    await tester.pumpAndSettle();
    expect(platform.positions[1], const Duration(seconds: 45));
    await tester.tap(find.byKey(const ValueKey('video-play')));
    await tester.pumpAndSettle();
    expect(platform.playing, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(platform.disposed, [1]);
  });

  readerTest('video pauses under another route and stays paused on return', (
    tester,
  ) async {
    await show(tester, NexVideoPlayer(path: '/clip.mp4', onOpen: () {}));
    await tester.tap(find.byKey(const ValueKey('video-cover-play')));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NexVideoPlayer));
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('covered')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.playing, isEmpty);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(platform.playing, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  readerTest('unsupported video retains a usable external fallback', (
    tester,
  ) async {
    platform.failInitialization = true;
    var external = 0;
    await show(
      tester,
      NexVideoPlayer(path: '/unsupported.mp4', onOpen: () => external++),
    );
    await tester.tap(find.byKey(const ValueKey('video-cover-play')));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be shown'), findsOneWidget);
    await tester.tap(find.byTooltip('Open in another app'));
    expect(external, 1);
    expect(platform.playing, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  readerTest('two inline videos cannot play over one another', (tester) async {
    await show(
      tester,
      Column(
        children: [
          NexVideoPlayer(path: '/first.mp4', onOpen: () {}),
          NexVideoPlayer(path: '/second.mp4', onOpen: () {}),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('video-cover-play')).first);
    await tester.pumpAndSettle();
    expect(platform.playing, {1});
    await tester.ensureVisible(
      find.byKey(const ValueKey('video-cover-play')).first,
    );
    await tester.tap(find.byKey(const ValueKey('video-cover-play')).first);
    await tester.pumpAndSettle();
    expect(platform.playing, {2});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(platform.playing, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.playing, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  readerTest(
    'backgrounding during video initialization cannot start delayed playback',
    (tester) async {
      platform.delayInitialization = true;
      await show(tester, NexVideoPlayer(path: '/clip.mp4', onOpen: () {}));
      await tester.tap(find.byKey(const ValueKey('video-cover-play')));
      await tester.pump();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      platform.initialize(1);
      await tester.pumpAndSettle();
      expect(platform.playing, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  readerTest(
    'closing during initialization releases the decoder without a pending timeout',
    (tester) async {
      platform.delayInitialization = true;
      await show(tester, NexVideoPlayer(path: '/opening.mp4', onOpen: () {}));
      await tester.tap(find.byKey(const ValueKey('video-cover-play')));
      await tester.pump();
      await tester.pump();
      expect(platform.created, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(platform.disposed, [1]);
      expect(platform.playing, isEmpty);
    },
  );

  testWidgets(
    'unsupported desktop never allocates an unavailable player',
    (tester) async {
      await show(tester, NexVideoPlayer(path: '/clip.mp4', onOpen: () {}));
      await tester.tap(find.byKey(const ValueKey('video-cover-play')));
      await tester.pumpAndSettle();
      expect(platform.created, 0);
      expect(find.textContaining('cannot be shown'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  readerTest('changing a playing video releases the old decoder', (
    tester,
  ) async {
    await show(tester, NexVideoPlayer(path: '/first.mp4', onOpen: () {}));
    await tester.tap(find.byKey(const ValueKey('video-cover-play')));
    await tester.pumpAndSettle();
    await show(tester, NexVideoPlayer(path: '/second.mp4', onOpen: () {}));
    expect(platform.playing, isEmpty);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(platform.disposed, [1]);
    expect(platform.created, 1);
    await tester.tap(find.byKey(const ValueKey('video-cover-play')));
    await tester.pumpAndSettle();
    expect(platform.playing, {2});
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final language in ['en', 'fa']) {
    for (final dark in [false, true]) {
      readerTest(
        '$language ${dark ? 'dark' : 'light'} readers fit narrow width at 3.2 text scale',
        (tester) async {
          await show(
            tester,
            Column(
              children: [
                NexVideoPlayer(path: '/clip.mp4', onOpen: () {}),
                NexPdfReader(path: '/report.pdf', onOpen: () {}),
              ],
            ),
            language: language,
            dark: dark,
            scale: 3.2,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
