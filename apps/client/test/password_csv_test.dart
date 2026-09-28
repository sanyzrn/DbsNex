import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/password_csv.dart';

void main() {
  test(
    'quoted fields and multiline notes round-trip without trimming passwords',
    () {
      final e = parsePasswordCsv(
        '\ufeffname,url,username,password,note\r\n"حساب, یک",https://example.test,u," p""ass ","line 1\nline 2"\r\n',
      ).single;
      expect(e.title, 'حساب, یک');
      expect(e.value('password'), ' p"ass ');
      expect(e.value('notes'), 'line 1\nline 2');
    },
  );
  test('malformed or unsupported exports are rejected before a write', () {
    for (final s in [
      'name,url\na,b',
      'url,username,password\nx,u,"open',
      'url,username,password\nx,u,',
    ]) {
      expect(() => parsePasswordCsv(s), throwsFormatException);
    }
  });
}
