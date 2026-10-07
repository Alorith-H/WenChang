import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenchang/services/srs_service.dart';

/// 「几月几日已学」徽章的数据层：lastLearnedDay 取最新一次学习日，
/// lastLearnedLabel 按 今天 / 今年历史 / 跨年 / 从未学过 四态出文案。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SrsService srs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    srs = await SrsService.load();
  });

  test('lastLearnedDay 多天记录返回最新、互不干扰、从未学过返回 null', () async {
    await srs.markLearned('sec-a', const [], DateTime(2026, 10, 4));
    await srs.markLearned('sec-b', const [], DateTime(2026, 10, 5));
    await srs.markLearned('sec-a', const [], DateTime(2026, 10, 6));
    await srs.markLearned('sec-c', const [], DateTime(2026, 10, 6));

    expect(srs.lastLearnedDay('sec-a'), '2026-10-06'); // 多天 → 最新
    expect(srs.lastLearnedDay('sec-b'), '2026-10-05');
    expect(srs.lastLearnedDay('sec-c'), '2026-10-06'); // 同天多板块互不干扰
    expect(srs.lastLearnedDay('sec-never'), isNull);
  });

  test('lastLearnedLabel 今天 → 今日已学，从未学过 → 空串', () async {
    final now = DateTime(2026, 10, 6);
    await srs.markLearned('today', const [], DateTime(2026, 10, 6));

    expect(srs.lastLearnedLabel('today', now), '今日已学');
    expect(srs.lastLearnedLabel('sec-never', now), '');
  });

  test('lastLearnedLabel 今年历史 → M月D日已学', () async {
    final now = DateTime(2026, 10, 6);
    await srs.markLearned('oct', const [], DateTime(2026, 10, 4));
    await srs.markLearned('jan', const [], DateTime(2026, 1, 2));

    expect(srs.lastLearnedLabel('oct', now), '10月4日已学');
    expect(srs.lastLearnedLabel('jan', now), '1月2日已学');
  });

  test('lastLearnedLabel 跨年 → 带年份的 yyyy-MM-dd 已学', () async {
    final now = DateTime(2026, 10, 6);
    await srs.markLearned('last-year', const [], DateTime(2025, 12, 31));

    expect(srs.lastLearnedLabel('last-year', now), '2025-12-31 已学');
  });
}
