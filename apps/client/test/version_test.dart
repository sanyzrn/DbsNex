import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app_version.dart';

void main() {
  test('nexAppVersion matches pubspec.yaml', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    // pubspec allows a `+build` suffix; the release workflow compares the
    // semantic part against the tag, so that is what has to agree here too.
    final pubspec = line.split(':')[1].trim().split('+').first;
    expect(nexAppVersion, pubspec);
  });
}
