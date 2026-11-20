import 'package:flutter/material.dart';

import '../logic/match_detail_logic.dart';
import '../logic/match_state.dart';
import '../widgets/match_header.dart' show localStartLabel;
import '../widgets/md_ui.dart';

/// Info tab (research §3.8, PRD §8.4): match facts, weather when supplied,
/// how the target was worked out, then the line-ups ([lineups], gated by
/// the screen). Officials are not in our data, so they are not shown.
class MatchInfoTab extends StatelessWidget {
  const MatchInfoTab({super.key, required this.match, required this.situation, required this.lineups, this.onSeriesTap});
  final MatchDetailVM match;
  final MatchSituation situation;
  final Widget lineups;
  final VoidCallback? onSeriesTap;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final w = m.weather;
    final chase = situation.chase;
    return Column(
      key: const ValueKey('match_detail_info_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MdSectionTitle('Match'),
        if (m.name != null) MdKeyValue(label: 'Match', value: m.name!),
        if (m.seriesName.isNotEmpty)
          MdKeyValue(
            valueKey: const ValueKey('match_detail_info_series'),
            label: 'Series',
            value: m.seriesName,
            onTap: m.seriesKey != null ? onSeriesTap : null,
          ),
        if (m.format != null) MdKeyValue(label: 'Format', value: m.format!),
        MdKeyValue(label: 'Status', value: situation.status.label),
        if (m.ground != null) MdKeyValue(label: 'Venue', value: m.ground!),
        if (m.startTime != null) MdKeyValue(label: 'Start (your time)', value: localStartLabel(m.startTime!)),
        if (m.toss != null) MdKeyValue(valueKey: const ValueKey('match_detail_toss'), label: 'Toss', value: m.toss!),
        if (chase != null)
          MdKeyValue(
            valueKey: const ValueKey('match_detail_target_note'),
            label: 'Target',
            value: chase.targetDerived
                ? '${chase.target}, derived: first-innings runs + 1 (the provider did not send a target)'
                : '${chase.target}',
          ),
        if (chase != null && chase.ballsEstimated)
          const MdNote('Balls left assume the full overs for this format; the provider did not send the overs limit.'),
        if (w != null) ...[
          const MdSectionTitle('Weather'),
          Column(
            key: const ValueKey('match_detail_weather'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (w.condition != null) MdKeyValue(label: 'Conditions', value: w.condition!),
              if (w.temperature != null) MdKeyValue(label: 'Temperature', value: w.temperature!),
              if (w.humidity != null) MdKeyValue(label: 'Humidity', value: '${w.humidity}%'),
              if (w.wind != null) MdKeyValue(label: 'Wind', value: w.wind!),
              if (w.rainForecast != null) MdKeyValue(label: 'Chance of rain', value: '${w.rainForecast}%'),
            ],
          ),
        ],
        const MdSectionTitle('Playing XI'),
        lineups,
      ],
    );
  }
}
