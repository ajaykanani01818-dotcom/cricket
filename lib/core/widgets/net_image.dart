import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Max decoded width for logos (perf budget: logos ≤ 96 px, avatars ≤ 144).
const int kLogoDecodeMax = 96;
const int kAvatarDecodeMax = 144;

/// Disk-cached network image with an initials fallback when the URL is
/// missing or fails. Decodes at display size, capped at [decodeMax] px.
class NetImage extends StatelessWidget {
  const NetImage({
    super.key,
    required this.url,
    this.size = 32,
    this.fallbackLetter,
    this.radius,
    this.fit = BoxFit.contain,
    this.background,
    this.decodeMax = kAvatarDecodeMax,
  });

  final String? url;
  final double size;
  final String? fallbackLetter;
  final double? radius; // null = circle
  final BoxFit fit;

  /// Defaults to the palette's surfaceAlt.
  final Color? background;
  final int decodeMax;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = background ?? p.surfaceAlt;
    final r = radius ?? size / 2;
    final u = url?.trim() ?? '';
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decode = math.min(decodeMax, (size * dpr).round());
    Widget fallback() => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: bg,
      child: Text(
        initialsOf(fallbackLetter, max: 1),
        style: AppFont.style(
          size: size * 0.42,
          weight: FontWeight.w800,
          color: p.inkMuted,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: size,
        height: size,
        child:
            u.isEmpty || !(u.startsWith('http://') || u.startsWith('https://'))
            ? fallback()
            : CachedNetworkImage(
                imageUrl: u,
                width: size,
                height: size,
                fit: fit,
                memCacheWidth: decode,
                fadeInDuration: const Duration(milliseconds: 120),
                placeholder: (_, _) => ColoredBox(color: bg),
                errorWidget: (_, _, _) => fallback(),
              ),
      ),
    );
  }
}

/// "India" → "IN", "Sri Lanka" → "SL", "PAK" → "PA" (max 2); '?' if empty.
String initialsOf(String? name, {int max = 2}) {
  final n = (name ?? '').trim();
  if (n.isEmpty) return '?';
  final words = n.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final s = words.length >= 2
      ? words.take(max).map((w) => w[0]).join()
      : n.substring(0, math.min(max, n.length));
  return s.toUpperCase();
}

/// Team logo on a light rounded chip (logos are drawn for light
/// backgrounds, so the chip stays light in dark mode too). Falls back to
/// initials. Decoded at ≤ 96 px.
class TeamLogo extends StatelessWidget {
  const TeamLogo({
    super.key,
    required this.url,
    required this.name,
    this.size = 32,
  });
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final u = url?.trim() ?? '';
    final hasUrl = u.startsWith('http://') || u.startsWith('https://');
    final radius = size * 0.22;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final inner = size - 4;
    Widget initials() => Center(
      child: Text(
        initialsOf(name),
        maxLines: 1,
        style: AppFont.style(
          size: size * 0.36,
          weight: FontWeight.w800,
          color: AppPalette.light.inkMuted,
          height: 1,
        ),
      ),
    );
    return Semantics(
      label: name.isEmpty ? null : '$name logo',
      image: true,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: p.logoChip,
          borderRadius: BorderRadius.circular(radius),
          border: p.isDark ? null : Border.all(color: p.hairline),
        ),
        alignment: Alignment.center,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: u,
                width: inner,
                height: inner,
                fit: BoxFit.contain,
                memCacheWidth: math.min(kLogoDecodeMax, (inner * dpr).round()),
                fadeInDuration: const Duration(milliseconds: 120),
                placeholder: (_, _) => const SizedBox.shrink(),
                errorWidget: (_, _, _) => initials(),
              )
            : initials(),
      ),
    );
  }
}
