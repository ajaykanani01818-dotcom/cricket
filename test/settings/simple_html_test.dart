import 'package:crickbex/features/settings/privacy_policy_html.dart';
import 'package:crickbex/features/settings/simple_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled privacy policy parses into headings + paragraphs (no title/style)', () {
    final blocks = parseSimpleHtml(privacyPolicyHtml);
    expect(blocks.first, const HtmlBlock(HtmlBlockType.h1, 'Privacy Policy'));
    expect(blocks[1], const HtmlBlock(HtmlBlockType.updated, 'Last updated: July 2026'));
    expect(blocks.where((b) => b.type == HtmlBlockType.h2).length, 8);
    expect(blocks.any((b) => b.text.contains('{') || b.text.contains('<')), isFalse);
    expect(blocks.any((b) => b.text.contains('Privacy Policy — CrickBex')), isFalse, reason: '<title> ignored');
  });

  test('entities, inline tags and whitespace', () {
    final b = parseSimpleHtml('<body><p>A &amp; B&nbsp;<b>bold</b>\n  &#169; &#x41; &unknown;</p><li> item </li></body>');
    expect(b, const [HtmlBlock(HtmlBlockType.paragraph, 'A & B bold © A &unknown;'), HtmlBlock(HtmlBlockType.listItem, 'item')]);
  });

  test('malformed / empty input never throws', () {
    expect(parseSimpleHtml(null), isEmpty);
    expect(parseSimpleHtml(''), isEmpty);
    expect(parseSimpleHtml('<p>unclosed'), isEmpty);
    expect(parseSimpleHtml('<p></p><div>plain div</div>'), isEmpty);
    expect(parseSimpleHtml('no tags at all'), isEmpty);
    expect(parseSimpleHtml('<P CLASS="x">Upper</P>'), const [HtmlBlock(HtmlBlockType.paragraph, 'Upper')]);
  });
}
