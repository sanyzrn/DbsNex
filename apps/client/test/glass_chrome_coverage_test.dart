import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary screens and modules use the shared glass chrome', () {
    const opticalEditors = {
      'camera_sheet.dart',
      'photo_annotate_screen.dart',
      'photo_crop_screen.dart',
      'photo_preview_screen.dart',
      'photo_viewer_screen.dart',
    };
    final problems = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      final name = file.uri.pathSegments.last;
      if (!opticalEditors.contains(name) &&
          RegExp(r'(?<![\w])AppBar\(').hasMatch(source)) {
        problems.add('${file.path}: use NexAppBar');
      }
      if (RegExp(r'(?<![\w])AlertDialog\(').hasMatch(source)) {
        problems.add('${file.path}: use NexAlertDialog');
      }
      if (RegExp(r'(?<![\w])PopupMenuButton[<(]').hasMatch(source)) {
        problems.add('${file.path}: use NexPopupMenuButton');
      }
    }
    expect(problems, isEmpty);
  });
}
