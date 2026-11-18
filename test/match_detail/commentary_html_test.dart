import 'package:crickbex/features/match_detail/logic/commentary_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCommentaryRuns', () {
    test('empty / null', () {
      expect(parseCommentaryRuns(null), isEmpty);
      expect(parseCommentaryRuns(''), isEmpty);
    });

    test('strips <p> and keeps plain text', () {
      expect(parseCommentaryRuns('<p>Taskin Ahmed to Bavuma: No Run.</p>'),
          [const CommentaryTextRun('Taskin Ahmed to Bavuma: No Run.')]);
    });

    test('bold / italic segments and merging of equal styles', () {
      final runs = parseCommentaryRuns('<p><strong>Stumps</strong> on Day 2. <em>Rain</em> <b>and</b><strong> more</strong></p>');
      expect(runs, [
        const CommentaryTextRun('Stumps', bold: true),
        const CommentaryTextRun(' on Day 2. '),
        const CommentaryTextRun('Rain', italic: true),
        const CommentaryTextRun(' '),
        const CommentaryTextRun('and more', bold: true),
      ]);
    });

    test('<br> becomes newline, entities decoded', () {
      final runs = parseCommentaryRuns('A &amp; B<br/>C&nbsp;D 5 &lt; 6 &quot;q&quot; &#39;s&#39; &#65;&#x42;');
      expect(runs.single.text, 'A & B\nC\u00A0D 5 < 6 "q" \'s\' AB');
      // Same as RN: entities are decoded before tags are stripped, so an
      // encoded tag-like token is removed.
      expect(parseCommentaryRuns('x &lt;y&gt; z').single.text, 'x  z');
    });

    test('unknown tags removed, attributes tolerated, stray residue dropped', () {
      final runs = parseCommentaryRuns('<div class="x"><span>Hi</span> <a href="#">there</a></div>');
      expect(runs.single.text, 'Hi there');
    });

    test('unclosed bold continues to the end', () {
      final runs = parseCommentaryRuns('a <b>bold forever');
      expect(runs, [const CommentaryTextRun('a '), const CommentaryTextRun('bold forever', bold: true)]);
    });
  });
}
