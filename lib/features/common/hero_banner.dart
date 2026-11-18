import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/match_transform.dart';
import '../../core/widgets/net_image.dart';

/// Top batter for a format (RN useHomeData `heroBannerPlayers`).
class HeroPlayer {
  const HeroPlayer({required this.format, required this.playerKey, required this.name, this.rating, this.rank, this.country = ''});
  final String format;
  final String playerKey;
  final String name;
  final num? rating;
  final int? rank;
  final String country;
}

enum HeroSlideType { live, recent, upcoming, player }

class HeroSlide {
  const HeroSlide(this.type, {this.match, this.player});
  final HeroSlideType type;
  final MatchSummary? match;
  final HeroPlayer? player;
}

/// RN HeroBanner slide list: every "live" (recent) match, then 2 upcoming,
/// then the top batters.
List<HeroSlide> buildHeroSlides(List<MatchSummary> live, List<MatchSummary> upcoming, List<HeroPlayer> players) => [
      for (final m in live) HeroSlide(m.isLive ? HeroSlideType.live : HeroSlideType.recent, match: m),
      for (final m in upcoming.take(2)) HeroSlide(HeroSlideType.upcoming, match: m),
      for (final p in players) HeroSlide(HeroSlideType.player, player: p),
    ];

/// Ported from RN `HeroBanner` (stadium background + auto-advancing slides).
/// Note: RN declares it but HomeScreen no longer mounts it; kept for reuse.
class HeroBanner extends StatefulWidget {
  const HeroBanner({super.key, required this.slides, this.onSlideTap, this.autoAdvance = const Duration(seconds: 6)});
  final List<HeroSlide> slides;
  final ValueChanged<HeroSlide>? onSlideTap;
  final Duration autoAdvance;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final _page = PageController();
  int _index = 0;
  Timer? _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final v = TickerMode.valuesOf(context).enabled;
    if (v != _visible) {
      _visible = v;
      _restartTimer();
    }
  }

  @override
  void didUpdateWidget(HeroBanner old) {
    super.didUpdateWidget(old);
    if (_index >= widget.slides.length && _index != 0) {
      _index = 0;
      if (_page.hasClients) _page.jumpToPage(0);
    }
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_visible || widget.slides.length <= 1) return;
    _timer = Timer.periodic(widget.autoAdvance, (_) => _go(_index + 1));
  }

  void _go(int target) {
    final n = widget.slides.length;
    if (n <= 1 || !_page.hasClients) return;
    final i = (target + n) % n;
    setState(() => _index = i);
    _page.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = (width * 0.58).roundToDouble().clamp(212.0, 290.0);
    final isSmall = width < 360, isLarge = width > 430;
    final titleSize = isSmall ? 19.0 : isLarge ? 24.0 : 22.0;
    final scoreSize = isSmall ? 15.0 : isLarge ? 20.0 : 18.0;
    final sidePad = isSmall ? 14.0 : isLarge ? 28.0 : 22.0;
    final arrow = isSmall ? 34.0 : 40.0;
    final slides = widget.slides;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(children: [
        Positioned.fill(child: SvgPicture.asset('assets/hero/stadium-default1.svg', fit: BoxFit.cover)),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xE0FFFFFF), Color(0x1F0B5CD4)]),
            ),
          ),
        ),
        PageView.builder(
          controller: _page,
          itemCount: slides.isEmpty ? 1 : slides.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: slides.isEmpty ? null : () => widget.onSlideTap?.call(slides[i]),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: sidePad + arrow),
              child: Center(child: _content(slides.isEmpty ? null : slides[i], titleSize, scoreSize)),
            ),
          ),
        ),
        if (slides.length > 1) ...[
          Positioned(left: 12, top: 12, child: _arrowBtn(Icons.chevron_left, arrow, () => _go(_index - 1), 'common_hero_prev')),
          Positioned(right: 12, top: 12, child: _arrowBtn(Icons.chevron_right, arrow, () => _go(_index + 1), 'common_hero_next')),
          Positioned(
            left: 0,
            right: 0,
            bottom: isSmall ? 10 : 16,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < slides.length; i++)
                GestureDetector(
                  onTap: () => _go(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                    width: i == _index ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.pitch : const Color(0xFFD0D0D0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ]),
          ),
        ],
        const Positioned(left: 0, right: 0, bottom: 0, height: 24, child: IgnorePointer(child: ColoredBox(color: Color(0x0A000000)))),
      ]),
    );
  }

  Widget _arrowBtn(IconData icon, double size, VoidCallback onTap, String key) => InkResponse(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: Color(0x0F000000), shape: BoxShape.circle),
          child: Icon(icon, size: size * 0.55, color: const Color(0x80000000)),
        ),
      );

  Widget _content(HeroSlide? s, double titleSize, double scoreSize) {
    const dark = Color(0xFF1A1A1A), meta = Color(0xFF555555), muted = Color(0xFF999999);
    Text title(String t) => Text(t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w800, color: dark));
    const gold = TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.gold, letterSpacing: 1);
    Widget scores(MatchSummary m) => FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (m.team1Logo != null) ...[NetImage(url: m.team1Logo, size: 28, fallbackLetter: m.team1), const SizedBox(width: 8)],
          Text(m.team1Score ?? '—', style: TextStyle(fontSize: scoreSize, fontWeight: FontWeight.w800, color: dark)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('vs', style: TextStyle(fontSize: 12, color: muted))),
          if (m.team2Logo != null) ...[NetImage(url: m.team2Logo, size: 28, fallbackLetter: m.team2), const SizedBox(width: 8)],
          Text(m.team2Score ?? '—', style: TextStyle(fontSize: scoreSize, fontWeight: FontWeight.w800, color: dark)),
        ]));
    const metaStyle = TextStyle(fontSize: 13, color: meta);

    final children = <Widget>[];
    if (s == null) {
      children.addAll([title('CrickBex'), const Text('Your premium cricket destination', style: TextStyle(fontSize: 15, color: meta))]);
    } else if (s.type == HeroSlideType.player) {
      final p = s.player!;
      children.addAll([
        Text('Top ${p.format} Batter', style: gold),
        const SizedBox(height: 10),
        title(p.name),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, children: [
          Text(p.country, style: metaStyle),
          const Text(' • ', style: TextStyle(fontSize: 13, color: muted)),
          Text('${p.rating ?? '-'} Rating', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.gold)),
          const Text(' • ', style: TextStyle(fontSize: 13, color: muted)),
          Text('#${p.rank ?? '-'} in World', style: metaStyle),
        ]),
      ]);
    } else {
      final m = s.match!;
      if (s.type == HeroSlideType.live) {
        children.add(const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          DecoratedBox(decoration: BoxDecoration(color: AppColors.live, shape: BoxShape.circle), child: SizedBox(width: 8, height: 8)),
          SizedBox(width: 8),
          Text('Live Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: dark, letterSpacing: 1)),
        ]));
      } else {
        children.add(Text(s.type == HeroSlideType.recent ? 'Result' : 'Upcoming', style: gold));
      }
      children.addAll([const SizedBox(height: 10), title('${m.team1} vs ${m.team2}'), const SizedBox(height: 10)]);
      if (s.type == HeroSlideType.upcoming) {
        final d = DateTime.tryParse(m.date);
        children.add(Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
          if (m.format != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(6)),
              child: Text(m.format!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: dark)),
            ),
          if (d != null) Text(DateFormat('MMM d, y', 'en_US').format(d.toLocal()), style: metaStyle),
          if (m.series.isNotEmpty) Text('• ${m.series}', style: const TextStyle(fontSize: 13, color: muted)),
        ]));
      } else {
        children.add(scores(m));
        final line = s.type == HeroSlideType.recent ? (m.resultMessage ?? m.status) : m.status;
        if (line.isNotEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(line, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: metaStyle),
          ));
        }
      }
    }
    return FittedBox(fit: BoxFit.scaleDown, child: SizedBox(width: 300, child: Column(mainAxisSize: MainAxisSize.min, children: children)));
  }
}
