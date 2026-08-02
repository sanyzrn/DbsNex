import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Dart half of the home-screen widget pipeline.
///
/// The heavy lifting is done by [WidgetSnapshotStore] — a JSON file in the
/// app's own directory that the Android widget providers read directly. This
/// class only carries the "something changed, repaint" signal to the native
/// side, where `AppWidgetManager` fans it out to every placed instance.
class NexWidgetsBridge {
  NexWidgetsBridge();

  static const _channel = MethodChannel('nex/widgets');

  /// Only Android registers `nex/widgets`; the whole widget system is an
  /// Android concept.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Asks Android to repaint every placed widget from the latest snapshot.
  ///
  /// Fire-and-forget on purpose: a widget that repaints a second late is
  /// invisible, while a capture path that waited on a platform channel is
  /// not. Nothing here may ever throw into the timeline.
  void notifyChanged() {
    if (!isSupported) return;
    unawaited(
      _channel.invokeMethod<void>('refresh').catchError((Object _) {}),
    );
  }
}
