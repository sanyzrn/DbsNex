import 'dart:io';

import 'package:flutter/services.dart';

/// A folder picked for automatic backups (W1.6), and the Android calls behind
/// it — see `NexBackupFolder.kt`.
///
/// Android only: the folder is a Storage Access Framework tree, which can be
/// on the phone or one a cloud or sync app (Google Drive, Nextcloud,
/// Syncthing) offers in the system picker.
class NexBackupFolderChannel {
  const NexBackupFolderChannel();

  static const _channel = MethodChannel('nex/os_capture');

  /// How many of Nex's own automatic backups the folder keeps.
  static const keep = 3;

  bool get supported => Platform.isAndroid;

  /// Opens the system folder picker. Null when nothing was picked.
  Future<({String uri, String name})?> pick() async {
    try {
      final picked = await _channel.invokeMapMethod<String, String>(
        'pickBackupFolder',
      );
      final uri = picked?['uri'];
      if (uri == null) return null;
      return (uri: uri, name: picked?['name'] ?? '');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Whether Nex can still write there: the grant can be taken away in
  /// Android's settings, or the app that offered the folder uninstalled.
  Future<bool> reachable(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('backupFolderReachable', {
            'uri': uri,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> release(String uri) async {
    try {
      await _channel.invokeMethod<void>('releaseBackupFolder', {'uri': uri});
    } on PlatformException {
      // Nothing to give back.
    } on MissingPluginException {
      // Not on Android.
    }
  }

  /// Copies [path] into the folder as [name]. Null when it landed, otherwise
  /// what went wrong, as the Android side put it.
  Future<String?> copy(String uri, String path, String name) async {
    try {
      final answer = await _channel.invokeMethod<String>('copyToBackupFolder', {
        'uri': uri,
        'path': path,
        'name': name,
        'keep': keep,
      });
      return answer == 'ok' ? null : (answer ?? 'no answer');
    } on PlatformException catch (error) {
      return 'platform: ${error.code}';
    } on MissingPluginException {
      return 'not available on this device';
    }
  }
}

/// The file name of an automatic backup: sortable, so the newest is last.
String nexAutoBackupName(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  final t = at.toUtc();
  return 'Nex-auto-${t.year}-${two(t.month)}-${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}.nexfull';
}
