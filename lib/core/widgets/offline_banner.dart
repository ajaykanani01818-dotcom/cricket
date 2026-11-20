import 'package:flutter/material.dart';

import '../network/network_status.dart';
import '../theme/app_theme.dart';

/// Offline strip at the top of the shell: ink band, surface text (not the
/// live red, which is reserved for live). Says what is shown and that it
/// recovers by itself. Zero height while online.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: NetworkStatus.instance,
    builder: (context, online, _) {
      if (online) return const SizedBox.shrink();
      final p = context.palette;
      return Semantics(
        liveRegion: true,
        child: Material(
          key: const ValueKey('offline_banner'),
          color: p.ink,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 16, color: p.surface),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "You're offline. Scores update when you reconnect.",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.style(
                        size: 13,
                        weight: FontWeight.w600,
                        color: p.surface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
