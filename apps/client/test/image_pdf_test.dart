import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/platform/image_pdf.dart';

void main() {
  test('a valid PDF: header, one page per image, an xref that points true', () {
    final picture = img.Image(width: 40, height: 60);
    img.fill(picture, color: img.ColorRgb8(255, 255, 255));
    final jpeg = Uint8List.fromList(img.encodeJpg(picture));
    final pdf = nexImagePdf([
      (jpeg: jpeg, width: 40, height: 60),
      (jpeg: jpeg, width: 40, height: 60),
    ]);
    final text = latin1.decode(pdf);
    expect(text.startsWith('%PDF-1.4'), isTrue);
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
    expect('/Type /Page '.allMatches(text), hasLength(2));
    expect(text, contains('/Count 2'));
    expect(text, contains('/Filter /DCTDecode'));

    // Every xref entry is the byte offset of the object it names.
    final xrefAt = int.parse(
      RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!,
    );
    expect(text.substring(xrefAt).startsWith('xref'), isTrue);
    final entries = RegExp(
      r'(\d{10}) 00000 n',
    ).allMatches(text.substring(xrefAt)).map((m) => int.parse(m.group(1)!));
    var number = 1;
    for (final offset in entries) {
      expect(text.substring(offset).startsWith('$number 0 obj'), isTrue);
      number++;
    }
    expect(number - 1, 2 + 2 * 3);
  });
}
