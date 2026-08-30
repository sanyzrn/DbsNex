/// The app's semantic version, single-sourced for the UI.
///
/// It used to be typed out separately in each place the About screen showed it,
/// so a release bump silently left the version the user could actually read
/// pointing at the previous release. `version_test.dart` fails the build if
/// this and `pubspec.yaml` ever drift apart again.
const nexAppVersion = '1.3.1';
