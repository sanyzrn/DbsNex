import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/link_art.dart';
import 'package:nex_client/platform/link_face.dart';
import 'package:nex_client/platform/link_reader.dart';
import 'package:nex_client/widgets/card_link.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_client/widgets/parallax_image.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// Link cards that show what they point at (2.8.3): what the address says
/// with no network, the page's picture and the site's icon from the site
/// itself, and a video that looks like one.
void main() {
  group('what an address says, with no network', () {
    test('YouTube: the video and its id, from every form of address', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://m.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/live/dQw4w9WgXcQ',
      ]) {
        final face = NexLinkFace.of(url);
        expect(face.name, 'YouTube', reason: url);
        expect(face.kind, NexLinkKind.video, reason: url);
        expect(face.youTubeId, 'dQw4w9WgXcQ', reason: url);
        expect(face.brandColor, isNotNull);
      }
      final channel = NexLinkFace.of('https://www.youtube.com/@nex');
      expect(channel.kind, NexLinkKind.profile);
      expect(channel.title, '@nex');
      expect(NexLinkFace.of('https://youtube.com/').youTubeId, isNull);
    });

    test('posts, profiles, repositories and articles', () {
      final reel = NexLinkFace.of('https://www.instagram.com/reel/Cabc123/');
      expect((reel.name, reel.kind), ('Instagram', NexLinkKind.video));
      final page = NexLinkFace.of('https://instagram.com/nexapp');
      expect((page.kind, page.title), (NexLinkKind.profile, '@nexapp'));
      final post = NexLinkFace.of('https://t.me/nexchannel/42');
      expect(
        (post.name, post.kind, post.title),
        ('Telegram', NexLinkKind.post, '@nexchannel'),
      );
      final repo = NexLinkFace.of('https://github.com/sanyzrn/DbsNex/pulls');
      expect((repo.kind, repo.title), (NexLinkKind.repo, 'sanyzrn/DbsNex'));
      final wiki = NexLinkFace.of(
        'https://fa.wikipedia.org/wiki/%D8%AA%D9%87%D8%B1%D8%A7%D9%86',
      );
      expect(
        (wiki.name, wiki.kind, wiki.title),
        ('Wikipedia', NexLinkKind.article, 'تهران'),
      );
      final place = NexLinkFace.of('https://maps.app.goo.gl/abc');
      expect(place.kind, NexLinkKind.place);
    });

    test('an article\'s slug is its title; an id is not', () {
      final article = NexLinkFace.of(
        'https://example.com/tech/446439-barghe-man-not-working/',
      );
      expect(article.kind, NexLinkKind.article);
      expect(article.title, 'Barghe man not working');
      expect(article.name, 'example.com');
      final persian = NexLinkFace.of(
        'https://blog.example.ir/'
        '%D8%B3%D9%84%D8%A7%D9%85-%D8%AF%D9%86%DB%8C%D8%A7',
      );
      expect(persian.title, 'سلام دنیا');
      final known = NexLinkFace.of(
        'https://www.zoomit.ir/tech-iran/446439-barghe-man-not-working/',
      );
      expect(
        (known.name, known.kind, known.title),
        ('Zoomit', NexLinkKind.article, 'Barghe man not working'),
      );
      expect(NexLinkFace.of('https://example.com/p/8f3a9c2e1b').title, isNull);
      expect(NexLinkFace.of('https://example.com/').title, isNull);
      final file = NexLinkFace.of('https://example.com/docs/report-2026.pdf');
      expect((file.kind, file.title), (NexLinkKind.file, 'report-2026.pdf'));
    });
  });

  group('pictures only from the page\'s own site', () {
    test('the same registered name, or the one a known site uses', () {
      final page = Uri.parse('https://news.example.co.uk/a');
      expect(
        nexSameSite(page, Uri.parse('https://cdn.example.co.uk/i.jpg')),
        isTrue,
      );
      expect(
        nexSameSite(page, Uri.parse('https://tracker.com/i.jpg')),
        isFalse,
      );
      expect(
        nexSameSite(
          Uri.parse('https://www.youtube.com/watch?v=x'),
          Uri.parse('https://i.ytimg.com/vi/x/hqdefault.jpg'),
        ),
        isTrue,
      );
      expect(
        nexSameSite(
          Uri.parse('https://zoomit.ir/a'),
          Uri.parse('https://i.ytimg.com/vi/x/hqdefault.jpg'),
        ),
        isFalse,
      );
    });

    test('a page names its picture and its icon, resolved against it', () {
      final preview = parseLinkPreview(
        '<html><head><title>T</title>'
        '<meta property="og:image" content="/img/cover.jpg">'
        '<link rel="icon" href="/favicon.png">'
        '<link rel="apple-touch-icon" href="https://example.com/touch.png">'
        '</head></html>',
        base: Uri.parse('https://example.com/news/1'),
      );
      expect(preview.imageUrl, Uri.parse('https://example.com/img/cover.jpg'));
      expect(preview.iconUrl, Uri.parse('https://example.com/touch.png'));
      final bare = parseLinkPreview(
        '<title>T</title>',
        base: Uri.parse('https://example.com/a'),
      );
      expect(bare.imageUrl, isNull);
      expect(bare.iconUrl, Uri.parse('https://example.com/favicon.ico'));
      expect(
        parseLinkPreview(
          '<meta property="og:image" content="javascript:x">',
          base: Uri.parse('https://example.com/'),
        ).imageUrl,
        isNull,
      );
    });
  });

  Note link(String id, String url, {String? title}) => Note(
    id: id,
    type: NoteType.link,
    content: url,
    title: title,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deviceId: 'd',
    rev: 1,
    syncState: SyncState.pending,
  );

  Future<void> host(WidgetTester tester, List<Widget> tiles) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nexSoftLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              for (final tile in tiles)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(width: 190, height: 230, child: tile),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('nex_link_art_');
    NexLinkArt.instance.debugUse(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  File picture(String name, int w, int h) {
    final im = img.Image(width: w, height: h);
    img.fill(im, color: img.ColorRgb8(200, 60, 40));
    return File('${dir.path}/$name')..writeAsBytesSync(img.encodePng(im));
  }

  testWidgets('a video saved offline still looks like one: its site, Video, '
      'and a small screen with Play', (tester) async {
    await host(tester, [
      NexNoteGridCard(
        note: link('y', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        strings: NexCardStrings.fallback,
        onTap: () {},
      ),
    ]);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.byKey(const ValueKey('grid-link-screen')), findsOneWidget);
    expect(find.text('youtube.com'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an article with no title wears the one its address spells', (
    tester,
  ) async {
    await host(tester, [
      NexNoteGridCard(
        note: link(
          'a',
          'https://example.com/tech/446439-barghe-man-not-working',
        ),
        strings: NexCardStrings.fallback,
        onTap: () {},
      ),
    ]);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Barghe man not working'), findsOneWidget);
    expect(find.text('Article'), findsOneWidget);
  });

  testWidgets('the site\'s own icon replaces its initial', (tester) async {
    final icon = picture('i.icon.png', 32, 32);
    NexLinkArt.instance.debugRemember('s', icon: icon);
    await host(tester, [
      NexNoteGridCard(
        note: link('s', 'https://example.com/', title: 'Example'),
        strings: NexCardStrings.fallback,
        onTap: () {},
      ),
    ]);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image && w.image is FileImage ||
            w is Image && w.image is ResizeImage,
      ),
      findsOneWidget,
    );
    expect(find.text('E'), findsNothing);
  });

  testWidgets('with its picture, the link fills its tile: the site and '
      'Video over it, Play in the middle, the title at the foot', (
    tester,
  ) async {
    final cover = picture('v.cover.jpg', 480, 270);
    await host(tester, [
      NexNoteGridCard(
        note: link(
          'v',
          'https://youtu.be/dQw4w9WgXcQ',
          title: 'A song from 1987',
        ),
        strings: NexCardStrings.fallback,
        onTap: () {},
      ),
    ]);
    expect(find.byType(NexParallaxImage), findsNothing);
    // The picture arrives after the tile is built, and the tile takes it.
    NexLinkArt.instance.debugRemember('v', cover: cover);
    await tester.pump();
    expect(find.byType(NexParallaxImage), findsOneWidget);
    expect(find.byKey(const ValueKey('grid-link-site')), findsOneWidget);
    expect(find.text('YouTube · Video'), findsOneWidget);
    expect(find.text('A song from 1987'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Persian: the kind in Persian, the address left to right', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        theme: nexSoftLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 190,
              height: 230,
              child: NexNoteGridCard(
                note: link('p', 'https://example.com/a/some-long-article-name'),
                strings: NexCardStrings.fallback,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('مطلب'), findsOneWidget);
    final host = tester.widget<Text>(find.text('example.com'));
    expect(host.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the list card: the address\'s title, and the site by its '
      'name and kind instead of a bare address', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nexSoftLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NexCardDensityScope(
            density: NexCardDensity.standard,
            child: NexCardLinkPreview(
              note: link('l', 'https://www.youtube.com/@nexapp'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('@nexapp'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text(' · Profile'), findsOneWidget);
    expect(NexCardLinkPreview.fits(link('x', '')), isFalse);
  });
}
