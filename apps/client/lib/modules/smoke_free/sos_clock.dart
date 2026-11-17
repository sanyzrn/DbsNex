/// A deadline survives delayed ticks and page/lifecycle changes. No background
/// alarm is needed: the remaining time is recomputed when the sheet resumes.
int sosSecondsLeft(DateTime deadline, DateTime now) {
  final millis = deadline.difference(now).inMilliseconds;
  return millis <= 0 ? 0 : (millis + 999) ~/ 1000;
}
