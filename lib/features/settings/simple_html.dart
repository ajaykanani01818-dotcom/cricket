import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Block kinds understood by the tiny HTML → widgets converter.
enum HtmlBlockType { h1, h2, h3, updated, paragraph, listItem }

/// A run of text inside a block; [href] is set for `<a href>` runs.
@immutable
class HtmlSpan {
  const HtmlSpan(this.text, [this.href]);
  final String text;
  final String? href;

  @override
  bool operator ==(Object other) =>
      other is HtmlSpan && other.text == text && other.href == href;
  @override
  int get hashCode => Object.hash(text, href);
  @override
  String toString() =>
      href == null ? 'HtmlSpan($text)' : 'HtmlSpan($text → $href)';
}

/// One block. Equality compares [type] and the plain [text] only.
@immutable
class HtmlBlock {
  const HtmlBlock(this.type, this.text, [this.spans = const []]);
  final HtmlBlockType type;

  /// Plain text (inline tags stripped, entities decoded, whitespace collapsed).
  final String text;

  /// [text] split into runs; links carry their href. Empty = one plain run.
  final List<HtmlSpan> spans;

  bool get hasLinks => spans.any((s) => s.href != null);

  @override
  bool operator ==(Object other) =>
      other is HtmlBlock && other.type == type && other.text == text;
  @override
  int get hashCode => Object.hash(type, text);
  @override
  String toString() => 'HtmlBlock($type, $text)';
}

final _blockRe = RegExp(
  r'<(h1|h2|h3|p|li|div)(\s[^>]*)?>([\s\S]*?)</\1\s*>',
  caseSensitive: false,
);
final _linkRe = RegExp(
  r'''<a\s[^>]*?href\s*=\s*["']([^"']*)["'][^>]*>([\s\S]*?)</a\s*>''',
  caseSensitive: false,
);
final _tagRe = RegExp(r'<[^>]+>');
final _wsRe = RegExp(r'\s+');
final _entityRe = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);');
final _updatedClassRe = RegExp(
  r'''class\s*=\s*["'][^"']*\b(updated|meta)\b''',
  caseSensitive: false,
);

const _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'copy': '©',
};

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

String _clean(String raw) =>
    decodeEntities(raw.replaceAll(_tagRe, ' ')).replaceAll(_wsRe, ' ');

/// Splits a block's inner HTML into text runs, keeping `<a href>` targets.
List<HtmlSpan> _spans(String inner) {
  final raw = <HtmlSpan>[];
  var at = 0;
  for (final m in _linkRe.allMatches(inner)) {
    if (m.start > at) raw.add(HtmlSpan(_clean(inner.substring(at, m.start))));
    raw.add(HtmlSpan(_clean(m.group(2)!), decodeEntities(m.group(1)!.trim())));
    at = m.end;
  }
  if (at < inner.length) raw.add(HtmlSpan(_clean(inner.substring(at))));

  // Collapse whitespace across run boundaries and trim the ends.
  final out = <HtmlSpan>[];
  var prevEndsWithSpace = true; // trims the leading space of the first run
  for (final s in raw) {
    var t = s.text;
    if (prevEndsWithSpace && t.startsWith(' ')) t = t.substring(1);
    if (t.isEmpty) continue;
    out.add(HtmlSpan(t, s.href));
    prevEndsWithSpace = t.endsWith(' ');
  }
  if (out.isNotEmpty && out.last.text.endsWith(' ')) {
    final l = out.removeLast();
    final t = l.text.trimRight();
    if (t.isNotEmpty) out.add(HtmlSpan(t, l.href));
  }
  return out;
}

