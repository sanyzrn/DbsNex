import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  test('extensions are recognised, and a leading dot is a name', () {
    expect(fileExtensionOf('report.pdf'), '.pdf');
    expect(fileExtensionOf('archive.tar.gz'), '.gz');
    expect(fileExtensionOf('.env'), '');
    expect(fileExtensionOf('no extension'), '');
    expect(fileExtensionOf('trailing.'), '');
    expect(fileBaseNameOf('گزارش سال.docx'), 'گزارش سال');
  });

  test('unsafe names are made safe and kept short', () {
    expect(safeFileName('a/b:c*?"<>|d', extension: '.md'), 'a b c d.md');
    expect(safeFileName('  ...  '), isNull);
    expect(
      safeFileName('x' * 300, extension: '.md')!.length,
      nexMaxFileNameLength,
    );
    expect(
      safeFileName('یادداشت‌های امروز', extension: '.md'),
      'یادداشت‌های امروز.md',
    );
  });

  test('a typed name is checked, not rewritten', () {
    expect(checkFileBaseName('  '), FileNameProblem.empty);
    expect(checkFileBaseName('..'), FileNameProblem.empty);
    expect(checkFileBaseName('a/b'), FileNameProblem.forbiddenCharacters);
    expect(
      checkFileBaseName('x' * 120, extension: '.pdf'),
      FileNameProblem.tooLong,
    );
    expect(checkFileBaseName('قرارداد اجاره', extension: '.pdf'), isNull);
  });

  test('a Markdown file is named after its first line', () {
    expect(markdownFileNameFor('# Shopping list\n- milk'), 'Shopping list.md');
    expect(markdownFileNameFor('\n\n  فهرست خرید  \nشیر'), 'فهرست خرید.md');
    expect(markdownFileNameFor('   \n'), 'note.md');
    expect(markdownFileNameFor('a/b'), 'a b.md');
  });
}
