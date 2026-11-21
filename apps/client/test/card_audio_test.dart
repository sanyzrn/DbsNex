import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:nex_client/widgets/card_audio.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;

/// A player that opens slowly, so a second tap can arrive while the first
/// one is still on its way — the race the request token exists for.
class _FakePlayer implements AudioPlayerPlatform {
  _FakePlayer(this.id, this.platform);

  @override
  final String id;
  final _FakeAudioPlatform platform;
  final _events = StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      const Stream<PlayerDataMessage>.empty();

  // Activated before a source is loaded, each with its own response type:
  // a bare Future fails the forwarder's cast and aborts the load.
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async => SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
    SetShuffleOrderRequest request,
  ) async => SetShuffleOrderResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
  setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async =>
      DisposeResponse();

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    await platform.holdLoads?.future;
    _events.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: const Duration(seconds: 30),
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ),
    );
    return LoadResponse(duration: const Duration(seconds: 30));
  }

  /// Everything this test never reaches — playlists, effects, web sinks.
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();

  void close() => unawaited(_events.close());
}

class _FakeAudioPlatform extends JustAudioPlatform {
  final players = <_FakePlayer>[];
  final disposed = <String>[];

  /// Holds every load open until the test says otherwise.
  Completer<void>? holdLoads;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = _FakePlayer(request.id, this);
    players.add(player);
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    disposed.add(request.id);
    for (final player in players) {
      if (player.id == request.id) player.close();
    }
    return DisposePlayerResponse();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late _FakeAudioPlatform platform;
  late JustAudioPlatform original;

  setUp(() {
    original = JustAudioPlatform.instance;
    platform = _FakeAudioPlatform();
    JustAudioPlatform.instance = platform;
    tmp = Directory.systemTemp.createTempSync('nex_card_audio_');
  });

  tearDown(() async {
    await NexCardAudio.instance.stop();
    JustAudioPlatform.instance = original;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note recording(String path) => Note(
    id: 'recording',
    type: NoteType.voice,
    mediaUri: path,
    mediaHash: 'hash',
    durationMs: 30000,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.synced,
  );

  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 500 && !ready(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a second tap while the first is opening leaves one player', () async {
    final file = File(p.join(tmp.path, 'memo.m4a'))
      ..writeAsBytesSync(const [1, 2, 3]);
    final note = recording(file.path);
    final audio = NexCardAudio.instance;
    platform.holdLoads = Completer<void>();

    final first = audio.toggle(note);
    await until(() => platform.players.isNotEmpty);
    expect(platform.players, hasLength(1), reason: 'the first load is open');

    // The same tap again, before the first player can say it is ready.
    final second = audio.toggle(note);
    await until(() => platform.players.length >= 2);
    expect(platform.players, hasLength(2), reason: 'both opened');

    platform.holdLoads!.complete();
    await Future.wait([first, second]);

    // The player the second tap superseded is let go, not left playing under
    // an unreachable reference.
    expect(platform.disposed, [platform.players.first.id]);
    expect(audio.noteId, note.id);
    expect(audio.loading, isFalse);
    expect(audio.isPlaying(note.id), isTrue);
  });
}
