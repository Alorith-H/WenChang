import 'dart:io';

import 'package:flutter/services.dart';

/// 更新下载与安装（任务 16）——「去下载」从跳浏览器改为 App 内直下 APK：
///
/// - [selectApkAsset] / [validateDownloadResult] / [decideUpdateAction]
///   全是纯函数，单测覆盖（test/update_download_test.dart）。
/// - [downloadApk] 用 dart:io（与 update_check 同款 HttpClient，不引新库）
///   边下边写目标文件并回调进度；[DownloadCancelToken] 中断进行中的
///   stream，**用户主动取消不算失败**。
/// - 校验不过 / 网络失败 / 无 apk 资产 / 安装器异常 → [decideUpdateAction]
///   一律给出 [UpdateFlowAction.openReleasePage]（对话框兜底跳 Release 页）。
/// - 成功 → [launchSystemInstaller] 经 FileProvider + MethodChannel 拉起
///   系统安装器（android MainActivity.kt 同名注册）。

/// 下载结果的最低字节数：实收必须严格大于它（防半截 HTML 错误页冒充 APK）。
const kMinApkBytes = 1024 * 1024;

/// 建连超时（下载本身不设总时长 —— 卡住时用户随时可取消）。
const kDownloadConnectTimeout = Duration(seconds: 15);

/// 缓存目录里的下载文件名；每次开下前先删旧文件。
const kUpdateApkFileName = 'update.apk';

/// 安装器 MethodChannel（android MainActivity.kt 同名注册）。
const kUpdaterChannel = 'wenchang/updater';

/// 从 GitHub Release JSON 的 `assets[]` 里挑 `.apk` 资产（纯函数）。
///
/// 取第一条 `name` 以 `.apk` 结尾（大小写不敏感）且
/// `browser_download_url` 非空的条目；无资产 / 全非 apk / 条目残缺 →
/// null（调用方据此直接走 fallback 打开 Release 页，不进入下载）。
String? selectApkAsset(Object? assets) {
  if (assets is! List) return null;
  for (final item in assets) {
    if (item is! Map) continue;
    final name = item['name'];
    final url = item['browser_download_url'];
    if (name is! String || url is! String) continue;
    if (!name.toLowerCase().endsWith('.apk')) continue;
    final trimmed = url.trim();
    if (trimmed.isEmpty) continue;
    return trimmed;
  }
  return null;
}

/// 下载结果校验（纯函数）：HTTP 200、实收字节数严格大于 1MB、
/// content-length 已知时必须与实收完全相等 —— 任一不满足按失败处理。
bool validateDownloadResult({
  required int statusCode,
  required int receivedBytes,
  int? contentLength,
}) {
  if (statusCode != HttpStatus.ok) return false;
  if (receivedBytes <= kMinApkBytes) return false;
  if (contentLength != null && contentLength != receivedBytes) return false;
  return true;
}

/// 下载流程的结局。
enum UpdateOutcome {
  /// 下载并校验通过 —— 可以拉起安装器。
  success,

  /// 网络 / 状态码 / 字节数 / 长度匹配任一不过 —— 兜底跳 Release 页。
  failed,

  /// 用户点了取消 —— 不算失败：静默关闭，不跳转。
  cancelled,
}

/// 由 [decideUpdateAction] 推导的下一步动作。
enum UpdateFlowAction {
  /// 还没下载且有 apk 资产：开始 App 内下载。
  startDownload,

  /// 下载成功：经 FileProvider 拉起系统安装器。
  openInstaller,

  /// 失败（含无 apk 资产 / 安装器异常）：兜底打开 Release 页面。
  openReleasePage,

  /// 用户主动取消：静默关闭对话框，不跳转。
  dismiss,
}

