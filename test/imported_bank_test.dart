import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenchang/models/models.dart';
import 'package:wenchang/services/app_data.dart';
import 'package:wenchang/services/backup_transfer.dart';
import 'package:wenchang/services/content_overrides.dart';
import 'package:wenchang/services/custom_questions.dart';
import 'package:wenchang/services/favorites.dart';
import 'package:wenchang/services/imported_bank.dart';

/// 议题 #3 持久层：导入数据落 SharedPreferences、AppData 加载优先级
/// （有导入版用导入版 / **按段**回退 assets / 损坏回退不崩），以及
/// **进度红线** —— 导入只碰五个数据 key，SRS 进度 / 打卡 / 练习历史
/// 的 key 一个都不动。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  List<Map<String, dynamic>> importedQuestions() => <Map<String, dynamic>>[
    {
      'id': 'imp-1',
      'sec': 'imp-s1',
      'q': '导入题干',
      'a': '导入答案',
      'src': '',
    },
  ];

  Map<String, dynamic> importedSource() => <String, dynamic>{
    'title': '导入提纲',
    'subtitle': <String>[],
    'chapters': <Map<String, dynamic>>[
      {
        'id': 'imp-c1',
        'title': '导入章',
        'sections': <Map<String, dynamic>>[
          {'id': 'imp-s1', 'title': '导入节', 'items': [], 'bullets': []},
        ],
      },
    ],
  };

  group('AppData 加载优先级', () {
    test('无导入 key → assets；有导入版 → 导入版（两段按段各自判断）', () async {
      // 1) 默认回退 assets。
      final assets = await AppData.load();
      expect(assets.questions, isNotEmpty, reason: 'assets 题库能加载');
      expect(assets.questions.any((e) => e.id == 'imp-1'), isFalse);
      expect(assets.chapters, isNotEmpty, reason: 'assets 资料能加载');

      // 2) 只有 imported_questions → 题库用导入版，资料仍是 assets。
      SharedPreferences.setMockInitialValues({
        kImportedQuestionsKey: jsonEncode(importedQuestions()),
      });
      final half = await AppData.load();
      expect(half.questions.single.id, 'imp-1');
      expect(
        half.doc.title,
        assets.doc.title,
        reason: '资料段没有导入 → 按段回退 assets',
      );

      // 3) 两段都有 → 全用导入版，索引一并重建。
      SharedPreferences.setMockInitialValues({
        kImportedQuestionsKey: jsonEncode(importedQuestions()),
        kImportedSourceKey: jsonEncode(importedSource()),
      });
      final full = await AppData.load();
      expect(full.questions.single.id, 'imp-1');
      expect(full.questions.single.q, '导入题干');
      expect(full.doc.title, '导入提纲');
      expect(full.totalSections, 1);
      expect(full.sectionIndex.keys, ['imp-s1']);
      expect(full.questionsBySec['imp-s1']!.single.id, 'imp-1');
    });

    test('损坏的导入存储 → 该段回退 assets，不崩', () async {
      final assets = await AppData.load();
      SharedPreferences.setMockInitialValues({
        kImportedQuestionsKey: 'not-json{{',
        kImportedSourceKey: '"不是对象"',
      });
      final data = await AppData.load();
      expect(data.questions.length, assets.questions.length);
      expect(data.chapters.length, assets.chapters.length);

      final bank = await ImportedBank.load();
      expect(bank.isEmpty, isTrue);
      expect(bank.questions, isNull);
      expect(bank.source, isNull);
    });
  });

  group('persistImportedBackup 落库', () {
    test('整份数据：五个 key 全写 + 各服务 reload 往返', () async {
      final data = BackupData(
        questions: [
          Question(id: 'imp-1', sec: 's9', q: '导入题', a: '导入答', src: '出'),
        ],
        source: SourceDoc(title: '导入提纲', subtitle: const ['副'], chapters: const [
          Chapter(
            id: 'c9',
            title: '章九',
            sections: [
              Section(id: 's9', title: '节九', items: [], bullets: []),
            ],
          ),
        ]),
        overrides: {
          'bullet': {'s9:-1:0': '改过的要点'},
          'question': {
            'imp-1': {'q': '纠错题干'},
          },
        },
        custom: const [
          CustomQuestion(id: 'cq-1', sec: 's9', q: '自建题', a: '自建答'),
        ],
        favoriteQids: const ['imp-1', 'cq-1'],
      );
      await persistImportedBackup(data);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kImportedQuestionsKey), contains('imp-1'));
      expect(prefs.getString(kImportedSourceKey), contains('导入提纲'));
      expect(prefs.getString(kContentOverridesKey), contains('改过的要点'));
      expect(prefs.getString(kCustomQuestionsKey), contains('自建题'));
      expect(prefs.getString(kFavoriteQidsKey), contains('imp-1'));
      expect(prefs.getString(kImportedAtKey), isNotNull);

      // 往返：四个读取方都拿到导入内容。
      final bank = await ImportedBank.load();
      expect(bank.questions!.single.id, 'imp-1');
      expect(bank.source!.title, '导入提纲');

      final overrides = await ContentOverrides.load();
      final overridesJson = overrides.toJson();
      expect(
        (overridesJson['bullet'] as Map<String, dynamic>)['s9:-1:0'],
        '改过的要点',
      );

      final custom = await CustomQuestions.load();
      expect(custom.items.single.id, 'cq-1');
      expect(custom.questions.single.q, '自建题');

      final favorites = await Favorites.load();
      expect(favorites.qids, containsAll(['imp-1', 'cq-1']));
    });

    test('缺段（null）→ 对应 key 不碰；进度红线 key 原样', () async {
      SharedPreferences.setMockInitialValues({
        kContentOverridesKey: jsonEncode({
          'bullet': {'keep:0': '本地纠错'},
          'question': <String, dynamic>{},
        }),
        kCustomQuestionsKey: jsonEncode([
          {'id': 'cq-9', 'sec': 's1', 'q': '本地自建', 'a': 'a'},
        ]),
        kFavoriteQidsKey: jsonEncode(['local-1']),
        // 进度红线：SRS 进度 / 打卡 / 练习历史 / 设置，导入全程不许动。
        'srs_states': '{"k1":{}}',
        'learned_dates': '{"s1":"2026-10-07"}',
        'review_session': '["q9"]',
        'daily_answers': '{"2026-10-07":{"total":5}}',
        'active_days': '["2026-10-07"]',
        'practice_history': '[{"order":1}]',
        'last_section': 's1',
        'font_scale': '1.2',
      });

      final data = BackupData(
        questions: [
          Question(id: 'imp-2', sec: 's1', q: 'q', a: 'a', src: ''),
        ],
        source: SourceDoc(title: 't', subtitle: const [], chapters: const [
          Chapter(id: 'c1', title: 'c', sections: []),
        ]),
        // overrides / custom / favoriteQids 缺（null）→ 不写。
      );
      await persistImportedBackup(data);

      final prefs = await SharedPreferences.getInstance();
      // 文件缺的段保留现状。
      expect(prefs.getString(kContentOverridesKey), contains('本地纠错'));
      expect(prefs.getString(kCustomQuestionsKey), contains('cq-9'));
      expect(prefs.getString(kFavoriteQidsKey), contains('local-1'));
      // 生效题库落库。
      expect(prefs.getString(kImportedQuestionsKey), contains('imp-2'));
      // 进度红线：逐 key 原样。
      expect(prefs.getString('srs_states'), '{"k1":{}}');
      expect(prefs.getString('learned_dates'), '{"s1":"2026-10-07"}');
      expect(prefs.getString('review_session'), '["q9"]');
      expect(prefs.getString('daily_answers'), '{"2026-10-07":{"total":5}}');
      expect(prefs.getString('active_days'), '["2026-10-07"]');
      expect(prefs.getString('practice_history'), '[{"order":1}]');
      expect(prefs.getString('last_section'), 's1');
      expect(prefs.getString('font_scale'), '1.2');
    });
  });

  group('端到端：差异导入落库后 AppData 生效', () {
    test('替换 + 新增的题在重载后可见，资料同内容保留', () async {
      final assets = await AppData.load();
      final first = assets.questions.first;
      final local = BackupData(
        questions: assets.questions,
        source: assets.doc,
        overrides: {
          'bullet': <String, dynamic>{},
          'question': <String, dynamic>{},
        },
        custom: const [],
        favoriteQids: const [],
      );
      final file = BackupData(
        questions: [
          Question(
            id: first.id,
            sec: first.sec,
            q: '被替换的题干',
            a: first.a,
            src: first.src,
          ),
          Question(
            id: 'brand-new',
            sec: '',
            q: '新增题',
            a: '新增答',
            src: '',
          ),
        ],
        source: assets.doc,
      );

      final outcome = applyDiff(file: file, local: local);
      expect(outcome.questionsReplaced, 1);
      expect(outcome.questionsAdded, 1);
      expect(outcome.sectionsAdded, 0);
      expect(outcome.sectionsReplaced, 0);

      await persistImportedBackup(outcome.data);

      final reloaded = await AppData.load();
      expect(
        reloaded.questions.any((e) => e.id == 'brand-new'),
        isTrue,
        reason: '文件新增的题重载后可见',
      );
      expect(
        reloaded.questions.firstWhere((e) => e.id == first.id).q,
        '被替换的题干',
        reason: '同 id 不同内容 → 文件版生效',
      );
      expect(
        reloaded.chapters.length,
        assets.chapters.length,
        reason: '资料内容相同 → 保留（章数不变）',
      );
      expect(reloaded.sectionIndex.length, assets.sectionIndex.length);
    });
  });
}
