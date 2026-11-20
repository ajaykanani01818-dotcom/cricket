import '../../../core/api/json.dart';

/// View-models for the Playing XI tab (GET /match/:id/playing11 → `data`).

/// RN `getRoleLabel`.
String playingXIRoleLabel(dynamic role) {
  final n = J.number(role);
  switch (n != null && n.isFinite ? n.toInt() : null) {
    case 0:
      return 'Batter';
    case 1:
      return 'Bowler';
    case 2:
      return 'Wicketkeeper';
    case 3:
      return 'Batting all-rounder';
    case 4:
      return 'Bowling all-rounder';
    default:
      return 'Player';
  }
}

class XiPlayer {
  const XiPlayer({
    required this.id,
    required this.name,
    required this.roleLabel,
    required this.isCaptain,
    required this.isWicketKeeper,
    required this.country,
    required this.avatar,
  });
  final String id, name, roleLabel;
  final bool isCaptain, isWicketKeeper;
  final String? country, avatar;
}

class XiTeam {
  const XiTeam({required this.name, required this.logo, required this.players});
  final String name;
  final String? logo;
  final List<XiPlayer> players;
}

class PlayingXIView {
  const PlayingXIView({required this.hasMatch, required this.team1, required this.team2, required this.signature});
  final bool hasMatch;
  final XiTeam team1, team2;
  final String signature;

  static const empty = PlayingXIView(
    hasMatch: false,
    team1: XiTeam(name: '', logo: null, players: []),
    team2: XiTeam(name: '', logo: null, players: []),
    signature: '',
  );

  @override
  bool operator ==(Object other) => other is PlayingXIView && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

/// [data] = `response.data` of /match/:id/playing11. RN shows the empty state
/// when `data.match` is missing.
PlayingXIView parsePlayingXI(dynamic data) {
  final rawMatch = J.map(data)['match'];
  if (rawMatch is! Map || rawMatch.isEmpty) return PlayingXIView.empty;
  final match = J.map(rawMatch);
  final teams = J.map(match['teams']);
  final sig = StringBuffer();

  XiTeam team(String teamKey, String listKey, String fallbackName) {
    final t = J.map(teams[teamKey]);
    final players = <XiPlayer>[];
    final raw = J.maps(match[listKey]);
    for (var i = 0; i < raw.length; i++) {
      final p = raw[i];
      final info = J.map(p['playerInfo']);
      players.add(XiPlayer(
        id: J.text(p['key']) ?? '$listKey-$i',
        name: J.str(p['name']),
        roleLabel: playingXIRoleLabel(p['role']),
        isCaptain: J.boolean(p['isCaptain']),
        isWicketKeeper: J.boolean(info['isWicketKeeper']),
        country: J.text(info['country']),
        avatar: J.text(info['logo']),
      ));
    }
    final xt = XiTeam(name: J.text(t['name']) ?? fallbackName, logo: J.text(t['logo']), players: players);
    sig.write('${xt.name}:${xt.logo}|');
    for (final x in players) {
      sig.write('${x.id}:${x.name}:${x.roleLabel}:${x.isCaptain}:${x.isWicketKeeper}:${x.country}:${x.avatar}|');
    }
    return xt;
  }

  final t1 = team('team1', 'playingXI_Team1', 'Team 1');
  final t2 = team('team2', 'playingXI_Team2', 'Team 2');
  return PlayingXIView(hasMatch: true, team1: t1, team2: t2, signature: sig.toString());
}

/// Bench / substitutes and wicketkeeper flags from GET /match/:id/squad.
class SquadView {
  const SquadView({this.bench1 = const [], this.bench2 = const [], this.keepers = const {}});
  final List<XiPlayer> bench1, bench2;

  /// Player keys flagged `isWicketKeeper` in the squad payload.
  final Set<String> keepers;

  static const empty = SquadView();

  String get signature =>
      '${bench1.map((p) => p.id).join(',')}|${bench2.map((p) => p.id).join(',')}|${(keepers.toList()..sort()).join(',')}';
}

SquadView parseSquad(dynamic data) {
  final rawMatch = J.map(data)['match'];
  if (rawMatch is! Map) return SquadView.empty;
  final m = J.map(rawMatch);
  final keepers = <String>{};
  for (final k in ['playingXI_Team1', 'playingXI_Team2', 'bench_Team1', 'bench_Team2', 'substitutes_Team1', 'substitutes_Team2']) {
    for (final p in J.maps(m[k])) {
      if (J.boolean(p['isWicketKeeper'])) {
        final key = J.text(p['key']);
        if (key != null) keepers.add(key);
      }
    }
  }
  List<XiPlayer> bench(String team) {
    final out = <XiPlayer>[];
    for (final k in ['bench_$team', 'substitutes_$team']) {
      final raw = J.maps(m[k]);
      for (var i = 0; i < raw.length; i++) {
        final p = raw[i];
        final name = J.text(p['name']);
        if (name == null) continue;
        out.add(XiPlayer(
          id: J.text(p['key']) ?? '$k-$i',
          name: name,
          roleLabel: playingXIRoleLabel(p['role']),
          isCaptain: J.boolean(p['isCaptain']),
          isWicketKeeper: J.boolean(p['isWicketKeeper']),
          country: null,
          avatar: J.text(p['logo']),
        ));
      }
    }
    return out;
  }

  return SquadView(bench1: bench('Team1'), bench2: bench('Team2'), keepers: keepers);
}
