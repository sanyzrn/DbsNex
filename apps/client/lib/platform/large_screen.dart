import 'dart:ui' show Size;

/// The smallest width, in logical pixels, from which Android treats a screen
/// as large: tablets, unfolded foldables, desktop windows.
///
/// It matters because of what Android 16 does there for an app targeting
/// API 36. A fixed orientation (`android:screenOrientation`, and
/// `SystemChrome.setPreferredOrientations`) is honoured on a phone and
/// ignored on a large screen, so a large screen can be in landscape however
/// the app asks. Code that assumed "the app is always portrait" asks this
/// first.
const nexLargeScreenMinWidth = 600.0;

/// Whether a window of [size] is on a large screen in Android's sense.
bool nexLargeScreen(Size size) => size.shortestSide >= nexLargeScreenMinWidth;
