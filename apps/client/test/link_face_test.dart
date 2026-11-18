import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/link_face.dart';

/// NEX-UI-03: what a link is, read from its address alone — now remembered.
/// The face is immutable and the address is the whole input, so the same
/// address is always the same answer; the link cards asked again on every
/// rebuild (the link-art listener rebuilds every mounted link card as
/// covers fill in) and each ask re-parsed the address, seven freshly
/// compiled regexes and all.
void main() {
  Matcher sameFaceAs(NexLinkFace expected) => predicate<NexLinkFace>(
    (face) =>
        face.host == expected.host &&
        face.name == expected.name &&
        face.kind == expected.kind &&
        face.brandColor == expected.brandColor &&
        face.title == expected.title &&
        face.youTubeId == expected.youTubeId,
    'the same face as $expected',
  );

  test('the same address is the same face — and the second ask is free', () {
    const url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
    final first = NexLinkFace.of(url);
    expect(identical(NexLinkFace.of(url), first), isTrue);

    expect(first.kind, NexLinkKind.video);
    expect(first.youTubeId, 'dQw4w9WgXcQ');
    expect(first.name, 'YouTube');
    expect(first.brandColor, 0xFFE62117);
  });

  test('answers stay right across the kinds of address', () {
    final short = NexLinkFace.of('https://youtu.be/dQw4w9WgXcQ');
    expect(short.kind, NexLinkKind.video);
    expect(short.youTubeId, 'dQw4w9WgXcQ');

    final repo = NexLinkFace.of('https://github.com/flutter/flutter');
    expect(repo.kind, NexLinkKind.repo);
    expect(repo.title, 'flutter/flutter');

    final article = NexLinkFace.of(
      'https://en.wikipedia.org/wiki/Persian_gulf',
    );
    expect(article.kind, NexLinkKind.article);
    expect(article.title, 'Persian gulf');

    final file = NexLinkFace.of(
      'https://example.com/downloads/report-2026.pdf',
    );
    expect(file.kind, NexLinkKind.file);
    expect(file.title, 'report-2026.pdf');

    final place = NexLinkFace.of('https://maps.app.goo.gl/xyz123');
    expect(place.kind, NexLinkKind.place);

    final post = NexLinkFace.of('https://x.com/somebody/status/1234');
    expect(post.kind, NexLinkKind.post);
    expect(post.title, '@somebody');

    final aparat = NexLinkFace.of('https://www.aparat.com/v/abcde');
    expect(aparat.kind, NexLinkKind.video);
    expect(aparat.name, 'Aparat');

    final bare = NexLinkFace.of('https://example.org/notes/first-post');
    expect(bare.kind, NexLinkKind.article);
    expect(bare.name, 'example.org');

    final notALink = NexLinkFace.of('not a link at all');
    expect(notALink.kind, NexLinkKind.page);

    final empty = NexLinkFace.of('');
    expect(empty.host, isEmpty);
    expect(empty.kind, NexLinkKind.page);
  });

  test('a changed address is a changed answer', () {
    final one = NexLinkFace.of('https://youtube.com/watch?v=dQw4w9WgXcQ');
    final other = NexLinkFace.of('https://youtube.com/watch?v=aaaaaaaaaaa');
    expect(identical(one, other), isFalse);
    expect(other.youTubeId, 'aaaaaaaaaaa');
  });

  test('the memory is bounded', () {
    final first = NexLinkFace.of('https://example.org/bound/first');
    // Enough distinct addresses to push the first one out of a 256-entry
    // memo; eviction recomputes rather than grows forever.
    for (var i = 0; i < 400; i++) {
      NexLinkFace.of('https://example.org/bound/other-$i');
    }
    final again = NexLinkFace.of('https://example.org/bound/first');
    expect(identical(again, first), isFalse, reason: 'the first was evicted');
    expect(again, sameFaceAs(first), reason: 'and recomputed the same answer');
  });
}
