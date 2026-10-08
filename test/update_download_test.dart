import 'package:flutter_test/flutter_test.dart';
import 'package:wenchang/services/update_download.dart';

/// 任务 16（App 内下载 APK）的纯函数测试：[selectApkAsset] 资产选择、
/// [validateDownloadResult] 下载结果校验、[decideUpdateAction] 失败 →
/// fallback 决策（区分用户取消）。不碰网络与平台通道 —— 下载/安装器
/// UI 与 MethodChannel 按任务要求不强求单测。
void main() {
  group('selectApkAsset 选 apk 资产（纯函数）', () {
    test('多资产：跳过非 apk，选中 .apk 的 browser_download_url', () {
      expect(
        selectApkAsset([
          {
            'name': 'source.zip',
            'browser_download_url': 'https://x/source.zip',
          },
          {
            'name': 'wenchang-1.2.0.apk',
            'browser_download_url': 'https://x/wenchang-1.2.0.apk',
          },
          {
            'name': 'checksums.txt',
            'browser_download_url': 'https://x/checksums.txt',
          },
        ]),
        'https://x/wenchang-1.2.0.apk',
      );
    });

    test('大小写 .APK 命中；缺 url / 空白 url 的条目跳过', () {
      expect(
        selectApkAsset([
          {'name': 'a.apk'}, // 缺 browser_download_url → 跳过
          {'name': 'b.apk', 'browser_download_url': '   '}, // 空 → 跳过
          {'name': 'C.APK', 'browser_download_url': ' https://x/c.apk '},
        ]),
        'https://x/c.apk', // url 去首尾空白
      );
    });

    test('无资产 / 空列表 / 非列表 → null', () {
      expect(selectApkAsset(null), isNull);
      expect(selectApkAsset(const []), isNull);
      expect(selectApkAsset('not a list'), isNull);
      expect(selectApkAsset({'name': 'a.apk'}), isNull); // 是 map 不是 list
      expect(selectApkAsset('a.apk'), isNull);
    });

    test('只有非 apk 资产（zip / txt）或残缺条目 → null', () {
      expect(
        selectApkAsset([
          {'name': 'app.zip', 'browser_download_url': 'https://x/app.zip'},
          {'name': 'checksums.txt', 'browser_download_url': 'https://x/c.txt'},
          'garbage-entry',
          42,
        ]),
        isNull,
      );
    });
  });

  group('validateDownloadResult 下载结果校验（纯函数）', () {
    test('200 + 严格超过 1MB + content-length 相等 → 通过', () {
      expect(
        validateDownloadResult(
          statusCode: 200,
          receivedBytes: 2 * 1024 * 1024,
          contentLength: 2 * 1024 * 1024,
        ),
        isTrue,
      );
    });

    test('content-length 未知（null）→ 不拦，只看字节数', () {
      expect(
        validateDownloadResult(
          statusCode: 200,
          receivedBytes: 1024 * 1024 + 1,
          contentLength: null,
        ),
        isTrue,
      );
    });

    test('content-length 存在但与实收不相等 → 失败', () {
      expect(
        validateDownloadResult(
          statusCode: 200,
          receivedBytes: 3 * 1024 * 1024,
          contentLength: 5 * 1024 * 1024,
        ),
        isFalse,
      );
      expect(
        validateDownloadResult(
          statusCode: 200,
          receivedBytes: 5 * 1024 * 1024 + 1, // 服务器宣称的长度没下全
          contentLength: 5 * 1024 * 1024,
        ),
        isFalse,
      );
    });

    test('非 200 → 失败', () {
      expect(
        validateDownloadResult(
          statusCode: 404,
          receivedBytes: 3 * 1024 * 1024,
          contentLength: 3 * 1024 * 1024,
        ),
        isFalse,
      );
      expect(
        validateDownloadResult(
          statusCode: 302,
          receivedBytes: 3 * 1024 * 1024,
          contentLength: null,
        ),
        isFalse,
      );
    });

    test('字节数不足 1MB（含恰好 1MB / 0）→ 失败', () {
      expect(
        validateDownloadResult(
          statusCode: 200,
          receivedBytes: 900 * 1024,
          contentLength: null,
        ),
        isFalse,
      );
      expect(
        validateDownloadResult(
          statusCode: 200,
          receivedBytes: 1024 * 1024, // 必须严格大于 1MB
          contentLength: 1024 * 1024,
        ),
        isFalse,
      );
      expect(
        validateDownloadResult(
          statusCode: 200,
          receivedBytes: 0,
          contentLength: null,
        ),
        isFalse,
      );
    });
  });

  group('decideUpdateAction 失败 → fallback 决策（纯函数）', () {
    test('未下载且无 apk 资产 → 直接打开 Release 页（不进下载）', () {
      expect(
        decideUpdateAction(apkUrl: null),
        UpdateFlowAction.openReleasePage,
      );
      expect(
        decideUpdateAction(apkUrl: '   '),
        UpdateFlowAction.openReleasePage,
      );
    });

    test('未下载但有 apk 资产 → 开始 App 内下载', () {
      expect(
        decideUpdateAction(apkUrl: 'https://x/wenchang.apk'),
        UpdateFlowAction.startDownload,
      );
    });

    test('下载失败（网络 / 非 200 / 校验不过）→ 兜底打开 Release 页', () {
      expect(
        decideUpdateAction(outcome: UpdateOutcome.failed),
        UpdateFlowAction.openReleasePage,
      );
      // 有资产也救不回来：结局优先。
      expect(
        decideUpdateAction(
          apkUrl: 'https://x/wenchang.apk',
          outcome: UpdateOutcome.failed,
        ),
        UpdateFlowAction.openReleasePage,
      );
    });

    test('用户主动取消 → 静默关闭，不跳转（不算失败）', () {
      expect(
        decideUpdateAction(outcome: UpdateOutcome.cancelled),
        UpdateFlowAction.dismiss,
      );
      expect(
        decideUpdateAction(
          apkUrl: 'https://x/wenchang.apk',
          outcome: UpdateOutcome.cancelled,
        ),
        UpdateFlowAction.dismiss,
      );
    });

    test('下载成功 → 拉起系统安装器', () {
      expect(
        decideUpdateAction(outcome: UpdateOutcome.success),
        UpdateFlowAction.openInstaller,
      );
    });
  });
}
