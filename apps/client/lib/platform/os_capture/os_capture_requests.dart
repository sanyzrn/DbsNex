part of '../os_capture_bridge.dart';

// What the OS hands Nex: the kinds of request, and the request itself.
// Split out of os_capture_bridge.dart (REL-10).

/// An OS surface asking Nex to do something on the timeline once there is a
/// timeline: the Capture widget's tap, or a Timeline widget row asking for
/// the note it shows (FR-8.1 / ADR-027).
///
/// Delivered in one of the two worlds a share arrives in, and for the same
/// reason: live, while a screen is listening, or during bootstrap, before any
/// screen exists — in which case it waits for [OsCaptureBridge.takeRequest].
/// The reminder launch path has this exact shape already.
/// What the OS asked for.
///
/// An enum rather than a pair of booleans, which is what this was: three
/// kinds fit in two flags only by accident, and the fourth — "just bring the
/// timeline up" — is the one that showed it. Every arm is named, so adding
/// another means the switch in [OsCaptureBridge._dispatch] stops compiling
/// rather than silently falling through to "open a note" with no note.
enum PendingOsRequestKind {
  /// The Capture widget's tile: open the capture sheet (FR-8.1).
  capture,

  /// A Timeline widget row: open the note it is showing.
  openNote,

  /// The Recap widget's refresh button: write a new brief.
  refreshRecap,

  /// A plain tap on a widget — its header, or its background.
  ///
  /// It carries no errand beyond "be the app", and it used to carry no
  /// payload either: the intent had no action, so Dart was never told it had
  /// happened. Android then did what it does for any launch of a running
  /// task — it brought the task back exactly as it was left. Somebody who had
  /// last been in Settings tapped the brief on their home screen and arrived
  /// in Settings, which is a perfectly reasonable thing for Android to do and
  /// not at all what the tap meant.
  openTimeline,

  /// A tap on one of the Cycle widgets: open «Cycle», behind the app lock
  /// like everything else.
  openCycle,
}

/// Which capture a quick-capture notification button asked for (W5.2).
///
/// The widget and the Quick Settings tile carry none and open the capture
/// sheet; the notification's buttons skip the sheet and go straight to the
/// kind they name.
enum OsCaptureMode {
  text,
  voice,
  photo,

  /// A photo already taken — the Timeline widget's gallery button.
  gallery,

  /// The Timeline widget's checklist button.
  checklist;

  static OsCaptureMode? fromWire(Object? value) => switch (value) {
    'text' => text,
    'voice' => voice,
    'photo' => photo,
    'gallery' => gallery,
    'checklist' => checklist,
    _ => null,
  };
}

/// One of those requests, with whatever it carries.
class PendingOsRequest {
  const PendingOsRequest.capture([this.captureMode])
    : kind = PendingOsRequestKind.capture,
      noteId = null;

  const PendingOsRequest.openNote(String this.noteId)
    : kind = PendingOsRequestKind.openNote,
      captureMode = null;

  /// The Recap widget's refresh button, which is a request to open the app.
  ///
  /// It cannot be anything else. Writing a new brief means asking a model,
  /// and a widget provider is a broadcast receiver with no Flutter engine
  /// behind it and about ten seconds to live — there is nothing in that
  /// process that could produce a sentence. So the button does the honest
  /// version of what it looks like it does: it opens Nex, the timeline
  /// re-asks the way its own refresh button does, and the new brief lands on
  /// the home screen through the snapshot a moment later.
  const PendingOsRequest.refreshRecap()
    : kind = PendingOsRequestKind.refreshRecap,
      noteId = null,
      captureMode = null;

  const PendingOsRequest.openTimeline()
    : kind = PendingOsRequestKind.openTimeline,
      noteId = null,
      captureMode = null;

  const PendingOsRequest.openCycle()
    : kind = PendingOsRequestKind.openCycle,
      noteId = null,
      captureMode = null;

  final PendingOsRequestKind kind;

  /// The note to open. Non-null exactly when [kind] is
  /// [PendingOsRequestKind.openNote].
  final String? noteId;

  /// For a capture: the kind a notification button named, or null for the
  /// capture sheet.
  final OsCaptureMode? captureMode;

  bool get isCapture => kind == PendingOsRequestKind.capture;

  bool get isRecapRefresh => kind == PendingOsRequestKind.refreshRecap;
}

/// What was refused, and how big it was.
///
/// Carries the numbers rather than a finished sentence: the message is
/// localised, and the file's own size is what makes the refusal make sense
/// instead of sounding arbitrary.
class RejectedShare {
  const RejectedShare({
    required this.filename,
    required this.bytes,
    required this.limit,
  });

  final String filename;
  final int bytes;

  /// The limit in force, carried along so the message can name it without
  /// reaching back to the bridge for a number it already knew.
  final int limit;
}
