import 'dart:async';

/// Prevents double taps from pushing the same route twice: taps are ignored
/// while a guarded async action runs (e.g. a series id being resolved) and
/// for a short cooldown after it (covers the push transition). Call
/// [dispose] from the owning State's dispose.
class TapGuard {
  TapGuard({this.cooldown = const Duration(milliseconds: 800)});
  final Duration cooldown;

  bool _running = false;
  Timer? _cooldownTimer;

  bool get busy => _running || _cooldownTimer != null;

  /// [action] should START navigation (don't await the pushed route's result).
  Future<void> run(FutureOr<void> Function() action) async {
    if (busy) return;
    _running = true;
    try {
      await action();
    } catch (_) {
      // A failed navigation must never leave the guard stuck.
    } finally {
      _running = false;
      if (cooldown > Duration.zero) {
        _cooldownTimer = Timer(cooldown, () => _cooldownTimer = null);
      }
    }
  }

  void dispose() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }
}
