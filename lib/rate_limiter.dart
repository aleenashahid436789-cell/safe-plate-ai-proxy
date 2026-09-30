// server/lib/rate_limiter.dart
//
// In-memory rate limiting: per-device daily caps on each endpoint, plus a
// global daily call budget as a hard ceiling on total Gemini spend.
//
// This is a single-instance, in-memory limiter — good enough for a v1
// Cloud Run deployment pinned to minInstances=1/maxInstances=1. If you
// scale to multiple instances later, move these counters to Firestore or
// Redis so they're shared across instances.

class RateLimiter {
  final Map<String, _Counter> _perDevice = {};
  final _Counter _global = _Counter();

  final int perDeviceDailyLimit;
  final int globalDailyBudget;

  RateLimiter({required this.perDeviceDailyLimit, required this.globalDailyBudget});

  /// Returns null if allowed, or a reason string if the request should be
  /// rejected (429).
  String? check(String deviceId) {
    _global.rollIfNewDay();
    if (_global.count >= globalDailyBudget) {
      return 'Daily server-wide request budget reached. Try again tomorrow.';
    }

    final counter = _perDevice.putIfAbsent(deviceId, () => _Counter());
    counter.rollIfNewDay();
    if (counter.count >= perDeviceDailyLimit) {
      return 'Daily request limit reached for this device. Try again tomorrow.';
    }

    counter.count++;
    _global.count++;
    return null;
  }

  /// Drop counters for devices untouched in the last 2 days, so memory
  /// doesn't grow unbounded over the life of a long-running instance.
  void sweep() {
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    _perDevice.removeWhere((_, c) => c.dayStart.isBefore(cutoff));
  }
}

class _Counter {
  int count = 0;
  DateTime dayStart = DateTime.now();

  void rollIfNewDay() {
    final now = DateTime.now();
    if (now.difference(dayStart) > const Duration(hours: 24)) {
      count = 0;
      dayStart = now;
    }
  }
}
