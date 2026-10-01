import 'dart:io';

import 'package:flutter/services.dart';

/// The phone a piece of feedback came from: the system and its version, and
/// the model.
///
/// A bug report that says "the keyboard covers the field" is two different
/// bugs on Android 10 and Android 15, and one that only happens on one
/// maker's phones is impossible to place without the name. Nothing that
/// identifies the person: no serial, no account, no install id.
typedef NexDeviceLabel = ({String platform, String? device});

/// Asks Android for its version and model; elsewhere, only the system name.
abstract final class NexDevice {
  static const _channel = MethodChannel('nex/os_capture');

  static NexDeviceLabel? _cached;

  static Future<NexDeviceLabel> describe() async {
    if (_cached case final label?) return label;
    final fallback = (platform: Platform.operatingSystem, device: null);
    if (!Platform.isAndroid) return _cached = fallback;
    try {
      final info = await _channel.invokeMapMethod<String, Object?>(
        'deviceInfo',
      );
      if (info == null) return fallback;
      return _cached = label(
        release: info['release'] as String?,
        manufacturer: info['manufacturer'] as String?,
        model: info['model'] as String?,
      );
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  /// "android 14" and "Samsung SM-S918B", short enough for the relay's
  /// limits (20 and 40 characters). The maker is left off a model that
  /// already starts with it, as Pixels and most Xiaomis do.
  static NexDeviceLabel label({
    String? release,
    String? manufacturer,
    String? model,
  }) {
    final version = release?.trim() ?? '';
    final platform = version.isEmpty ? 'android' : 'android $version';
    final maker = manufacturer?.trim() ?? '';
    final name = model?.trim() ?? '';
    final device = switch ((maker, name)) {
      (_, '') => maker,
      ('', _) => name,
      _ when name.toLowerCase().startsWith(maker.toLowerCase()) => name,
      _ => '${maker[0].toUpperCase()}${maker.substring(1)} $name',
    };
    return (
      platform: _clip(platform, 20),
      device: device.isEmpty ? null : _clip(device, 40),
    );
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);
}