/// 流程决策（纯函数）—— 对话框每一步只问它，不自己拍脑袋：
///
/// - [outcome] 非空：success → 拉安装器；failed → 兜底 Release 页；
///   cancelled → 静默关（区分用户取消，不触发 fallback）。
/// - [outcome] 为空（还没开始下载）：无 apk 资产 → 兜底 Release 页；
///   有资产 → 开始下载。
UpdateFlowAction decideUpdateAction({
  String? apkUrl,
  UpdateOutcome? outcome,
}) {
  switch (outcome) {
    case UpdateOutcome.success:
      return UpdateFlowAction.openInstaller;
    case UpdateOutcome.failed:
      return UpdateFlowAction.openReleasePage;
    case UpdateOutcome.cancelled:
      return UpdateFlowAction.dismiss;
    case null:
      break;
  }
  if (apkUrl == null || apkUrl.trim().isEmpty) {
    return UpdateFlowAction.openReleasePage;
  }
  return UpdateFlowAction.startDownload;
}

/// 下载取消令牌：点「取消」时 [cancel]，进行中的 stream 被强断。
class DownloadCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  /// 是否已取消。
  bool get isCancelled => _cancelled;

  /// 取消（幂等）：先置位再通知监听者 —— 之后注册的会立刻执行一次。
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners) {
      listener();
    }
    _listeners.clear();
  }

  /// 注册监听；若已取消则立刻执行一次。
  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }
}

/// 下载 [url] 到 [destination]（先删旧文件），进度经 [onProgress] 回报
/// （第二个参数为 content-length，未知时为 null）。
///
/// 结局：HTTP 200 且 [validateDownloadResult] 通过 → success；用户取消
/// （[cancelToken]）→ cancelled；其余（断网 / 非 200 / 校验不过 / 写盘
/// 异常）→ failed。非 success 一律删掉半截文件，绝不留残包。
Future<UpdateOutcome> downloadApk({
  required Uri url,
  required File destination,
  required DownloadCancelToken cancelToken,
  void Function(int receivedBytes, int? totalBytes)? onProgress,
}) async {
  _tryDelete(destination); // 先删旧文件，防止残留半截包混进结果

  final client = HttpClient()..connectionTimeout = kDownloadConnectTimeout;
  // 取消即强关连接：挂在 socket 上的读取立刻中断（可中断 stream）。
  cancelToken.addListener(() => client.close(force: true));
  var outcome = UpdateOutcome.failed;
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, 'wenchang-app');
    // GitHub 资产直链 302 → objects.githubusercontent.com，默认跟随。
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
    } else {
      final total = response.contentLength >= 0 ? response.contentLength : null;
      var received = 0;
      final sink = destination.openWrite();
      try {
        await for (final chunk in response) {
          if (cancelToken.isCancelled) break; // 取消：中断 stream，不再收字节
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        try {
          await sink.close();
        } catch (_) {
          // 收尾关不上的半截写盘按外层结局处理，文件随后统一清理
        }
      }
      outcome = validateDownloadResult(
            statusCode: response.statusCode,
            receivedBytes: received,
            contentLength: total,
          )
          ? UpdateOutcome.success
          : UpdateOutcome.failed;
    }
  } catch (_) {
    // 断网 / 强关连接 / 写盘异常：此刻已取消算取消，否则算失败。
    outcome = cancelToken.isCancelled
        ? UpdateOutcome.cancelled
        : UpdateOutcome.failed;
  } finally {
    client.close(force: true);
    // 取消优先：校验落定的同一瞬间用户点了取消 → 尊重用户。
    if (cancelToken.isCancelled) outcome = UpdateOutcome.cancelled;
    if (outcome != UpdateOutcome.success) _tryDelete(destination);
  }
  return outcome;
}

/// 经 FileProvider 拉起系统安装器（MainActivity.kt：ACTION_VIEW +
/// `application/vnd.android.package-archive` + FLAG_GRANT_READ_URI_PERMISSION，
/// authority 为 `${applicationId}.fileprovider`）。
///
/// 成功启动 → true；FileProvider / intent 任何异常 → false（调用方据此
/// 兜底打开 Release 页）。
Future<bool> launchSystemInstaller(String apkPath) async {
  try {
    await const MethodChannel(kUpdaterChannel)
        .invokeMethod('installApk', {'path': apkPath});
    return true;
  } catch (_) {
    return false;
  }
}

/// 尽力删除文件（不存在 / 权限问题都不抛）。
void _tryDelete(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // 删不掉就留着：下次开下前还会再删，且只有 success 才会走到安装
  }
}
