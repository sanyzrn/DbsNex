import 'dart:async';

/// Repaint day-based facts at the next civil midnight, without storage reads.
class QuitDayClock {
  QuitDayClock(this.onDay);
  final void Function() onDay;
  Timer? _timer;
  void start() {
    stop();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(next.difference(now), () {
      onDay();
      start();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
