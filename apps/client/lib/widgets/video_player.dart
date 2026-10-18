import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';
import '../platform/route_observer.dart';
import '../platform/video_preview.dart';

/// Local video in Nex's reading surface. A decoder is created only after
/// Play; it pauses when covered or backgrounded and is released with the note.
class NexVideoPlayer extends StatefulWidget {
  const NexVideoPlayer({super.key, required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  State<NexVideoPlayer> createState() => _NexVideoPlayerState();
}

class _NexVideoPlayerState extends State<NexVideoPlayer>
    with WidgetsBindingObserver, RouteAware {
  static _NexVideoPlayerState? _active;
  VideoPlayerController? _controller;
  ModalRoute<void>? _route;
  Uint8List? _poster;
  bool _loading = false;
  bool _failed = false;
  bool _wantPlay = false;
  int _generation = 0;
  double? _scrub;
  Completer<void>? _cancelOpening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPoster());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (_route != route) {
      nexRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) nexRouteObserver.subscribe(this, route);
    }
    if (!TickerMode.of(context)) _pause();
  }

  @override
  void didUpdateWidget(NexVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path == widget.path) return;
    _retire();
    _poster = null;
    _loading = false;
    _failed = false;
    unawaited(_loadPoster());
  }

  Future<void> _loadPoster() async {
    final generation = _generation;
    final poster = await NexVideoPreview.poster(widget.path);
    if (mounted && generation == _generation) setState(() => _poster = poster);
  }

  void _retire() {
    ++_generation;
    _cancelOpening?.complete();
    _cancelOpening = null;
    _wantPlay = false;
    if (_active == this) _active = null;
    _scrub = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.pause().catchError((Object _) {}));
      unawaited(controller.dispose().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    nexRouteObserver.unsubscribe(this);
    _retire();
    super.dispose();
  }

  void _pause() {
    _wantPlay = false;
    if (_active == this) _active = null;
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.pause().catchError((Object _) {}));
    }
  }

  void _activate() {
    if (_active != this) _active?._pause();
    _active = this;
  }

  @override
  void didPushNext() => _pause();

  @override
  void didPop() => _pause();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  Future<void> _command(
    Future<void> Function(VideoPlayerController) action,
  ) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await action(controller);
    } on Object {
      if (mounted && _controller == controller) {
        _pause();
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (!NexVideoPreview.canPlay) {
      setState(() => _failed = true);
      return;
    }
    var controller = _controller;
    if (controller == null || _failed || controller.value.hasError) {
      _retire();
      final generation = _generation;
      _wantPlay = true;
      _activate();
      controller = VideoPlayerController.file(File(widget.path));
      _controller = controller;
      final cancelled = Completer<void>();
      _cancelOpening = cancelled;
      setState(() {
        _loading = true;
        _failed = false;
      });
      try {
        await Future.any([
          controller.initialize(),
          cancelled.future,
        ]).timeout(const Duration(seconds: 20));
        if (!mounted || generation != _generation) return;
        _cancelOpening = null;
        setState(() => _loading = false);
        // Backgrounding or covering the sheet while opening must not cause
        // delayed playback when the initialization eventually completes.
        if (_wantPlay) await _command((player) => player.play());
      } on Object {
        if (mounted && generation == _generation) {
          _retire();
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
      }
      return;
    }
    _wantPlay = !controller.value.isPlaying;
    if (!_wantPlay) {
      await _command((player) => player.pause());
    } else {
      _activate();
      await _command((player) async {
        if (player.value.position >= player.value.duration) {
          await player.seekTo(Duration.zero);
        }
        if (_wantPlay) await player.play();
      });
    }
  }

  String _clock(Duration value, bool persian) {
    final seconds = value.inSeconds;
    final hours = seconds ~/ 3600;
    return nexDigits(
      '${hours > 0 ? '$hours:' : ''}${hours > 0 ? (seconds ~/ 60 % 60).toString().padLeft(2, '0') : seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
      persian: persian,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _card(context, null);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => _card(context, value),
    );
  }

  Widget _card(BuildContext context, VideoPlayerValue? value) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final ready = value?.isInitialized == true;
    final failed = _failed || value?.hasError == true;
    final playing = value?.isPlaying == true;
    final speed = value?.playbackSpeed ?? 1;
    final speedLabel = speed == speed.roundToDouble()
        ? '${speed.round()}'
        : '$speed';
    final duration = value?.duration ?? Duration.zero;
    final whole = duration.inMilliseconds;
    final at = _scrub ?? (value?.position.inMilliseconds ?? 0).toDouble();
    final tooltip = playing ? l10n.pauseVideo : l10n.playVideo;
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Material(
        key: const ValueKey('inline-video'),
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final ratio = ready ? value!.aspectRatio : 16 / 9;
                return SizedBox(
                  height: (constraints.maxWidth / (ratio > 0 ? ratio : 16 / 9))
                      .clamp(180.0, 420.0),
                  child: Stack(
                    alignment: Alignment.center,
                    fit: StackFit.expand,
                    children: [
                      if (ready && !failed)
                        Center(
                          child: AspectRatio(
                            aspectRatio: ratio > 0 ? ratio : 16 / 9,
                            child: VideoPlayer(_controller!),
                          ),
                        )
                      else if (_poster != null)
                        Image.memory(
                          _poster!,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        )
                      else
                        Icon(
                          Icons.movie_outlined,
                          size: 48,
                          color: scheme.onSurfaceVariant,
                        ),
                      if (!playing)
                        Center(
                          child: IconButton.filled(
                            key: const ValueKey('video-cover-play'),
                            tooltip: failed ? l10n.retry : tooltip,
                            onPressed: _loading
                                ? null
                                : () => unawaited(_toggle()),
                            iconSize: 40,
                            padding: const EdgeInsets.all(NexSpacing.md),
                            icon: Icon(
                              _loading
                                  ? Icons.hourglass_top_rounded
                                  : failed
                                  ? Icons.refresh
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (failed)
              Padding(
                padding: const EdgeInsets.all(NexSpacing.md),
                child: Text(
                  l10n.inlineMediaUnavailable,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
              child: Wrap(
                spacing: NexSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton.filledTonal(
                    key: const ValueKey('video-play'),
                    tooltip: tooltip,
                    onPressed: _loading ? null : () => unawaited(_toggle()),
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                  ),
                  Text(
                    '${_clock(Duration(milliseconds: at.round()), persian)} / ${_clock(duration, persian)}',
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('video-speed'),
                    onPressed: !ready || failed
                        ? null
                        : () => unawaited(
                            _command(
                              (player) => player.setPlaybackSpeed(
                                value!.playbackSpeed < 1.5
                                    ? 1.5
                                    : value.playbackSpeed < 2
                                    ? 2
                                    : 1,
                              ),
                            ),
                          ),
                    child: Text(nexDigits('$speedLabel×', persian: persian)),
                  ),
                  IconButton(
                    tooltip: (value?.volume ?? 1) > 0
                        ? l10n.muteVideo
                        : l10n.unmuteVideo,
                    onPressed: !ready || failed
                        ? null
                        : () => unawaited(
                            _command(
                              (player) => player.setVolume(
                                player.value.volume > 0 ? 0 : 1,
                              ),
                            ),
                          ),
                    icon: Icon(
                      (value?.volume ?? 1) > 0
                          ? Icons.volume_up_outlined
                          : Icons.volume_off_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.openInOtherApp,
                    onPressed: widget.onOpen,
                    icon: const Icon(Icons.open_in_new),
                  ),
                ],
              ),
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Slider(
                key: const ValueKey('video-seek'),
                min: 0,
                max: whole > 0 ? whole.toDouble() : 1,
                value: at.clamp(0, whole > 0 ? whole.toDouble() : 1),
                semanticFormatterCallback: (value) =>
                    _clock(Duration(milliseconds: value.round()), persian),
                onChanged: !ready || failed || whole <= 0
                    ? null
                    : (value) => setState(() => _scrub = value),
                onChangeEnd: !ready || failed || whole <= 0
                    ? null
                    : (value) {
                        setState(() => _scrub = null);
                        unawaited(
                          _command(
                            (player) => player.seekTo(
                              Duration(milliseconds: value.round()),
                            ),
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
