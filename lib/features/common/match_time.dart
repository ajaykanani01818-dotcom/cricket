import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Pure date/countdown helpers shared by the match cards (ported from the
/// inline helpers of RN UpcomingMatchCard / CountdownTimer / HomeScreen).

/// "Starts in" label used by UpcomingMatchCard's big countdown (RN StartsInBig):
/// `Xd Yh` / `Xh Ym` / `Xm`; null when the start is in the past.
String? startsInLabel(DateTime target, DateTime now) {
  final diff = target.difference(now);
  if (diff.inMilliseconds <= 0) return null;
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// RN CountdownTimer: only for matches starting within 24 hours.
String? countdownWithin24h(DateTime target, DateTime now) {
  final diff = target.difference(now);
  if (diff.inMilliseconds <= 0 || diff > const Duration(hours: 24)) return null;
  final hours = diff.inHours;
  final minutes = diff.inMinutes % 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

/// RN `formatTime`: Today / Tomorrow / "Nov 18" + "03:30 PM" (local time).
({String dayLabel, String time}) formatMatchTime(DateTime date, DateTime now) {
  final d = date.toLocal();
  final n = now.toLocal();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(n.year, n.month, n.day);
  final tomorrow = DateTime(n.year, n.month, n.day + 1);
  final String dayLabel;
  if (day == today) {
    dayLabel = 'Today';
  } else if (day == tomorrow) {
    dayLabel = 'Tomorrow';
  } else {
    dayLabel = DateFormat('MMM d', 'en_US').format(d);
  }
  return (dayLabel: dayLabel, time: DateFormat('hh:mm a', 'en_US').format(d));
}

/// RN HomeScreen `formatSeriesDate`: "Nov 19"; '-' when unparseable.
String formatShortDate(String iso) {
  final d = DateTime.tryParse(iso.trim());
  return d == null ? '-' : DateFormat('MMM d', 'en_US').format(d.toLocal());
}

/// One shared minute ticker for every countdown on screen (instead of one
/// Timer per card). Runs only while something listens.
class MinuteClock extends ChangeNotifier {
  MinuteClock._();
  static final MinuteClock instance = MinuteClock._();

  /// Overridable in tests.
  @visibleForTesting
  static DateTime Function() nowFn = DateTime.now;
  static DateTime now() => nowFn();

  Timer? _timer;
  int _listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _listeners++;
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => notifyListeners());
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _listeners--;
    if (_listeners <= 0) {
      _listeners = 0;
      _timer?.cancel();
      _timer = null;
    }
  }

  @visibleForTesting
  bool get isTicking => _timer != null;

  @visibleForTesting
  void debugTick() => notifyListeners();
}
