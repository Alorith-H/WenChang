import 'package:flutter_test/flutter_test.dart';
import 'package:wenchang/services/srs_logic.dart';

void main() {
  final day0 = DateTime(2026, 10, 6);

  test('熟练: 3 cumulative goodCount → mature, no due', () {
    var s = SrsState.initial();
    s = applyGrade(s, Grade.good, day0); // goodCount 1, interval 1, due +1
    expect(s.goodCount, 1);
    expect(s.streak, 1);
    expect(s.interval, 1);
    expect(s.due, '2026-10-07');
    expect(s.mature, isFalse);

    s = applyGrade(s, Grade.good, day0); // goodCount 2, interval 2, due +2
    expect(s.goodCount, 2);
    expect(s.streak, 2);
    expect(s.interval, 2);
    expect(s.due, '2026-10-08');

    s = applyGrade(s, Grade.good, day0); // goodCount 3 → mature
    expect(s.goodCount, 3);
    expect(s.mature, isTrue);
    expect(s.due, isNull);
  });

  test('累计 3 次熟练毕业，生疏/忘记不清零 goodCount', () {
    // good, good, hard, good → 累计 3 次 → mature（不看连续）。
    var s = SrsState.initial();
    s = applyGrade(s, Grade.good, day0);
    s = applyGrade(s, Grade.good, day0);
    expect(s.goodCount, 2);
    s = applyGrade(s, Grade.hard, day0);
    expect(s.goodCount, 2); // 生疏不清零
    expect(s.mature, isFalse);
    s = applyGrade(s, Grade.good, day0);
    expect(s.goodCount, 3);
    expect(s.mature, isTrue);

    // 忘记同样不清零：good, again, good, good → mature。
    s = SrsState.initial();
    s = applyGrade(s, Grade.good, day0);
    s = applyGrade(s, Grade.again, day0);
    expect(s.goodCount, 1);
    expect(s.streak, 0); // 连续计数照旧被重置（仅作展示）
    s = applyGrade(s, Grade.good, day0);
    s = applyGrade(s, Grade.good, day0);
    expect(s.goodCount, 3);
    expect(s.mature, isTrue);
  });

  test('熟练 interval caps at 30 days', () {
    const s = SrsState(interval: 20, streak: 1, goodCount: 1);
    final next = applyGrade(s, Grade.good, day0);
    expect(next.interval, 30);
    expect(next.goodCount, 2);
    expect(next.due, '2026-11-05');
  });

  test('生疏 halves the interval, min 1 day', () {
    var s = applyGrade(const SrsState(interval: 4), Grade.hard, day0);
    expect(s.interval, 2);
    expect(s.streak, 0);
    expect(s.due, '2026-10-08');

    s = applyGrade(const SrsState(interval: 1), Grade.hard, day0);
    expect(s.interval, 1);

    s = applyGrade(SrsState.initial(), Grade.hard, day0);
    expect(s.interval, 1);
    expect(s.due, '2026-10-07');
  });

  test('忘记 schedules tomorrow', () {
    final s = applyGrade(const SrsState(interval: 9, streak: 2), Grade.again, day0);
    expect(s.interval, 1);
    expect(s.streak, 0);
    expect(s.goodCount, 0);
    expect(s.due, '2026-10-07');
    expect(s.mature, isFalse);
  });

  test('date helpers round-trip', () {
    expect(formatDay(day0), '2026-10-06');
    expect(addDays(day0, 30), '2026-11-05');
    expect(parseDay('2026-10-06'), day0);
    expect(parseDay('not-a-date'), isNull);
  });

  test('SrsState json round-trip', () {
    const s = SrsState(
      interval: 4,
      streak: 2,
      goodCount: 2,
      mature: false,
      due: '2026-10-09',
    );
    final back = SrsState.fromJson(s.toJson());
    expect(back.interval, 4);
    expect(back.streak, 2);
    expect(back.goodCount, 2);
    expect(back.mature, isFalse);
    expect(back.due, '2026-10-09');
  });

  test('legacy json (no goodCount) migrates from streak', () {
    // streak < 3：goodCount 取 streak，未成熟。
    final a = SrsState.fromJson({
      'interval': 4,
      'streak': 2,
      'mature': false,
      'due': '2026-10-09',
    });
    expect(a.goodCount, 2);
    expect(a.mature, isFalse);

    // streak ≥ 3：直接标成熟。
    final b = SrsState.fromJson({
      'interval': 8,
      'streak': 3,
      'mature': true,
    });
    expect(b.goodCount, 3);
    expect(b.mature, isTrue);

    // 旧数据带 mature 标志但无 goodCount 时也不会"变年轻"。
    final c = SrsState.fromJson({'interval': 2, 'streak': 5, 'mature': true});
    expect(c.goodCount, 5);
    expect(c.mature, isTrue);
  });
}
