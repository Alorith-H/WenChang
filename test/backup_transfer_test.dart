import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenchang/models/models.dart';
import 'package:wenchang/services/backup_transfer.dart';
import 'package:wenchang/services/custom_questions.dart';

/// 议题 #3 纯函数层测试：导出结构完整性（含 导出 → 导入 → 相等 往返）、
/// 导入校验的每条报错文案、覆盖语义、差异合并的三分支（新增 / 替换 /
/// 保留）—— 不碰 IO 与 SharedPreferences，全部离线可跑。
void main() {
  Question q(String id, {String sec = 's1', String text = ''}) => Question(
    id: id,
    sec: sec,
    q: text.isEmpty ? '题-$id' : text,
    a: '答-$id',
    src: '',
  );

  Section section(String id, {String title = ''}) => Section(
    id: id,
    title: title.isEmpty ? '节-$id' : title,
    items: const [],
    bullets: const [],
  );

  Chapter chapter(String id, {List<Section> sections = const []}) =>
      Chapter(id: id, title: '章-$id', sections: sections);

  SourceDoc doc({List<Chapter> chapters = const []}) => SourceDoc(
    title: '提纲',
    subtitle: const ['副题'],
    chapters: chapters,
  );

  CustomQuestion custom(String id, {String sec = 's1', String text = ''}) =>
      CustomQuestion(
        id: id,
        sec: sec,
        q: text.isEmpty ? '自-$id' : text,
        a: '答-$id',
      );

  /// 一份结构合法的备份 map（null 的附属段 = 文件缺该段，不写进 JSON）。
  Map<String, dynamic> validFile({
    List<Map<String, dynamic>>? questions,
    Object? source,
    Object? overrides,
    Object? customQuestions,
    Object? favoriteQids,
    Object? formatVersion,
  }) => <String, dynamic>{
    'formatVersion': ?formatVersion,
    'exportedAt': '2026-10-07T00:00:00.000',
    'stats': <String, dynamic>{'questionCount': 2},
    'questions': questions ??
        <Map<String, dynamic>>[
          {'id': 'q1', 'sec': 's1', 'q': '题一', 'a': '答一', 'src': ''},
          {'id': 'q2', 'sec': 's1', 'q': '题二', 'a': '答二', 'src': '出处'},
        ],
    'source': source ??
        <String, dynamic>{
          'title': '提纲',
          'subtitle': ['副'],
          'chapters': <Map<String, dynamic>>[
            {
              'id': 'c1',
              'title': '章一',
              'sections': <Map<String, dynamic>>[
                {'id': 's1', 'title': '节一', 'items': [], 'bullets': []},
              ],
            },
          ],
        },
    'overrides': ?overrides,
    'custom_questions': ?customQuestions,
    'favorite_qids': ?favoriteQids,
  };

  String raw(Map<String, dynamic> m) => jsonEncode(m);

  group('parseBackup 导入校验', () {
    test('坏 JSON / 根节点不是对象 → 明确报错', () {
      final bad = parseBackup('不是 JSON{{');
      expect(bad.ok, isFalse);
      expect(bad.error, '文件不是有效的 JSON');

      final arr = parseBackup('[1,2]');
      expect(arr.ok, isFalse);
      expect(arr.error, contains('根节点'));
    });

    test('缺 questions / 题数为 0 / 类型不对 → 报错', () {
      final noQuestions = validFile()..remove('questions');
      expect(parseBackup(raw(noQuestions)).error, contains('缺少题库'));

      final empty = validFile(questions: const []);
      expect(parseBackup(raw(empty)).error, contains('题库为空'));

      final wrongType = validFile()..['questions'] = 'oops';
      expect(parseBackup(raw(wrongType)).error, contains('缺少题库'));
    });

    test('缺 id / q / a → 报错并指出第几题', () {
      final missingId = validFile(questions: [
        {'q': '没 id 的题', 'a': '答'},
        {'id': 'q2', 'q': '题二', 'a': '答二'},
      ]);
      expect(
        parseBackup(raw(missingId)).error,
        '第 1 题格式非法：缺少 id / q / a',
      );

      final missingA = validFile(questions: [
        {'id': 'q1', 'q': '题一', 'a': '答一'},
        {'id': 'q2', 'q': '题二'},
      ]);
      expect(
        parseBackup(raw(missingA)).error,
        '第 2 题格式非法：缺少 id / q / a',
      );

      final blankQ = validFile(questions: [
        {'id': 'q1', 'sec': 's1', 'q': '', 'a': '答一'},
      ]);
      expect(parseBackup(raw(blankQ)).error, contains('第 1 题'));
    });

    test('source 缺失 / 不是对象 / 没有章节 → 报错', () {
      final noSource = validFile()..remove('source');
      expect(parseBackup(raw(noSource)).error, contains('缺少资料'));

      final notMap = validFile(source: 'oops');
      expect(parseBackup(raw(notMap)).error, contains('资料（source）'));

      final noChapters = validFile(
        source: {'title': 'x', 'chapters': []},
      );
      expect(parseBackup(raw(noChapters)).error, contains('没有章节'));
    });

    test('附属段结构错 / 自建题缺 id·q → 报错', () {
      expect(
        parseBackup(raw(validFile(overrides: 'oops'))).error,
        contains('纠错'),
      );
      expect(
        parseBackup(raw(validFile(customQuestions: 'oops'))).error,
        contains('自建题'),
      );
      expect(
        parseBackup(raw(validFile(favoriteQids: 'oops'))).error,
        contains('收藏'),
      );
      expect(
        parseBackup(
          raw(validFile(customQuestions: [
            {'id': '', 'q': '缺 id'},
          ])),
        ).error,
        '自建题第 1 条格式非法：缺少 id / q',
      );
    });

    test('formatVersion 过新 → 拒绝并提示升级；缺失 / 当前版 → 放行', () {
      final tooNew = parseBackup(raw(validFile(formatVersion: 99)));
      expect(tooNew.ok, isFalse);
      expect(tooNew.error, contains('升级'));

      expect(parseBackup(raw(validFile(formatVersion: kBackupFormatVersion))).ok, isTrue);
      expect(parseBackup(raw(validFile())).ok, isTrue);
    });

    test('合法文件 → 成功：题数、资料、附属段与 meta 都在', () {
      final ok = parseBackup(
        raw(
          validFile(
            formatVersion: kBackupFormatVersion,
            overrides: {
              'bullet': {'s1:-1:0': '改'},
              'question': <String, dynamic>{},
            },
            customQuestions: const [],
            favoriteQids: const [],
          ),
        ),
      );
      expect(ok.ok, isTrue);
      final data = ok.backup!;
      expect(data.questions, hasLength(2));
      expect(data.questions.first.id, 'q1');
      expect(data.source.chapters.single.id, 'c1');
      expect(data.source.chapters.single.sections.single.title, '节一');
      expect(data.overrides, isNotNull);
      expect(data.custom, isEmpty, reason: '文件带空段 ≠ 缺段');
      expect(data.favoriteQids, isEmpty);
      expect(data.meta['formatVersion'], kBackupFormatVersion);
      expect(data.meta['exportedAt'], '2026-10-07T00:00:00.000');
    });
  });

  group('导出结构完整性', () {
    test('buildBackupJson：段齐全、stats 实数正确、可编码可解析', () {
      final questions = [q('q1'), q('q2'), q('q3')];
      final source = doc(chapters: [
        chapter('c1', sections: [section('s1'), section('s2')]),
        chapter('c2', sections: [section('s3')]),
      ]);
      final overrides = {
        'bullet': {'s1:-1:0': '改过的要点'},
        'question': {
          'q1': {'q': '纠错题干'},
        },
      };
      final json = buildBackupJson(
        questions: questions,
        source: source,
        overrides: overrides,
        customQuestions: [custom('cq-1')],
        favoriteQids: ['q1', 'q2'],
        exportedAt: DateTime.utc(2026, 10, 7),
      );

      expect(
        json.keys,
        containsAll([
          'formatVersion',
          'exportedAt',
          'stats',
          'questions',
          'source',
          'overrides',
          'custom_questions',
          'favorite_qids',
        ]),
      );
      expect(json['formatVersion'], kBackupFormatVersion);
      final stats = json['stats'] as Map<String, dynamic>;
      expect(stats['questionCount'], 3);
      expect(stats['chapterCount'], 2);
      expect(stats['sectionCount'], 3);
      expect(stats['customCount'], 1);
      expect(stats['favoriteCount'], 2);
      expect(stats['overrideCount'], 2, reason: 'bullet 1 + question 1');

      // 导出前校验：编码成功且原样解析得回。
      final parsed = parseBackup(jsonEncode(json));
      expect(parsed.ok, isTrue);
      expect(parsed.backup!.questions.map((e) => e.id), ['q1', 'q2', 'q3']);
    });

    test('往返：导出 → parse → 覆盖导入 → 各段逐字节相等', () {
      final questions = [q('q1', text: '甲'), q('q2', text: '乙')];
      final source = SourceDoc(
        title: '提纲',
        subtitle: const ['副题'],
        chapters: [
          Chapter(id: 'c1', title: '章一', sections: [
            Section(
              id: 's1',
              title: '节一',
              items: const [],
              bullets: [
                Bullet(
                  t: '要点',
                  key: true,
                  segs: const [
                    BulletSeg(text: '黑'),
                    BulletSeg(text: '红', red: true),
                  ],
                ),
              ],
            ),
          ]),
        ],
      );
      final overrides = {
        'bullet': {'s1:-1:0': '改过的要点'},
        'question': <String, dynamic>{},
      };
      final exported = buildBackupJson(
        questions: questions,
        source: source,
        overrides: overrides,
        customQuestions: [custom('cq-1')],
        favoriteQids: ['q1'],
        exportedAt: DateTime.utc(2026, 10, 7, 8, 30),
      );

      final parsed = parseBackup(jsonEncode(exported));
      expect(parsed.ok, isTrue);

      // 覆盖导入到一份「完全不同的本地数据」上 → 输出必须等于文件版。
      final other = BackupData(
        questions: [q('zzz')],
        source: doc(chapters: [chapter('zz')]),
        overrides: {
          'bullet': <String, dynamic>{'x': 'y'},
          'question': <String, dynamic>{},
        },
        custom: [custom('cq-999')],
        favoriteQids: ['zzz'],
      );
      final out = applyReplace(file: parsed.backup!, local: other);
      expect(
        jsonEncode([for (final x in out.questions) x.toJson()]),
        jsonEncode(exported['questions']),
      );
      expect(jsonEncode(out.source.toJson()), jsonEncode(exported['source']));
      expect(out.overrides, exported['overrides']);
      expect(
        jsonEncode([for (final c in out.custom!) c.toJson()]),
        jsonEncode(exported['custom_questions']),
      );
      expect(out.favoriteQids, exported['favorite_qids']);

      // 再导一遍（exportedAt 从 meta 回填）→ 整个结构与原文件逐字节相等。
      final again = buildBackupJson(
        questions: out.questions,
        source: out.source,
        overrides: out.overrides!,
        customQuestions: out.custom!,
        favoriteQids: out.favoriteQids!,
        exportedAt: DateTime.parse(exported['exportedAt'] as String),
      );
      expect(again, exported);
    });
  });

  group('差异合并 · 题库 mergeQuestionsById', () {
    test('三分支：新增 / 替换 / 保留，顺序本地在前、文件新增追加', () {
      final local = [
        q('a', text: '本地甲'),
        q('b', text: '本地乙'),
        q('c', text: '本地丙'),
      ];
      final incoming = [q('b', text: '文件乙'), q('d', text: '文件丁')];

      final r = mergeQuestionsById(local: local, incoming: incoming);
      expect(r.added, 1, reason: 'd：文件有本地无');
      expect(r.replaced, 1, reason: 'b：id 同内容不同');
      expect(r.kept, 2, reason: 'a、c：本地有文件无');
      expect(r.merged.map((e) => e.id).toList(), ['a', 'b', 'c', 'd']);
      expect(r.merged[1].q, '文件乙', reason: '替换为文件版');
      expect(r.merged[0].q, '本地甲', reason: '本地独有保留');
    });

    test('内容相同 → 保留；文件重复 id 只收首个；本地空 id 保留', () {
      final local = [q('a', text: '同'), q('', text: '无 id 本地题')];
      final incoming = [
        q('a', text: '同'),
        q('a', text: '文件重复'),
        q('b', text: '文件新题'),
      ];

      final r = mergeQuestionsById(local: local, incoming: incoming);
      expect(r.kept, 2, reason: 'a 内容相同 + 本地空 id');
      expect(r.added, 1, reason: 'b；重复的 a 不计');
      expect(r.replaced, 0);
      expect(r.merged.where((e) => e.id == 'a').single.q, '同');
      expect(r.merged.where((e) => e.id.isEmpty).single.q, '无 id 本地题');
      expect(r.merged.last.id, 'b');
    });
  });

  group('差异合并 · 资料 mergeSourceById', () {
    test('板块与章各走三分支：替换 / 新增 / 保留', () {
      final local = doc(chapters: [
        chapter('c1', sections: [
          section('s1', title: '本地一'),
          section('s2', title: '本地二'),
        ]),
        chapter('c2', sections: [section('s3')]),
      ]);
      final incoming = doc(chapters: [
        chapter('c1', sections: [
          section('s1', title: '文件一'),
          section('s3', title: '文件三'),
        ]),
        chapter('c3', sections: [section('s9')]),
      ]);

      final r = mergeSourceById(local: local, incoming: incoming);
      expect(r.merged.chapters.map((e) => e.id).toList(), [
        'c1',
        'c2',
        'c3',
      ]);
      expect(r.chaptersAdded, 1, reason: 'c3：文件独有章');

      final c1 = r.merged.chapters.first;
      expect(c1.sections.map((e) => e.id).toList(), ['s1', 's2', 's3']);
      expect(c1.sections.first.title, '文件一', reason: '板块同 id 内容不同 → 文件版');
      expect(c1.sections[1].title, '本地二', reason: '本地独有板块保留');
      expect(c1.sections.last.title, '文件三', reason: '文件独有板块新增');
      expect(r.sectionsReplaced, 1);
      expect(
        r.sectionsAdded,
        2,
        reason: 'c1 内新增 s3 + 新章 c3 带进来的 s9',
      );

      // 本地独有章原样保留（含其内部板块）。
      final c2 = r.merged.chapters[1];
      expect(c2.id, 'c2');
      expect(c2.sections.single.id, 's3');
    });

    test('内容完全相同 → 原样保留（0 替换 0 新增）', () {
      final d = doc(chapters: [
        chapter('c1', sections: [section('s1', title: '一样')]),
      ]);
      final r = mergeSourceById(local: d, incoming: d);
      expect(r.sectionsReplaced, 0);
      expect(r.sectionsAdded, 0);
      expect(r.chaptersAdded, 0);
      expect(r.merged.chapters.single.id, 'c1');
      expect(r.merged.chapters.single.sections.single.title, '一样');
    });
  });

  group('差异合并 · 纠错 / 自建题 / 收藏', () {
    test('纠错按 key 合并：同 key 文件优先、本地独有保留、分子表', () {
      final Map<String, dynamic> local = {
        'bullet': {'s1:-1:0': '本地要点', 'keep:key': '本地独有'},
        'question': {
          'q1': {'q': '本地题'},
        },
      };
      final Map<String, dynamic> incoming = {
        'bullet': {'s1:-1:0': '文件要点'},
        'question': {
          'q2': {'q': '文件新题'},
        },
      };
      final m = mergeOverridesById(local: local, incoming: incoming);
      final bullet = m['bullet'] as Map<String, dynamic>;
      final question = m['question'] as Map<String, dynamic>;
      expect(bullet['s1:-1:0'], '文件要点', reason: '同 key 以文件为准');
      expect(bullet['keep:key'], '本地独有', reason: '本地独有保留');
      expect(question.keys, containsAll(['q1', 'q2']));
      expect(question['q2'], {'q': '文件新题'});
    });

    test('自建题按 id 三分支（同题库语义）', () {
      final local = [
        custom('cq-1', text: '本地一'),
        custom('cq-2', text: '本地二'),
      ];
      final incoming = [
        custom('cq-2', text: '文件二'),
        custom('cq-3', text: '文件三'),
      ];
      final r = mergeCustomById(local: local, incoming: incoming);
      expect(r.replaced, 1);
      expect(r.added, 1);
      expect(r.kept, 1);
      expect(r.merged.map((e) => e.id).toList(), ['cq-1', 'cq-2', 'cq-3']);
      expect(r.merged[1].q, '文件二');
    });

    test('收藏并集去重：本地序在前，文件新增追加', () {
      expect(
        mergeFavoriteIds(local: ['q1', 'q2'], incoming: ['q2', 'q3', 'q1']),
        ['q1', 'q2', 'q3'],
      );
      expect(mergeFavoriteIds(local: const [], incoming: ['a', 'a']), ['a']);
    });
  });

  group('覆盖模式 applyReplace', () {
    test('题库 + 资料整体替换；文件缺附属段 → 保留本地现状', () {
      final file = BackupData(
        questions: [q('f1')],
        source: doc(chapters: [chapter('fc')]),
        // overrides / custom / favoriteQids 缺（null）。
      );
      final local = BackupData(
        questions: [q('l1')],
        source: doc(chapters: [chapter('lc')]),
        overrides: {
          'bullet': <String, dynamic>{'k': '本地纠错'},
          'question': <String, dynamic>{},
        },
        custom: [custom('cq-1')],
        favoriteQids: ['l1'],
      );

      final out = applyReplace(file: file, local: local);
      expect(out.questions.single.id, 'f1', reason: '题库整体替换');
      expect(out.source.chapters.single.id, 'fc', reason: '资料整体替换');
      expect(out.overrides, local.overrides, reason: '文件缺纠错段 → 保留');
      expect(out.custom!.single.id, 'cq-1', reason: '文件缺自建题段 → 保留');
      expect(out.favoriteQids, ['l1'], reason: '文件缺收藏段 → 保留');
    });

    test('文件带（哪怕是空的）附属段 → 本地被替换', () {
      final file = BackupData(
        questions: [q('f1')],
        source: doc(chapters: [chapter('fc')]),
        overrides: {
          'bullet': <String, dynamic>{'x': '文件纠错'},
          'question': <String, dynamic>{},
        },
        custom: const [],
        favoriteQids: const [],
      );
      final local = BackupData(
        questions: [q('l1')],
        source: doc(chapters: [chapter('lc')]),
        overrides: {
          'bullet': <String, dynamic>{'k': '本地纠错'},
          'question': <String, dynamic>{},
        },
        custom: [custom('cq-1')],
        favoriteQids: ['l1'],
      );

      final out = applyReplace(file: file, local: local);
      expect(out.custom, isEmpty, reason: '文件带空段 → 清掉本地');
      expect(out.favoriteQids, isEmpty);
      expect(
        (out.overrides!['bullet'] as Map<String, dynamic>).keys,
        ['x'],
        reason: '文件版纠错整体替换',
      );
    });
  });

  group('差异模式 applyDiff', () {
    test('各段三分支合并，实数计数进 outcome', () {
      final local = BackupData(
        questions: [q('a', text: '甲'), q('b', text: '乙')],
        source: doc(chapters: [
          chapter('c1', sections: [section('s1', title: '本地节')]),
        ]),
        overrides: {
          'bullet': <String, dynamic>{'k1': '本地'},
          'question': <String, dynamic>{},
        },
        custom: [custom('cq-1', text: '本地自建')],
        favoriteQids: ['a'],
      );
      final file = BackupData(
        questions: [q('b', text: '乙改'), q('c', text: '丙')],
        source: doc(chapters: [
          chapter('c1', sections: [
            section('s1', title: '文件节'),
            section('s2', title: '新节'),
          ]),
        ]),
        overrides: {
          'bullet': <String, dynamic>{'k2': '文件'},
          'question': <String, dynamic>{},
        },
        custom: [custom('cq-1', text: '文件自建')],
        favoriteQids: ['b'],
        meta: {'formatVersion': kBackupFormatVersion},
      );

      final r = applyDiff(file: file, local: local);
      expect(r.questionsAdded, 1, reason: 'c');
      expect(r.questionsReplaced, 1, reason: 'b');
      expect(r.questionsKept, 1, reason: 'a');
      expect(r.data.questions.map((e) => e.id).toList(), ['a', 'b', 'c']);
      expect(r.data.questions[1].q, '乙改');

      expect(r.sectionsReplaced, 1, reason: 's1 内容不同');
      expect(r.sectionsAdded, 1, reason: 's2 文件独有');
      expect(r.data.source.chapters.single.sections, hasLength(2));

      expect(r.customReplaced, 1);
      expect(r.data.custom!.single.q, '文件自建');
      expect(
        (r.data.overrides!['bullet'] as Map<String, dynamic>).keys,
        ['k1', 'k2'],
        reason: '纠错 key 并集，同 key 文件版',
      );
      expect(r.data.favoriteQids, ['a', 'b'], reason: '收藏并集');
      expect(r.data.meta['formatVersion'], kBackupFormatVersion);
    });

    test('文件缺附属段 = 空集合并 → 本地现状原样', () {
      final local = BackupData(
        questions: [q('a')],
        source: doc(chapters: [chapter('c1')]),
        overrides: {
          'bullet': <String, dynamic>{'k': '本地'},
          'question': <String, dynamic>{},
        },
        custom: [custom('cq-1')],
        favoriteQids: ['a'],
      );
      final file = BackupData(
        questions: [q('b')],
        source: doc(chapters: [chapter('c2')]),
      );

      final r = applyDiff(file: file, local: local);
      expect(r.data.overrides, local.overrides, reason: '缺段 → 本地原样');
      expect(r.data.custom!.single.id, 'cq-1');
      expect(r.data.favoriteQids, ['a']);
      expect(r.questionsAdded, 1);
      expect(r.chaptersAdded, 1, reason: 'c2 并入；本地 c1 保留');
      expect(r.data.source.chapters.map((e) => e.id), ['c1', 'c2']);
    });
  });
}