/// Converts the small, well-formed HTML of the bundled legal pages into
/// blocks. Only the `<body>` is read when present (so `<title>`/`<style>` are
/// ignored); inline tags are stripped, entities decoded, whitespace collapsed
/// and links kept as [HtmlSpan]s. A `<div class="updated">` or
/// `<p class="meta">` becomes [HtmlBlockType.updated]; other divs are
/// skipped. Malformed/empty input yields an empty list (never throws).
List<HtmlBlock> parseSimpleHtml(String? html) {
  if (html == null || html.trim().isEmpty) return const [];
  var body = html;
  final b = RegExp(
    r'<body[^>]*>([\s\S]*?)(</body>|$)',
    caseSensitive: false,
  ).firstMatch(html);
  if (b != null) body = b.group(1) ?? '';
  final main = RegExp(
    r'<main[^>]*>([\s\S]*?)</main>',
    caseSensitive: false,
  ).firstMatch(body);
  if (main != null) body = main.group(1) ?? '';
  body = body.replaceAll(
    RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false),
    '',
  );

  final out = <HtmlBlock>[];
  for (final m in _blockRe.allMatches(body)) {
    final tag = m.group(1)!.toLowerCase();
    final attrs = m.group(2) ?? '';
    final spans = _spans(m.group(3)!);
    final text = spans.map((s) => s.text).join();
    if (text.isEmpty) continue;
    final isUpdated = _updatedClassRe.hasMatch(attrs);
    final HtmlBlockType? type = switch (tag) {
      'h1' => HtmlBlockType.h1,
      'h2' => HtmlBlockType.h2,
      'h3' => HtmlBlockType.h3,
      'p' => isUpdated ? HtmlBlockType.updated : HtmlBlockType.paragraph,
      'li' => HtmlBlockType.listItem,
      'div' => isUpdated ? HtmlBlockType.updated : null,
      _ => null,
    };
    if (type != null) out.add(HtmlBlock(type, text, spans));
  }
  return out;
}

/// Renders [blocks] in the app's reading typography. Links are tappable and
/// reported to [onLink] with their raw href.
class SimpleHtmlView extends StatelessWidget {
  const SimpleHtmlView({
    super.key,
    required this.blocks,
    this.onLink,
    this.hideTitle = false,
  });
  final List<HtmlBlock> blocks;
  final ValueChanged<String>? onLink;

  /// Skip `<h1>` blocks (when the page title is already in the top bar).
  final bool hideTitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shown = [
      for (final b in blocks)
        if (!(hideTitle && b.type == HtmlBlockType.h1)) b,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) _block(p, shown[i], i == 0),
      ],
    );
  }

  Widget _block(AppPalette p, HtmlBlock b, bool first) {
    final reading = AppText.reading.copyWith(color: p.ink);
    switch (b.type) {
      case HtmlBlockType.h1:
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.xs),
          child: Semantics(
            header: true,
            child: Text(b.text, style: AppText.h2.copyWith(color: p.ink)),
          ),
        );
      case HtmlBlockType.updated:
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.lg),
          child: Text(b.text, style: AppText.meta.copyWith(color: p.inkMuted)),
        );
      case HtmlBlockType.h2:
      case HtmlBlockType.h3:
        return Padding(
          padding: EdgeInsets.only(
            top: first ? 0 : Spacing.xl,
            bottom: Spacing.sm,
          ),
          child: Semantics(
            header: true,
            child: Text(
              b.text,
              style:
                  (b.type == HtmlBlockType.h2
                          ? AppText.sectionTitle
                          : AppText.h4)
                      .copyWith(color: p.ink),
            ),
          ),
        );
      case HtmlBlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: _RichBlock(
            block: b,
            style: reading,
            linkColor: p.brandText,
            onLink: onLink,
          ),
        );
      case HtmlBlockType.listItem:
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm, left: Spacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Text('•  ', style: reading.copyWith(color: p.inkMuted)),
              ),
              Expanded(
                child: _RichBlock(
                  block: b,
                  style: reading,
                  linkColor: p.brandText,
                  onLink: onLink,
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// Paragraph text with tappable link runs (owns its gesture recognizers).
class _RichBlock extends StatefulWidget {
  const _RichBlock({
    required this.block,
    required this.style,
    required this.linkColor,
    required this.onLink,
  });
  final HtmlBlock block;
  final TextStyle style;
  final Color linkColor;
  final ValueChanged<String>? onLink;

  @override
  State<_RichBlock> createState() => _RichBlockState();
}

class _RichBlockState extends State<_RichBlock> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(String href) {
    final r = TapGestureRecognizer()..onTap = () => widget.onLink?.call(href);
    _recognizers.add(r);
    return r;
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    if (!b.hasLinks) return Text(b.text, style: widget.style);
    _clear();
    final linkStyle = widget.style.copyWith(
      color: widget.linkColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final s in b.spans)
            if (s.href == null || widget.onLink == null)
              TextSpan(text: s.text)
            else
              TextSpan(
                text: s.text,
                style: linkStyle,
                recognizer: _tap(s.href!),
              ),
        ],
      ),
    );
  }
}
