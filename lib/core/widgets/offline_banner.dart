import 'package:flutter/material.dart';

import '../network/network_status.dart';
import '../theme/app_theme.dart';

/// Ported from RN `OfflineBanner`.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: NetworkStatus.instance,
        builder: (context, online, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: online
              ? const SizedBox.shrink()
              : Material(
                  key: const ValueKey('offline_banner'),
                  color: AppColors.live,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                        Icon(Icons.wifi_off, size: 16, color: AppColors.white),
                        SizedBox(width: 6),
                        Text('No internet connection', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      ]),
                    ),
                  ),
                ),
        ),
      );
}
