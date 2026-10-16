# 2.0.6 experimental native-editor magnifier

This uses Flutter's existing `TextMagnifier`, with a native geometry/touch adapter.
No extra Flutter dependency, editor replacement or root renderer change is involved.
The first test device is the owner's Android phone; no device run is claimed yet.

## Phone checks

1. Open a multiline note containing Persian, English, punctuation and empty lines.
   Long-press a word, then drag each selection handle and the collapsed caret.
   The lens should contain the actual text, follow the active line and stay on screen.
2. Hold still during a drag for several seconds, cross wrapped lines and scroll a
   long note with a handle. Check both ends and both text directions.
3. Test capture, editing, a caption, assistant input and a private message. Verify
   Copy/Cut/formatting and keyboard behavior. Private text stays inside the app.
4. Release/cancel the gesture, type, close the keyboard, open another route, rotate
   the phone and background the app. No lens should remain floating afterward.
5. Try light/dark themes and large system text. Watch for an empty or second
   Android lens, displaced handles, flicker or new lag. Record the screen and note
   Android version/device if any occur.

## Known compatibility boundary

Direct editor gestures use the existing native touch/selection callbacks. On
Android 10+, stock AOSP popup handles are observed through public `WindowInspector`
window enumeration. This relies on framework handle class identities; unrecognized
OEM handles are not intercepted. Android 8/9 have no popup-handle observation.

Suppressing Android's own lens uses AOSP's rotation guard: a 360-degree identity
rotation during native touch dispatch, restored in `finally` before drawing. This
is an experimental compatibility workaround, not a supported opt-out API. An OEM
change could cause a missing or duplicate lens; device validation remains required.

Disable with `NexTextField.flutterMagnifier = false` and rebuild if needed. The
native protocol receives the same flag, so both halves turn off together.

## Verification performed locally

- Native-editor protocol/widget regression suite: 23 tests passed, including
  the four new magnifier cases.
- The complete client suite and final analysis are delegated to GitHub CI after
  a local Flutter bootstrap was stopped by automatic execution review.
- Kotlin compilation of `NexEditText.kt` and `NexMagnifierBridge.kt`, against the
  Android 15 API implementation jar and Flutter 3.35.5 embedding.
- No claim of a full APK build, native touch execution or device frame timing.

## Existing upstream components

- [Flutter TextMagnifier](https://api.flutter.dev/flutter/material/TextMagnifier-class.html)
- [Android WindowInspector](https://developer.android.com/reference/android/view/inspector/WindowInspector)
- [AOSP Android 15 Editor](https://github.com/aosp-mirror/platform_frameworks_base/blob/android-15.0.0_r1/core/java/android/widget/Editor.java)
