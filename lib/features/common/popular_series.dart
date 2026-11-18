import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/json.dart';
import '../../core/router/app_nav.dart';
import '../../core/services/cricket_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/net_image.dart';
import 'series_resolver.dart';
import 'tap_guard.dart';

const _seriesSharedLogo = 'https://etimg.etb2bimg.com/photo/74594723.cms';

class PopularSeriesItem {
  const PopularSeriesItem({required this.key, required this.name, required this.shortLabel, required this.logo});
  final String key; // sb_series_key (or key/_id)
  final String name;
  final String shortLabel;
  final String logo;
}

/// RN usePopularSeries `acronym`.
String seriesAcronym(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length > 3 ? w.substring(0, 3) : w).toUpperCase();
  }
  final s = words.map((w) => w[0]).join();
  return (s.length > 4 ? s.substring(0, 4) : s).toUpperCase();
}

/// Parses `/series?status=ONGOING` (data is a list, or `{series: [...]}`).
List<PopularSeriesItem> parsePopularSeries(dynamic data) {
  final raw = data is List ? data : J.list(J.map(data)['series']);
  final out = <PopularSeriesItem>[];
  for (final s in J.maps(raw)) {
    final name = J.str(s['name']).trim();
    final key = (J.text(s['sb_series_key']) ?? J.text(s['key']) ?? J.text(s['_id']) ?? '').trim();
    if (key.isEmpty || name.isEmpty) continue;
    out.add(PopularSeriesItem(key: key, name: name, shortLabel: seriesAcronym(name), logo: _seriesSharedLogo));
    if (out.length == 10) break;
  }
  return out;
}

/// RN usePopularSeries: ongoing series, [] on failure.
Future<List<PopularSeriesItem>> loadPopularSeries(MatchService service) async {
  try {
    return parsePopularSeries((await service.getSeries(status: 'ONGOING', page: 1, perPage: 10)).data);
  } catch (_) {
    return const [];
  }
}

/// Ported from RN `PopularSeriesQuickAction`: floating blue pill (bottom-right)
/// listing ongoing series; auto-collapses after 5s of inactivity.
/// Note: RN declares it but no screen currently mounts it; kept for reuse.
class PopularSeriesQuickAction extends StatefulWidget {
  const PopularSeriesQuickAction({super.key, this.screen = 'home', this.bottomOffset = 96, this.service});

  /// 'home' (flash icon) or 'series' (trophy icon).
  final String screen;
  final double bottomOffset;
  final MatchService? service;

  @override
  State<PopularSeriesQuickAction> createState() => _PopularSeriesQuickActionState();
}

class _PopularSeriesQuickActionState extends State<PopularSeriesQuickAction> {
  List<PopularSeriesItem>? _list;
  bool _open = true;
  Timer? _collapseTimer;
  final _guard = TapGuard();

  MatchService get _service => widget.service ?? MatchService.instance;

  @override
  void initState() {
    super.initState();
    loadPopularSeries(_service).then((l) {
      if (!mounted) return;
      setState(() => _list = l);
      _armCollapse();
    });
  }

  void _armCollapse() {
    _collapseTimer?.cancel();
    if (!_open) return;
    _collapseTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _open = false);
    });
  }

  void _setOpen(bool open) {
    setState(() => _open = open);
    _armCollapse();
  }

  Future<void> _openSeries(PopularSeriesItem item) => _guard.run(() async {
        _armCollapse();
        final id = await resolveSeriesId(_service, candidates: [item.key], name: item.name);
        if (!mounted) return;
        if (id == null) return;
        AppNav.seriesDetail(context, id, seriesName: item.name);
      });

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _guard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) return const SizedBox.shrink();
    final icon = widget.screen == 'home' ? Icons.flash_on : Icons.emoji_events;
    final areaHeight = (list.isEmpty ? 1 : list.length) * 62.0;
    final seriesArea = areaHeight.clamp(64.0, 214.0);

    final expanded = Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x33FFFFFF),
          border: Border.all(color: const Color(0x88FBBF24)),
        ),
        child: Icon(icon, size: 18, color: AppColors.goldLight),
      ),
      Container(width: 60, height: 1, color: const Color(0x4DFFFFFF), margin: const EdgeInsets.only(bottom: 8)),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: seriesArea),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: list.length,
          itemBuilder: (context, i) => _item(list[i]),
        ),
      ),
      InkWell(
        key: const ValueKey('common_quick_action_collapse'),
        onTap: () => _setOpen(false),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 40,
          height: 32,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.keyboard_arrow_down, size: 22, color: AppColors.goldLight),
        ),
      ),
    ]);

    final collapsed = InkWell(
      key: const ValueKey('common_quick_action_open'),
      onTap: () => _setOpen(true),
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x40FFFFFF),
          border: Border.all(color: const Color(0x4DFFFFFF)),
        ),
        child: Icon(icon, size: 19, color: AppColors.goldLight),
      ),
    );

    return Positioned(
      right: 14,
      bottom: widget.bottomOffset,
      child: Material(
        color: AppColors.pitch,
        elevation: 12,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedSize(
          duration: Duration(milliseconds: _open ? 280 : 220),
          curve: Curves.easeOutCubic,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(width: _open ? 66 : 40, child: Center(child: _open ? expanded : collapsed)),
          ),
        ),
      ),
    );
  }

  Widget _item(PopularSeriesItem item) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          key: ValueKey('common_quick_action_${item.key}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openSeries(item),
          child: Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0x2EFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x40FFFFFF)),
            ),
            child: Column(children: [
              NetImage(url: item.logo, size: 44, fallbackLetter: item.name, background: const Color(0x26FFFFFF)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(item.shortLabel,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: AppColors.white, height: 1.3)),
              ),
            ]),
          ),
        ),
      );
}
