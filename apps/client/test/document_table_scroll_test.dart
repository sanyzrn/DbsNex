import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/documents/docx_markdown.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/folded_note.dart';

void main() {
  for (final docx in [false, true]) {
    for (final persian in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '${docx ? 'DOCX' : 'Markdown'} table scrolls ($persian, $scale)',
          (tester) async {
            tester.view.physicalSize = const Size(360, 760);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final cell = persian
                ? 'توضیحات کامل محصول و قیمت برای مقایسه'
                : 'Readable product details and pricing';
            final rows = [
              ['Rank', 'Product', 'Platform', 'Rating', 'Pricing', 'Link'],
              ['1', cell, cell, '4.8', cell, 'LAST-COLUMN'],
            ];
            if (!docx) rows.last[5] = '[LAST-COLUMN](https://example.org)';
            var source =
                '| ${rows.first.join(' | ')} |\n| ${List.filled(6, '---').join(' | ')} |\n| ${rows.last.join(' | ')} |';
            if (docx) {
              final xml =
                  '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:tbl>${rows.map((row) => '<w:tr>${row.map((text) => '<w:tc><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:tc>').join()}</w:tr>').join()}</w:tbl></w:body></w:document>';
              final bytes = utf8.encode(xml);
              final archive = Archive()
                ..addFile(
                  ArchiveFile('word/document.xml', bytes.length, bytes),
                );
              source = NexDocx.read(ZipEncoder().encode(archive))!.markdown;
            }
            final paragraph = persian
                ? 'متن کنار جدول خوانا می‌ماند.'
                : 'Text around the table stays readable.';
            source = '$paragraph\n\n$source\n\n$paragraph';
            String? opened;
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: FoldedNote(
                      text: source,
                      markdown: true,
                      onTapLink: (url) => opened = url,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final horizontal = find.byWidgetPredicate(
              (w) =>
                  w is SingleChildScrollView &&
                  w.scrollDirection == Axis.horizontal,
            );
            expect(horizontal, findsOneWidget);
            final scrollable = tester.state<ScrollableState>(
              find
                  .descendant(of: horizontal, matching: find.byType(Scrollable))
                  .first,
            );
            expect(scrollable.position.maxScrollExtent, greaterThan(0));
            expect(tester.getSize(find.byType(Table)).width, greaterThan(360));
            final rtl = scrollable.position.axisDirection == AxisDirection.left;
            await tester.drag(horizontal, Offset(rtl ? 200 : -200, 0));
            await tester.pumpAndSettle();
            expect(scrollable.position.pixels, greaterThan(0));
            scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
            await tester.pump();
            expect(
              find.text('LAST-COLUMN', findRichText: true),
              findsOneWidget,
            );
            expect(find.byType(SelectionArea), findsOneWidget);
            if (!docx) {
              await tester.tap(find.text('LAST-COLUMN', findRichText: true));
              expect(opened, 'https://example.org');
            }
            expect(
              tester
                  .getSize(find.text(paragraph, findRichText: true).first)
                  .width,
              lessThanOrEqualTo(360),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
