import 'package:flutter/material.dart';

import '../motion/hero_tags.dart';
import '../motion/motion.dart';
import '../theme/app_theme.dart';

/// A score ("135/4", "245/6 (48.2)") in tabular Archivo wdth 72 / wght 800.
///
/// When [text] changes AFTER the first build, only the characters that
/// changed roll vertically (odometer, [Motion.digitRoll]); unchanged
/// characters stay still. First render, identical text and reduced motion
/// never animate (reduced motion: instant swap). At rest it is one Text.
///
/// [heroTag]: wrap in a [MatchHero] for the card → Match Centre moment.
class ScoreText extends StatefulWidget {
  const ScoreText(
    this.text, {
    super.key,
    this.style,
    this.heroTag,
    this.animate = true,
    this.semanticsLabel,
    this.textAlign,
  });

  final String text;

  /// Defaults to [AppText.scoreCard].
  final TextStyle? style;
  final String? heroTag;
  final bool animate;
  final String? semanticsLabel;
  final TextAlign? textAlign;

  @override
  State<ScoreText> createState() => _ScoreTextState();
}

class _ScoreTextState extends State<ScoreText>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  String? _from;

  AnimationController get _ctrl =>
      _c ??= AnimationController(vsync: this, duration: Motion.digitRoll)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed && mounted) {
            setState(() => _from = null);
          }
        });

  @override
  void didUpdateWidget(ScoreText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text &&
        widget.animate &&
        !Motion.reducedOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      _from = old.text;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = (widget.style ?? AppText.scoreCard);
    final from = _from;
    Widget child;
    if (from == null || _c == null) {
      child = Text(
        widget.text,
        style: style,
        maxLines: 1,
        textAlign: widget.textAlign,
        softWrap: false,
      );
    } else {
      child = _Rolling(
        from: from,
        to: widget.text,
        style: style,
        animation: CurvedAnimation(parent: _c!, curve: Motion.standard),
      );
    }
    child = Semantics(
      label: widget.semanticsLabel ?? widget.text,
      excludeSemantics: true,
      child: RepaintBoundary(child: child),
    );
    final tag = widget.heroTag;
    return tag == null ? child : MatchHero(tag: tag, child: child);
  }
}

/// Characters aligned from the right; changed ones roll up.
class _Rolling extends StatelessWidget {
  const _Rolling({
    required this.from,
    required this.to,
    required this.style,
    required this.animation,
  });
  final String from, to;
  final TextStyle style;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final n = to.length > from.length ? to.length : from.length;
    final a = from.padLeft(n), b = to.padLeft(n);
    final lineH = (style.fontSize ?? 16) * (style.height ?? 1.2);
    final chars = <Widget>[];
    for (var i = 0; i < n; i++) {
      final o = a[i], c = b[i];
      if (o == c) {
        if (c != ' ' || i >= n - to.length) chars.add(Text(c, style: style));
        continue;
      }
      chars.add(
        ClipRect(
          child: SizedBox(
            height: lineH,
            child: AnimatedBuilder(
              animation: animation,
              builder: (_, _) {
                final t = animation.value;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Transform.translate(
                      offset: Offset(0, -lineH * t),
                      child: Text(o.trim().isEmpty ? '' : o, style: style),
                    ),
                    Transform.translate(
                      offset: Offset(0, lineH * (1 - t)),
                      child: Text(c.trim().isEmpty ? '' : c, style: style),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: chars,
    );
  }
}
