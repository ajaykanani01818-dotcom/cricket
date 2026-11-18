/// Ported from RN `src/utils/fixtureStatus.ts`.
enum FixtureCardKind { live, completed, abandoned, cancelled, scheduled }

class FixtureDisplay {
  final FixtureCardKind kind;
  final String statusLine;
  final bool isLive;
  const FixtureDisplay(this.kind, this.statusLine, this.isLive);
}

const _pastInferCancelAfterHours = 5;

String _norm(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_').replaceAll(RegExp(r'[^A-Z0-9_]'), '').trim();

FixtureDisplay resolveSeriesFixtureDisplay(String statusRaw, String dateIso, [String? resultMessage, DateTime? now]) {
  final matchTime = DateTime.tryParse(dateIso);
  final current = now ?? DateTime.now();
  final clearlyPastUndecided =
      matchTime != null && current.difference(matchTime).inMinutes / 60 >= _pastInferCancelAfterHours;
  final key = _norm(statusRaw);
  final msg = resultMessage?.trim() ?? '';

  if (key == 'LIVE' || key == 'IN_PROGRESS' || key.contains('LIVE')) {
    return const FixtureDisplay(FixtureCardKind.live, 'Live', true);
  }
  const completed = {'COMPLETED', 'FINISHED', 'COMPLETE', 'RESULT', 'ENDED', 'TIED', 'TIE', 'DRAW', 'DRAWN'};
  if (completed.contains(key)) {
    return FixtureDisplay(FixtureCardKind.completed, msg.isNotEmpty ? msg : (statusRaw.isNotEmpty ? statusRaw : 'Completed'), false);
  }
  if (key == 'ABANDONED' || key.contains('ABANDON')) {
    return FixtureDisplay(FixtureCardKind.abandoned, msg.isNotEmpty ? msg : 'Abandoned', false);
  }
  if (key.contains('CANCEL') || {'WASH_OUT', 'WASHOUT', 'NO_RESULT', 'MATCH_ABANDONED'}.contains(key)) {
    return FixtureDisplay(FixtureCardKind.cancelled, msg.isNotEmpty ? msg : 'Cancelled', false);
  }
  if (clearlyPastUndecided) return const FixtureDisplay(FixtureCardKind.cancelled, 'Cancelled', false);
  if (key == 'NOT_STARTED' || key == 'NOTSTARTED') {
    return const FixtureDisplay(FixtureCardKind.scheduled, 'Not started', false);
  }
  return FixtureDisplay(FixtureCardKind.scheduled, statusRaw.isNotEmpty ? statusRaw : 'Scheduled', false);
}
