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

/// 「标熟」按钮的纯逻辑：把 [state] 直接置为成熟态 —— goodCount 至少补到
/// 3（与「累计 3 次正确毕业」同一数据结构与判定），due 清空。该题从此被
/// buildReviewQueue 排除，永远不再进入复习队列。
SrsState forceMature(SrsState state) => SrsState(
      interval: state.interval,
      streak: state.streak,
      goodCount: math.max(state.goodCount, 3),
      mature: true,
    );

// ------------------------------------------------------------- 忘记重排

/// 单次复习会话内，每道题最多被「忘记」重排到队尾的次数（sessionRequeues
/// 上限）—— 超限不再追加，防止忘记 → 重排 → 忘记死循环。
const int kSessionRequeues = 3;

/// [requeueForgotten] 的结果：更新后的队列与重排计数；[appended] 表示这次
/// 是否真的把题追加到了队尾（超限 / 空 id 为 false）。
class RequeueOutcome {
  final List<String> ids;
  final Map<String, int> requeues;
  final bool appended;

  const RequeueOutcome({
    required this.ids,
    required this.requeues,
    required this.appended,
  });
}

/// 忘记重排的纯函数：评为「忘记」的 [id] 追加到 [ids] 队尾（同一次会话内
/// 稍后再次出现）。[requeues] 是 id → 本会话已重排次数，达到 [limit]
/// （默认 [kSessionRequeues]）就不再追加；正常结束不设上限之外的特判。
/// 入参不被修改。
RequeueOutcome requeueForgotten(
  List<String> ids,
  String id,
  Map<String, int> requeues, {
  int limit = kSessionRequeues,
}) {
  final used = requeues[id] ?? 0;
  if (id.isEmpty || used >= limit) {
    return RequeueOutcome(
      ids: List<String>.of(ids),
      requeues: Map<String, int>.of(requeues),
      appended: false,
    );
  }
  return RequeueOutcome(
    ids: <String>[...ids, id],
    requeues: Map<String, int>.of(requeues)..[id] = used + 1,
    appended: true,
  );
}

/// 已答（去重口径，每题只算一次）：队列前缀里已经作答过的**不同题数**
/// （任何评级都算，含忘记）。注意这不是复习页顶部计数的「完成」口径 ——
/// 完成口径只算 生疏/熟练，由会话的 completed 集合维护
/// （见 `SrsService.completeInSession`）。
int distinctAnswered(List<String> ids, int index) {
  final end = index.clamp(0, ids.length).toInt();
  return ids.sublist(0, end).toSet().length;
}

/// 「今日待复习」剩余（去重口径，首页用）：后缀中没在前缀（已答）出现过
/// 的不同题数。忘记重排出队尾的副本已答过，不计入剩余，因此重排既不会
/// 让「已答」提前、也不会推后。
int distinctRemaining(List<String> ids, int index) {
  final start = index.clamp(0, ids.length).toInt();
  final seen = ids.sublist(0, start).toSet();
  var count = 0;
  for (var i = start; i < ids.length; i++) {
    if (seen.add(ids[i])) count++;
  }
  return count;
}

// ------------------------------------------------------------- 标熟移除

/// [removeFromQueue] 的结果：移除后的队列与校正过的进度下标。
class QueueRemoval {
  final List<String> ids;
  final int index;

  const QueueRemoval(this.ids, this.index);

  /// 队列已走完（下标顶到末尾）—— 会话就此结束。
  bool get done => index >= ids.length;
}

/// 标熟移除的纯函数：把 [id] 从 [ids] 里的**全部出现**（含队尾重排副本）
/// 移除并校正进度下标 —— 当前项被移除后下标保持指向下一题；前面的副本被
/// 移除则下标相应前移。队列里没有 [id] 时原样返回。
QueueRemoval removeFromQueue(List<String> ids, int index, String id) {
  final out = <String>[];
  var removedBefore = 0;
  for (var i = 0; i < ids.length; i++) {
    if (ids[i] == id) {
      if (i < index) removedBefore++;
      continue;
    }
    out.add(ids[i]);
  }
  if (out.length == ids.length) {
    return QueueRemoval(List<String>.of(ids), index);
  }
  final next = (index - removedBefore).clamp(0, out.length).toInt();
  return QueueRemoval(out, next);
}
