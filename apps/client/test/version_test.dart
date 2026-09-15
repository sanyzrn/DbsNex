import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app_version.dart';

/// The version the repository states about itself, and the one place it is
/// allowed to be stated from.
///
/// `release.yml` treats the **tag** as the single source of truth: before it
/// builds, it stamps `pubspec.yaml` and `app_version.dart` from the tag, so
/// what is checked in never reaches a user. That is a good design and it had
/// one unwatched consequence — nothing needed the checked-in numbers to be
/// right, so they stopped being. They sat at 1.3.2 for nine releases, and
/// everything that reads the repository without running a release build read
/// 1.3.2: a contributor, a code-reading assistant, and anyone who installed a
/// debug build and looked at About.
///
/// So the numbers are now pinned to something that does move: the newest
/// released section of the changelog. The stamp in the workflow stays, as the
/// belt to this file's braces.
void main() {
  /// The repository root, from the package directory tests run in.
  String rootFile(String name) => File('../../$name').readAsStringSync();

  String pubspecVersion() {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    // pubspec allows a `+build` suffix; the release workflow compares the
    // semantic part against the tag, so that is what has to agree here too.
    return line.split(':')[1].trim().split('+').first;
  }

  test('nexAppVersion matches pubspec.yaml', () {
    expect(nexAppVersion, pubspecVersion());
  });

  test('the version is the newest release the changelog names', () {
    // By name, not by position — the same rule `release.yml` reads the file
    // by, and for the same reason: the file opens with a prose section that
    // is itself a `## ` heading, and carries a fresh `## Unreleased` above
    // the newest release.
    final newest = rootFile('CHANGELOG.md')
        .split('\n')
        .map((line) => RegExp(r'^## v(\d+\.\d+\.\d+)$').firstMatch(line))
        .nonNulls
        .first
        .group(1);
    expect(
      pubspecVersion(),
      newest,
      reason:
          'Cutting a release renames "## Unreleased" to "## vX.Y.Z"; bump '
          'pubspec.yaml and lib/app_version.dart in the same commit.',
    );
  });

  test('the changelog the app ships is the changelog in the repository', () {
    // `assets/CHANGELOG.md` is a byte-for-byte copy — the update sheet and
    // the history screen read the shipped one, and a release published from
    // the root file while the app showed a stale copy would be two different
    // accounts of the same version. Checked here because the alternative is
    // remembering to `cmp` them by hand on every release, which is exactly
    // the kind of promise this file exists to stop relying on.
    expect(
      File('assets/CHANGELOG.md').readAsStringSync(),
      rootFile('CHANGELOG.md'),
      reason: 'cp CHANGELOG.md apps/client/assets/CHANGELOG.md',
    );
  });
}
