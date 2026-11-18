import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Ported from RN `MatchSectionTitle`. The RN version takes an emoji string;
/// this one takes a Material [IconData] (callers map their emoji).
/// variant: 'default' | 'stat' | 'currentOver' ('currentOver' pulses the icon
/// with a gold glow: opacity 1→0.25, scale 1→1.22, 800ms each way).
class MatchSectionTitle extends StatefulWidget {
  const MatchSectionTitle({super.key, required this.icon, required this.label, this.variant = 'default'});
  final IconData icon;
  final String label;
  final String variant;

  @override
  State<MatchSectionTitle> createState() => _MatchSectionTitleState();
}

class _MatchSectionTitleState extends State<MatchSectionTitle> with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  bool get _isStat => widget.variant == 'stat';
  bool get _isCurrentOver => widget.variant == 'currentOver';

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(MatchSectionTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variant != widget.variant) _syncAnimation();
  }

  void _syncAnimation() {
    if (_isCurrentOver) {
      _pulse ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    } else {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = _isCurrentOver ? 22.0 : _isStat ? 18.0 : 20.0;
    final iconGap = _isStat ? 8.0 : 10.0;
    Widget icon = Icon(
      widget.icon,
      size: iconSize,
      color: _isCurrentOver ? AppColors.gold : AppColors.pitch,
      shadows: _isCurrentOver ? const [Shadow(color: AppColors.gold, blurRadius: 16)] : null,
    );
    final pulse = _pulse;
    if (pulse != null) {
      icon = FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.25).animate(pulse),
        child: ScaleTransition(scale: Tween<double>(begin: 1, end: 1.22).animate(pulse), child: icon),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: _isCurrentOver ? 8 : _isStat ? 4 : 12),
      child: Padding(
        padding: _isCurrentOver ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          children: [
            SizedBox(height: iconSize + 4, child: Center(child: icon)),
            SizedBox(width: iconGap),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _isStat ? 16 : 15,
                  fontWeight: _isStat ? FontWeight.w800 : FontWeight.w700,
                  letterSpacing: _isCurrentOver ? 0.2 : _isStat ? 0.15 : 0,
                  height: _isCurrentOver ? 22 / 15 : null,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
