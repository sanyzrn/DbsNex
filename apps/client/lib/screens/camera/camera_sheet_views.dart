part of '../camera_sheet.dart';

extension _NexCameraViews on _NexCameraSheetState {
  Widget _videoStatus(BuildContext context, MediaQueryData media) {
    final l10n = AppLocalizations.of(context);
    final recording = _recording || _startingVideo;
    final clock = nexDigits(
      nexCameraClock(_elapsed),
      persian: l10n.localeName == 'fa',
    );
    final note = switch (_noticeKind) {
      _Notice.tooShort => l10n.cameraVideoTooShort,
      _Notice.tooLarge => l10n.cameraVideoTooLarge,
      _Notice.failed => l10n.captureFailed,
      null => _silentVideo ? l10n.cameraSilentVideo : null,
    };
    return Positioned(
      left: NexSpacing.md,
      right: NexSpacing.md,
      top: media.viewPadding.top + NexSpacing.sm,
      child: IgnorePointer(
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: NexMotion.of(context, NexMotion.fast),
              child: recording
                  ? Semantics(
                      key: const ValueKey('camera-recording-clock'),
                      liveRegion: true,
                      label: l10n.cameraRecordingElapsed(clock),
                      excludeSemantics: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexSpacing.sm,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(NexRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _RecordingDot(),
                            const SizedBox(width: NexSpacing.xs),
                            Text(
                              clock,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            if (_silentVideo) ...[
                              const SizedBox(width: NexSpacing.xs),
                              const Icon(
                                Icons.mic_off_outlined,
                                color: Colors.white70,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : Text(
                      note ?? l10n.cameraHoldForVideo,
                      key: ValueKey(note == null ? 'hint' : 'note'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: note == null ? .6 : .9,
                        ),
                        fontSize: 13,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      // Not reached when the camera has failed: [_unavailable] takes the
      // panel then. This is the wait — faint, and saying so.
      return _failed ? const SizedBox.expand() : _waiting(context);
    }
    // previewSize is in the sensor's landscape terms. On a phone the panel is
    // portrait; on a large screen it is whichever way the device is held.
    final size = controller.value.previewSize;
    final landscape =
        nexLargeScreen(MediaQuery.sizeOf(context)) &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final long = size?.width ?? 4;
    final short = size?.height ?? 3;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: landscape ? long : short,
          height: landscape ? short : long,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  /// The panel while the sensor is still being asked for: a skeleton in
  /// its own dimness and the words, in the same voice the microphone
  /// permission speaks in. Six seconds in, the system camera is offered
  /// here rather than only after the timeout has already eaten the wait.
  Widget _waiting(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.xl,
        NexSpacing.xl,
        NexSpacing.xl,
        120,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_camera_outlined,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 40,
                ),
                const SizedBox(height: NexSpacing.md),
                // The skeleton: the panel's own shape, ghosted, where the picture
                // is about to be.
                Container(
                  width: 132,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(NexRadius.md),
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                Text(
                  l10n.cameraStarting,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                if (_offerSystemCamera) ...[
                  const SizedBox(height: NexSpacing.md),
                  FilledButton.tonal(
                    onPressed: () =>
                        Navigator.of(context).pop(_useSystemCamera),
                    child: Text(l10n.cameraUseSystem),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _unavailable(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.xl,
        NexSpacing.xl,
        NexSpacing.xl,
        120,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white70,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.cameraUnavailable,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: NexSpacing.md),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(_useSystemCamera),
            child: Text(l10n.cameraUseSystem),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, double bottomInset) {
    final l10n = AppLocalizations.of(context);
    return Positioned.fill(
      left: 20,
      right: 20,
      bottom: bottomInset + 20,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RoundButton(
                tooltip: l10n.cameraClose,
                onPressed: _close,
                // chevron_left mirrors itself under RTL; swapping it here
                // as well flipped it twice (LOC-10).
                child: const Icon(Icons.chevron_left, size: 28),
              ),
              _Shutter(
                label: _recording
                    ? l10n.cameraStopRecording
                    : l10n.cameraShutter,
                holdLabel: widget.video ? l10n.cameraHoldForVideo : null,
                enabled: _controller != null && !_taking,
                recording: _recording || _startingVideo,
                onPressed: _recording ? () => unawaited(_stopVideo()) : _take,
                onHoldStart: widget.video
                    ? () => unawaited(_startVideo())
                    : null,
                onHoldEnd: widget.video ? () => unawaited(_stopVideo()) : null,
              ),
              if (_recording || _startingVideo)
                // While recording the only choice that matters is the one
                // that stops it, and it is here as well as on the shutter so
                // the gesture is not the only way.
                _RoundButton(
                  tooltip: l10n.cameraStopRecording,
                  onPressed: () => unawaited(_stopVideo()),
                  child: const Icon(Icons.stop_rounded),
                )
              else
                _RoundButton(
                  tooltip: l10n.cameraOptions,
                  onPressed: () => _set(() => _menuOpen = !_menuOpen),
                  child: const Icon(Icons.more_vert),
                ),
            ],
          ),
          // Above the ⋮ button it belongs to.
          PositionedDirectional(
            end: 0,
            bottom: 90,
            child: IgnorePointer(
              ignoring: !_menuOpen,
              child: AnimatedScale(
                scale: _menuOpen ? 1 : .8,
                alignment: Directionality.of(context) == TextDirection.rtl
                    ? Alignment.bottomLeft
                    : Alignment.bottomRight,
                duration: NexMotion.of(context, NexMotion.standard),
                curve: NexMotion.curve,
                child: AnimatedOpacity(
                  opacity: _menuOpen ? 1 : 0,
                  duration: NexMotion.of(context, NexMotion.fast),
                  child: _Menu(
                    children: [
                      _MenuItem(
                        icon: Icons.photo_library_outlined,
                        label: l10n.cameraGallery,
                        onTap: () => unawaited(_pickFromGallery()),
                      ),
                      if (widget.video && _controller != null)
                        _MenuItem(
                          icon: Icons.videocam_outlined,
                          label: l10n.cameraRecordVideo,
                          onTap: () {
                            _set(() => _menuOpen = false);
                            unawaited(_startVideo());
                          },
                        ),
                      if (widget.cameras.length > 1)
                        _MenuItem(
                          icon: Icons.cameraswitch_outlined,
                          label: l10n.cameraSwitch,
                          onTap: _switchCamera,
                        ),
                      _MenuItem(
                        icon: switch (_lastFlash) {
                          FlashMode.auto => Icons.flash_auto,
                          FlashMode.always => Icons.flash_on,
                          _ => Icons.flash_off,
                        },
                        label: switch (_lastFlash) {
                          FlashMode.auto => l10n.cameraFlashAuto,
                          FlashMode.always => l10n.cameraFlashOn,
                          _ => l10n.cameraFlashOff,
                        },
                        onTap: _cycleFlash,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
