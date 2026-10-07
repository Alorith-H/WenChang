/// Pure spaced-repetition logic — no Flutter / storage dependencies, so it is
/// easy to unit test and reason about.
library;

import 'dart:math' as math;

/// Answer grade tapped on a review card.
enum Grade {
  /// 熟练
  good,

  /// 生疏
  hard,

  /// 忘记
  again,
}

/// Date helpers using local calendar days, formatted as `yyyy-MM-dd`.
String formatDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Parses a `yyyy-MM-dd` string; returns null when malformed.
DateTime? parseDay(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

/// Today + [days] as `yyyy-MM-dd`.
String addDays(DateTime from, int days) => formatDay(from.add(Duration(days: days)));

/// Per-question SRS state persisted as JSON in shared_preferences.
class SrsState {
  /// Current interval in days (0 = never graded).
  final int interval;

  /// Consecutive 熟练 answers (informational; graduation uses [goodCount]).
  final int streak;

  /// Lifetime total of 熟练 answers — 3 cumulative → mature. 生疏/忘记
  /// never reset or interrupt it, they only slow the interval down.
  final int goodCount;

  /// Once true the question is retired from the queue.
  final bool mature;

  /// Next due day (`yyyy-MM-dd`), null when not due / mature.
  final String? due;

  const SrsState({
    this.interval = 0,
    this.streak = 0,
    this.goodCount = 0,
    this.mature = false,
    this.due,
  });

  factory SrsState.initial() => const SrsState();

  factory SrsState.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return SrsState.initial();
    final interval = json['interval'];
    final streak = json['streak'];
    final due = json['due'];
    final goodCount = json['goodCount'];
    // Migration: records written before `goodCount` existed fall back to the
    // old consecutive streak — a streak of 3+ already meant "graduated".
    final migrated = goodCount is! int;
    final good = migrated ? (streak is int ? streak : 0) : goodCount;
    return SrsState(
      interval: interval is int ? interval : 0,
      streak: streak is int ? streak : 0,
      goodCount: good,
      mature: json['mature'] == true || (migrated && good >= 3),
      due: due is String && due.isNotEmpty ? due : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'interval': interval,
        'streak': streak,
        'goodCount': goodCount,
        'mature': mature,
        if (due != null) 'due': due,
      };
}

/// Applies one answer grade to a question's state.
///
/// - 熟练: goodCount += 1; **3 cumulative** 熟练 → mature (no due).
///   Otherwise interval = 0→1 else min(30, interval*2), due = today + interval.
/// - 生疏: interval = 0→1 else max(1, interval ~/ 2), due = today + interval.
/// - 忘记: interval = 1, due = today + 1.
///
/// 生疏/忘记 never touch `goodCount` — they only slow the interval down
/// (the informational consecutive `streak` is still reset). Graduation is
/// lifetime-cumulative, not consecutive, so a bad answer cannot undo
/// progress toward mature.
///
/// All due distances are clamped to 1..30 days.
SrsState applyGrade(SrsState state, Grade grade, DateTime today) {
  switch (grade) {
    case Grade.good:
      final streak = state.streak + 1;
      final goodCount = state.goodCount + 1;
      if (goodCount >= 3) {
        return SrsState(
          interval: state.interval,
          streak: streak,
          goodCount: goodCount,
          mature: true,
        );
      }
      final interval =
          state.interval == 0 ? 1 : math.min(30, state.interval * 2);
      return SrsState(
        interval: interval,
        streak: streak,
        goodCount: goodCount,
        mature: false,
        due: addDays(today, interval),
      );
    case Grade.hard:
      final interval = state.interval == 0
          ? 1
          : math.min(30, math.max(1, state.interval ~/ 2));
      return SrsState(
        interval: interval,
        streak: 0,
        goodCount: state.goodCount,
        mature: false,
        due: addDays(today, interval),
      );
    case Grade.again:
      return SrsState(
        interval: 1,
        streak: 0,
        goodCount: state.goodCount,
        mature: false,
        due: addDays(today, 1),
      );
  }
}
