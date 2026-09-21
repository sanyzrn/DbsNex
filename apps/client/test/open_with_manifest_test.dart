import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whether Nex appears in the list of apps offering to open a markdown file.
///
/// Nothing in Dart can answer that. It is decided entirely by the intent
/// filters in the Android manifest, which nothing else in this repository
/// reads — so the one thing that can go wrong silently is somebody tidying
/// the manifest and taking the answer away with them.
///
/// Deliberately a test about the declaration rather than about the behaviour:
/// the behaviour needs a device and a file manager. What this holds is that
/// the claim is still being made, and made for the three cases that matter.
void main() {
  late String manifest;

  setUpAll(() {
    // Relative to `apps/client`, which is where `flutter test` runs from.
    manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
  });

  test('Nex offers to open a markdown file', () {
    expect(manifest, contains('android.intent.action.VIEW'));
    expect(manifest, contains('android:mimeType="text/markdown"'));
    expect(manifest, contains('android:mimeType="text/x-markdown"'));
  });

  test('and the type most .md files actually arrive as', () {
    // The load-bearing one. Most things that hand over a .md — Telegram's
    // "Open in" among them — type it as plain text, so a filter without this
    // would miss the common case while looking like it covered everything.
    expect(manifest, contains('android:mimeType="text/plain"'));
  });

  test('and the ones that arrive with no useful type at all', () {
    // A filter carrying a pathPattern only matches an intent whose type also
    // matches, which is why this is a second filter rather than three more
    // lines in the first.
    expect(manifest, contains(r'android:pathPattern=".*\\.md"'));
    expect(manifest, contains('android:mimeType="application/octet-stream"'));
  });

  test('from both of the schemes a file can arrive on', () {
    // content:// is what a modern provider hands over; file:// is what the
    // older file managers still send.
    expect(manifest, contains('android:scheme="content"'));
    expect(manifest, contains('android:scheme="file"'));
  });
}
