import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Block kinds understood by the tiny HTML → widgets converter.
enum HtmlBlockType { h1, h2, h3, updated, paragraph, listItem }

class HtmlBlock {
  const HtmlBlock(this.type, this.text);
  final HtmlBlockType type;
  final String text;

  @override
  bool operator ==(Object other) => other is HtmlBlock && other.type == type && other.text == text;
  @override
  int get hashCode => Object.hash(type, text);
  @override
  String toString() => 'HtmlBlock($type, $text)';
}

final _blockRe = RegExp(
  r'<(h1|h2|h3|p|li|div)(\s[^>]*)?>([\s\S]*?)</\1\s*>',
  caseSensitive: false,
);
final _tagRe = RegExp(r'<[^>]+>');
final _wsRe = RegExp(r'\s+');
final _entityRe = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);');

const _named = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'mdash': '—', 'ndash': '–', 'hellip': '…', 'copy': '©'};

String decodeEntities(String s) => s.replaceAllMapped(_entityRe, (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        final c = int.tryParse(e.substring(2), radix: 16);
        return c == null ? m.group(0)! : String.fromCharCode(c);
      }
      if (e.startsWith('#')) {
        final c = int.tryParse(e.substring(1));
        return c == null ? m.group(0)! : String.fromCharCode(c);
      }
      return _named[e.toLowerCase()] ?? m.group(0)!;
    });

/// Converts the small, well-formed HTML used by the bundled legal pages into
/// blocks. Only the `<body>` is read (so `<title>`/`<style>` are ignored);
/// inline tags are stripped, entities decoded, whitespace collapsed. A
/// `<div class="updated">` becomes [HtmlBlockType.updated]; other divs are
/// skipped. Malformed/empty input yields an empty list (never throws).
List<HtmlBlock> parseSimpleHtml(String? html) {
  if (html == null || html.trim().isEmpty) return const [];
  var body = html;
  final b = RegExp(r'<body[^>]*>([\s\S]*?)(</body>|$)', caseSensitive: false).firstMatch(html);
  if (b != null) body = b.group(1) ?? '';
  body = body.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), '');

  final out = <HtmlBlock>[];
  for (final m in _blockRe.allMatches(body)) {
    final tag = m.group(1)!.toLowerCase();
    final attrs = m.group(2) ?? '';
    final text = decodeEntities(m.group(3)!.replaceAll(_tagRe, ' ')).replaceAll(_wsRe, ' ').trim();
    if (text.isEmpty) continue;
    final HtmlBlockType? type = switch (tag) {
      'h1' => HtmlBlockType.h1,
      'h2' => HtmlBlockType.h2,
      'h3' => HtmlBlockType.h3,
      'p' => HtmlBlockType.paragraph,
      'li' => HtmlBlockType.listItem,
      'div' => RegExp(r'''class\s*=\s*["'][^"']*\bupdated\b''').hasMatch(attrs) ? HtmlBlockType.updated : null,
      _ => null,
    };
    if (type != null) out.add(HtmlBlock(type, text));
  }
  return out;
}

/// Renders [blocks] with the same typography as the RN WebView CSS.
class SimpleHtmlView extends StatelessWidget {
  const SimpleHtmlView({super.key, required this.blocks});
  final List<HtmlBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < blocks.length; i++) _block(blocks[i], i),
    ]);
  }

  Widget _block(HtmlBlock b, int i) {
    switch (b.type) {
      case HtmlBlockType.h1:
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(b.text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
        );
      case HtmlBlockType.updated:
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text(b.text, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        );
      case HtmlBlockType.h2:
      case HtmlBlockType.h3:
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 24, bottom: 8),
          child: Text(b.text,
              style: TextStyle(fontSize: b.type == HtmlBlockType.h2 ? 15 : 14, fontWeight: FontWeight.w800, color: AppColors.text)),
        );
      case HtmlBlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(b.text, style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF475569))),
        );
      case HtmlBlockType.listItem:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 12),
          child: Text('• ${b.text}', style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF475569))),
        );
    }
  }
}
