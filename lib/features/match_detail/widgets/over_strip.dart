import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/seam_strip.dart';
import '../logic/match_state.dart';

/// The Seam strip for the current over, with the previous overs one swipe
/// (or one tap on the arrows) away. Index 0 is the current over; swiping
/// right reveals the over before it (research §3.4).
///
/// The strip is keyed by over, so a new over starts a fresh strip (no
/// replay); within an over the [SeamStrip] itself drops in exactly one new
/// bead or shows "+N balls" for a catch-up.
class OverStrip extends StatefulWidget {
  const OverStrip({super.key, required this.overs});
  final List<OverView> overs;

  @override
  State<OverStrip> createState() => _OverStripState();
}

class _OverStripState extends State<OverStrip> {
  int _index = 0;

  @override
  void didUpdateWidget(OverStrip old) {
    super.didUpdateWidget(old);
    // A new current over brings the user back to "now".
    if (old.overs.isEmpty ||
        widget.overs.isEmpty ||
        old.overs.first.key != widget.overs.first.key) {
      _index = 0;
    }
    if (_index >= widget.overs.length) _index = 0;
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.overs.length - 1);
    if (next != _index) setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final overs = widget.overs;
    if (overs.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    final ov = overs[_index];
    final summary = <String>[
      if (ov.runs != null) ov.runs == 1 ? '1 run' : '${ov.runs} runs',
      ?ov.bowler,
    ];
    final canOlder = _index < overs.length - 1;
    final canNewer = _index > 0;

    Widget arrow(
      IconData icon,
      String tip,
      bool enabled,
      VoidCallback onTap,
      String key,
    ) => SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        key: ValueKey(key),
        tooltip: tip,
        padding: EdgeInsets.zero,
        iconSize: 22,
        onPressed: enabled ? onTap : null,
        color: p.ink,
        disabledColor: p.hairline,
        icon: Icon(icon),
      ),
    );

    return Semantics(
      container: true,
      label: '${ov.title}${_index == 0 ? ', this over' : ''}',
      child: GestureDetector(
        key: const ValueKey('match_detail_over_strip'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 150) _go(1); // swipe right → earlier over
          if (v < -150) _go(-1);
        },
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: Spacing.md,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _index == 0 && ov.inProgress
                                ? '${ov.title}, this over'
                                : ov.title,
                            key: const ValueKey('match_detail_over_title'),
                            style: AppFont.style(
                              size: 13,
                              weight: FontWeight.w700,
                              color: p.ink,
                              height: 1.3,
                            ),
                          ),
                          for (final s in summary)
                            Text(
                              s,
                              style: AppText.small.copyWith(color: p.inkMuted),
                            ),
                        ],
                      ),
                    ),
                    if (overs.length > 1) ...[
                      arrow(
                        Icons.chevron_left,
                        'Earlier over',
                        canOlder,
                        () => _go(1),
                        'match_detail_over_older',
                      ),
                      arrow(
                        Icons.chevron_right,
                        'Later over',
                        canNewer,
                        () => _go(-1),
                        'match_detail_over_newer',
                      ),
                    ],
                  ],
                ),
                SeamStrip.labels(ov.labels, key: ValueKey('seam_${ov.key}')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
