import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/screens/camera_sheet.dart';

/// The clock the recording badge shows, and the two lengths that decide what
/// happens to a hold. The gesture itself needs a sensor; these are the parts
/// of it that can be wrong without one, and the parts a device test would
/// otherwise have to hold a phone for.
void main() {
  test('the recording clock pads minutes and seconds, and keeps counting', () {
    expect(nexCameraClock(Duration.zero), '00:00');
    expect(nexCameraClock(const Duration(seconds: 7)), '00:07');
    expect(nexCameraClock(const Duration(seconds: 65)), '01:05');
    expect(nexCameraClock(const Duration(minutes: 3)), '03:00');
    // Past an hour the minutes keep growing rather than wrapping to 00.
    expect(nexCameraClock(const Duration(minutes: 125, seconds: 4)), '125:04');
  });

  test('a slip of the thumb is shorter than a held video can be', () {
    expect(NexCameraSheet.minVideo, lessThan(NexCameraSheet.maxVideo));
    expect(NexCameraSheet.minVideo.inMilliseconds, greaterThan(0));
    // Long enough that the sensor has started, short enough not to feel like
    // a wait.
    expect(NexCameraSheet.minVideo.inMilliseconds, lessThanOrEqualTo(1500));
    // Three minutes of 1080p stays far inside the 500 MiB attachment limit.
    expect(NexCameraSheet.maxVideo, const Duration(minutes: 3));
  });

  test('a hold that becomes a recording starts before a tap would end', () {
    // The shutter's hold threshold is shorter than the shortest kept video:
    // a press that starts recording always reaches the length that is kept.
    expect(NexCameraSheet.minVideo.inMilliseconds, greaterThan(280));
  });
}
