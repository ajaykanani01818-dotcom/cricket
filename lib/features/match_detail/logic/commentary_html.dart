/// Ported from RN `src/utils/commentaryHtml.ts`.
///
/// Minimal commentary HTML -> styled text runs.
/// Supports: <strong>, <b>, <em>, <i>, <br>; strips other tags; decodes common entities.
library;

class CommentaryTextRun {
  final String text;
  final bool bold;
  final bool italic;
  const CommentaryTextRun(this.text, {this.bold = false, this.italic = false});

  @override
  bool operator ==(Object other) =>
      other is CommentaryTextRun && other.text == text && other.bold == bold && other.italic == italic;

  @override
  int get hashCode => Object.hash(text, bold, italic);

  @override
  String toString() => 'Run("$text", b=$bold, i=$italic)';
}

String decodeHtmlEntities(String s) {
  return s
      .replaceAll('&amp;', '&')
      .replaceAllMapped(RegExp(r'&#x([0-9a-f]+);', caseSensitive: false), (m) {
        final code = int.tryParse(m.group(1)!, radix: 16);
        return code == null ? m.group(0)! : String.fromCharCode(code);
      })
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m.group(1)!);
        return code == null ? m.group(0)! : String.fromCharCode(code);
      })
      .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

final _anyTag = RegExp(r'<\s*\/?\s*([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>');
final _styleTag = RegExp(r'<(\/?)\s*(strong|b|em|i)\s*>', caseSensitive: false);
final _br = RegExp(r'<br\s*\/?>', caseSensitive: false);
final _residue = RegExp(r'<[^>]*>');

/// Remove tags we do not interpret (keeps strong/b/em/i tokens).
String _stripUnsupportedTags(String html) => html.replaceAllMapped(_anyTag, (m) {
      final t = m.group(1)!.toLowerCase();
      if (t == 'strong' || t == 'b' || t == 'em' || t == 'i') return m.group(0)!;
      return '';
    });

List<CommentaryTextRun> parseCommentaryRuns(String? html) {
  if (html == null || html.isEmpty) return const [];
  var decoded = decodeHtmlEntities(html);
  decoded = decoded.replaceAll(_br, '\n');
  decoded = _stripUnsupportedTags(decoded);

  final runs = <CommentaryTextRun>[];
  var bold = false;
  var italic = false;
  final buf = StringBuffer();

  void flush() {
    if (buf.isNotEmpty) {
      runs.add(CommentaryTextRun(buf.toString(), bold: bold, italic: italic));
      buf.clear();
    }
  }

  var last = 0;
  for (final m in _styleTag.allMatches(decoded)) {
    buf.write(decoded.substring(last, m.start));
    flush();
    final isClose = m.group(1) == '/';
    final t = m.group(2)!.toLowerCase();
    if (t == 'strong' || t == 'b') {
      bold = !isClose;
    } else {
      italic = !isClose;
    }
    last = m.end;
  }
  buf.write(decoded.substring(last));
  flush();

  final merged = <CommentaryTextRun>[];
  for (final r in runs) {
    if (merged.isNotEmpty && merged.last.bold == r.bold && merged.last.italic == r.italic) {
      final prev = merged.removeLast();
      merged.add(CommentaryTextRun(prev.text + r.text, bold: r.bold, italic: r.italic));
    } else {
      merged.add(r);
    }
  }
  // Drop any stray angle-bracket residue
  return merged
      .map((r) => CommentaryTextRun(r.text.replaceAll(_residue, ''), bold: r.bold, italic: r.italic))
      .toList(growable: false);
}
