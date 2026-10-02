import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled fonts travel with their SIL OFL 1.1 text (REL-08): it is an
/// asset, so the licence page can show it on a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (font, path) in [
    ('Inter', 'third_party/Inter-OFL.txt'),
    ('Vazirmatn', 'third_party/Vazirmatn-OFL.txt'),
  ]) {
    test('$font ships its OFL text', () async {
      final text = await rootBundle.loadString(path);
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(text, contains('The $font Project Authors'));
    });
  }
}
