import 'dart:convert';
import 'dart:typed_data';

/// A PDF whose pages are JPEG images, each scaled to the page width.
///
/// For reports Nex lays out itself: the page is drawn by Flutter — Persian
/// shaped and right-to-left, in the app's own fonts — and captured, so the
/// PDF looks exactly like the screen. A PDF text layer would need a font
/// embedded and Persian shaped by hand, and is not what a doctor reading a
/// one-page summary needs. The format here is the plain PDF 1.4 that every
/// viewer and printer reads: one image XObject per page and a one-line
/// content stream that draws it.
Uint8List nexImagePdf(
  List<({Uint8List jpeg, int width, int height})> pages, {
  double pageWidth = 595.28,
  double pageHeight = 841.89,
}) {
  final out = BytesBuilder(copy: false);
  final offsets = <int>[];
  void write(String text) => out.add(latin1.encode(text));
  void object(int number, void Function() body) {
    offsets.add(out.length);
    write('$number 0 obj\n');
    body();
    write('\nendobj\n');
  }

  // 1: catalog, 2: page tree, then three objects per page.
  final kids = [for (var i = 0; i < pages.length; i++) '${3 + i * 3} 0 R'];
  write('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  object(1, () => write('<< /Type /Catalog /Pages 2 0 R >>'));
  object(
    2,
    () => write(
      '<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>',
    ),
  );
  String n(double v) => v.toStringAsFixed(2);
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final pageObj = 3 + i * 3;
    final imageObj = pageObj + 1;
    final contentObj = pageObj + 2;
    final drawnHeight = pageWidth * page.height / page.width;
    final top = pageHeight - drawnHeight;
    final content = latin1.encode(
      'q ${n(pageWidth)} 0 0 ${n(drawnHeight)} 0 ${n(top)} cm /Im0 Do Q',
    );
    object(
      pageObj,
      () => write(
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${n(pageWidth)} ${n(pageHeight)}] '
        '/Resources << /XObject << /Im0 $imageObj 0 R >> >> '
        '/Contents $contentObj 0 R >>',
      ),
    );
    object(imageObj, () {
      write(
        '<< /Type /XObject /Subtype /Image /Width ${page.width} '
        '/Height ${page.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 '
        '/Filter /DCTDecode /Length ${page.jpeg.length} >>\nstream\n',
      );
      out.add(page.jpeg);
      write('\nendstream');
    });
    object(contentObj, () {
      write('<< /Length ${content.length} >>\nstream\n');
      out.add(content);
      write('\nendstream');
    });
  }
  final xref = out.length;
  write('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  write(
    'trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return out.takeBytes();
}
