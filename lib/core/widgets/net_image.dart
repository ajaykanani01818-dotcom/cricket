import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ported from RN `CachedImage`: disk-cached network image with a letter
/// fallback when the URL is missing or fails. Decodes at display size
/// (memCacheWidth) to keep scrolling lists smooth.
class NetImage extends StatelessWidget {
  const NetImage({
    super.key,
    required this.url,
    this.size = 32,
    this.fallbackLetter,
    this.radius,
    this.fit = BoxFit.contain,
    this.background = AppColors.neutralSurface,
  });

  final String? url;
  final double size;
  final String? fallbackLetter;
  final double? radius; // null = circle
  final BoxFit fit;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size / 2;
    final u = url?.trim() ?? '';
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: background,
          child: Text(
            (fallbackLetter?.trim().isNotEmpty ?? false) ? fallbackLetter!.trim()[0].toUpperCase() : '?',
            style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: size,
        height: size,
        child: u.isEmpty || !(u.startsWith('http://') || u.startsWith('https://'))
            ? fallback()
            : CachedNetworkImage(
                imageUrl: u,
                width: size,
                height: size,
                fit: fit,
                memCacheWidth: (size * dpr).round(),
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, _) => Container(color: background),
                errorWidget: (_, _, _) => fallback(),
              ),
      ),
    );
  }
}
