import 'package:flutter_test/flutter_test.dart';
import 'package:wenchang/services/update_check.dart';

/// 议题 #5（检查更新）的纯函数测试：版本规范化与语义化比较
/// [isNewer]、静默横幅去重判断 [shouldShowBanner]、Release 解析
/// [parseRelease]。不碰网络（[fetchLatestRelease] 的 8s 超时与静默
/// 失败在设备离线时由实现自身保证，这里只测可注入的纯逻辑）。
void main() {
  group('normalizeVersion 规范化', () {
    test('剥 v/V 前缀', () {
      expect(normalizeVersion('v1.0.2'), '1.0.2');
      expect(normalizeVersion('V2.1.0'), '2.1.0');
      expect(normalizeVersion('1.0.2'), '1.0.2');
    });

    test('剥 +构建号与首尾空白', () {
      expect(normalizeVersion('1.0.0+1'), '1.0.0');
      expect(normalizeVersion(' v1.0.0+12 '), '1.0.0');
    });
  });

  group('isNewer 语义化比较（纯函数）', () {
    test('v 前缀 + 本地 +构建号：远端更新 → true', () {
      expect(isNewer('v1.0.1', '1.0.0+1'), isTrue);
      expect(isNewer('V1.0.1', '1.0.0'), isTrue);
    });

    test('同版本（含 v 前缀 / +构建号）不算新', () {
      expect(isNewer('v1.0.0', '1.0.0'), isFalse);
      expect(isNewer('1.0.0', '1.0.0+1'), isFalse);
      expect(isNewer('1.0.0+2', '1.0.0+1'), isFalse);
    });

    test('缺段按 0 补齐：1.0 与 1.0.0 等长', () {
      expect(isNewer('1.0', '1.0.0'), isFalse);
      expect(isNewer('1.0.0', '1.0'), isFalse);
      expect(isNewer('1.0.1', '1.0'), isTrue);
      expect(isNewer('1.0', '1.0.1'), isFalse);
    });

    test('逐段数值比较，不是字典序（1.10.0 > 1.9.9）', () {
      expect(isNewer('1.10.0', '1.9.9'), isTrue);
      expect(isNewer('1.9.9', '1.10.0'), isFalse);
      expect(isNewer('2', '1.9.9'), isTrue);
    });

    test('远端更旧 → false', () {
      expect(isNewer('0.9.9', '1.0.0'), isFalse);
      expect(isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('任一侧为空 / 不可解析 → false（拿不准就不打扰）', () {
      expect(isNewer('', '1.0.0'), isFalse);
      expect(isNewer('1.0.0', ''), isFalse);
      expect(isNewer('abc', '1.0.0'), isFalse);
      expect(isNewer('v', '1.0.0'), isFalse);
    });
  });

  group('shouldShowBanner 横幅去重（纯函数）', () {
    test('发现新版本且从未忽略 → 展示', () {
      expect(
        shouldShowBanner(remote: '1.0.1', local: '1.0.0'),
        isTrue,
      );
      expect(
        shouldShowBanner(remote: '1.0.1', local: '1.0.0', dismissed: null),
        isTrue,
      );
    });

    test('已是最新 / 远端更旧 → 不展示', () {
      expect(
        shouldShowBanner(remote: '1.0.0', local: '1.0.0'),
        isFalse,
      );
      expect(
        shouldShowBanner(remote: '0.9.0', local: '1.0.0'),
        isFalse,
      );
    });

    test('该版本已被忽略（含 v 前缀差异）→ 不再骚扰', () {
      expect(
        shouldShowBanner(
          remote: '1.0.1',
          local: '1.0.0',
          dismissed: '1.0.1',
        ),
        isFalse,
      );
      expect(
        shouldShowBanner(
          remote: 'v1.0.1',
          local: '1.0.0',
          dismissed: '1.0.1',
        ),
        isFalse,
      );
      expect(
        shouldShowBanner(
          remote: '1.0.1',
          local: '1.0.0',
          dismissed: 'v1.0.1',
        ),
        isFalse,
      );
    });

    test('忽略的是旧版本、远端又出了新版 → 正常展示', () {
      expect(
        shouldShowBanner(
          remote: '1.0.2',
          local: '1.0.0',
          dismissed: '1.0.1',
        ),
        isTrue,
      );
    });
  });

  group('parseRelease 解析（纯函数）', () {
    test('完整 JSON → tagName / version / body / htmlUrl', () {
      final release = parseRelease({
        'tag_name': 'v1.2.0',
        'body': '## 更新内容\n- 修复若干问题',
        'html_url': 'https://github.com/Alorith-H/WenChang/releases/tag/v1.2.0',
      });
      expect(release, isNotNull);
      expect(release!.tagName, 'v1.2.0');
      expect(release.version, '1.2.0'); // 已规范化，可直接比较
      expect(release.body, '## 更新内容\n- 修复若干问题');
      expect(
        release.htmlUrl,
        'https://github.com/Alorith-H/WenChang/releases/tag/v1.2.0',
      );
    });

    test('body 缺失 / 非串 → 空串；tag_name 决定规范化版本', () {
      final release = parseRelease({
        'tag_name': 'v1.0.0+7',
        'html_url': 'https://example.com/r',
      });
      expect(release, isNotNull);
      expect(release!.version, '1.0.0');
      expect(release.body, '');
    });

    test('缺 tag_name / 缺 html_url / 非对象 → null（按检查失败处理）', () {
      expect(
        parseRelease({
          'html_url': 'https://example.com/r',
          'body': '',
        }),
        isNull,
      );
      expect(parseRelease({'tag_name': 'v1.0.0'}), isNull);
      expect(parseRelease({'tag_name': '', 'html_url': 'u'}), isNull);
      expect(parseRelease('not a map'), isNull);
      expect(parseRelease(null), isNull);
      expect(parseRelease([1, 2, 3]), isNull);
    });

    test('解析结果能直接喂给 isNewer / shouldShowBanner', () {
      final release = parseRelease({
        'tag_name': 'v1.1.0',
        'html_url': 'https://example.com/r',
      })!;
      expect(isNewer(release.version, '1.0.0+1'), isTrue);
      expect(
        shouldShowBanner(
          remote: release.version,
          local: '1.0.0',
          dismissed: '1.0.9',
        ),
        isTrue,
      );
    });
  });
}
