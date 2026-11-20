import 'package:crickbex/features/settings/legal_documents.dart';
import 'package:crickbex/features/settings/simple_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bundled privacy policy parses into headings, paragraphs and list items',
    () {
      final blocks = parseSimpleHtml(privacyPolicyHtml);
      expect(blocks.first, const HtmlBlock(HtmlBlockType.h1, 'Privacy policy'));
      expect(
        blocks[1],
        const HtmlBlock(HtmlBlockType.updated, 'Effective 18 November 2026'),
      );
      expect(blocks.where((b) => b.type == HtmlBlockType.h2).length, 12);
      expect(blocks.where((b) => b.type == HtmlBlockType.listItem).length, 8);
      expect(
        blocks.any((b) => b.text.contains('{') || b.text.contains('<')),
        isFalse,
      );
    },
  );

  test('bundled terms parse; links keep their href', () {
    final blocks = parseSimpleHtml(termsOfUseHtml);
    expect(blocks.where((b) => b.type == HtmlBlockType.h2).length, 11);
    final privacy = blocks.firstWhere(
      (b) => b.text.startsWith('How we handle information'),
    );
    expect(
      privacy.text,
      'How we handle information is described in our privacy policy.',
    );
    expect(privacy.spans, const [
      HtmlSpan('How we handle information is described in our '),
      HtmlSpan('privacy policy', 'privacy-policy.html'),
      HtmlSpan('.'),
    ]);
  });

  test('entities, inline tags and whitespace', () {
    final b = parseSimpleHtml(
      '<body><p>A &amp; B&nbsp;<b>bold</b>\n  &#169; &#x41; &unknown;</p><li> item </li></body>',
    );
    expect(b, const [
      HtmlBlock(HtmlBlockType.paragraph, 'A & B bold © A &unknown;'),
      HtmlBlock(HtmlBlockType.listItem, 'item'),
    ]);
  });

  test('link spacing collapses across run boundaries', () {
    final b = parseSimpleHtml(
      '<p> See <a href="x.html"> the page </a> now </p>',
    ).single;
    expect(b.text, 'See the page now');
    expect(b.spans.map((s) => s.text).join(), b.text);
    expect(b.spans[1], const HtmlSpan('the page ', 'x.html'));
  });

  test('p.meta and div.updated become the "updated" line', () {
    expect(
      parseSimpleHtml('<p class="meta">Effective today</p>').single.type,
      HtmlBlockType.updated,
    );
    expect(
      parseSimpleHtml('<div class="updated">Last updated</div>').single.type,
      HtmlBlockType.updated,
    );
  });

  test('malformed / empty input never throws', () {
    expect(parseSimpleHtml(null), isEmpty);
    expect(parseSimpleHtml(''), isEmpty);
    expect(parseSimpleHtml('<p>unclosed'), isEmpty);
    expect(parseSimpleHtml('<p></p><div>plain div</div>'), isEmpty);
    expect(parseSimpleHtml('no tags at all'), isEmpty);
    expect(parseSimpleHtml('<P CLASS="x">Upper</P>'), const [
      HtmlBlock(HtmlBlockType.paragraph, 'Upper'),
    ]);
  });
}
