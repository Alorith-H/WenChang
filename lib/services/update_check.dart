import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 检查更新（议题 #5）—— 对 GitHub Release 的最新版本。
///
/// - [isNewer] / [normalizeVersion] / [shouldShowBanner] / [parseRelease]
///   全是纯函数，单测覆盖（test/update_check_test.dart）。
/// - [fetchLatestRelease] 8 秒超时，任何网络失败都静默返回 null ——
///   手动检查据此弹「检查失败」SnackBar，冷启动静默检查直接无感丢弃。
/// - `dismissed_version` 记忆横幅已忽略的版本，同版本不重复骚扰。

/// GitHub API：最新 Release（无需鉴权）。
const kReleasesLatestUrl =
    'https://api.github.com/repos/Alorith-H/WenChang/releases/latest';

/// 检查超时：手动 / 静默共用，绝不卡转圈超过 8 秒。
const kUpdateCheckTimeout = Duration(seconds: 8);

/// 横幅已忽略的版本号（SharedPreferences key，议题 #5）。
const kDismissedVersionKey = 'dismissed_version';

/// 一个 GitHub Release 的展示所需字段。
class ReleaseInfo {
  /// 规范化后的版本号（`v1.0.2` → `1.0.2`），用于比较与横幅去重。
  final String version;

  /// 原始 tag（`v1.0.2`），用于对话框标题与横幅文案。
  final String tagName;

  /// Release 正文原文（更新内容；缺失时为空串）。
  final String body;

  /// Release 页面地址（「去下载」按钮打开它）。
  final String htmlUrl;

  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.body,
    required this.htmlUrl,
  });
}

/// 版本号规范化：剥掉 `v`/`V` 前缀与 `+构建号`，去首尾空白。
/// `v1.0.0+1` → `1.0.0`；非字符串/空 → 原样返回（由比较方判空）。
String normalizeVersion(String raw) {
  var v = raw.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  final plus = v.indexOf('+');
  if (plus >= 0) v = v.substring(0, plus);
  return v.trim();
}

/// 语义化比较：远端 [remote] 是否比本地 [local] 新（纯函数）。
///
/// - 处理 `v` 前缀、`+构建号`（`1.0.0+1` → `1.0.0`）、缺段（`1.0` 与
///   `1.0.0` 等长，缺段按 0）、非数字段（按 0 处理）；
/// - 逐段数值比较（`1.10.0` > `1.9.9`，不是字典序）；
/// - 任一侧规范化后为空 → false（拿不准就不打扰）。
bool isNewer(String remote, String local) {
  final r = normalizeVersion(remote);
  final l = normalizeVersion(local);
  if (r.isEmpty || l.isEmpty) return false;
  final rp = r.split('.');
  final lp = l.split('.');
  final n = rp.length > lp.length ? rp.length : lp.length;
  for (var i = 0; i < n; i++) {
    final a = i < rp.length ? (int.tryParse(rp[i]) ?? 0) : 0;
    final b = i < lp.length ? (int.tryParse(lp[i]) ?? 0) : 0;
    if (a != b) return a > b;
  }
  return false; // 同版本（含缺段补齐）不算新
}

/// 冷启动静默横幅的去重判断（纯函数）：发现新版本、且该版本没被用户
/// 关闭过（`dismissed_version`）才展示。
bool shouldShowBanner({
  required String remote,
  required String local,
  String? dismissed,
}) {
  if (!isNewer(remote, local)) return false;
  if (dismissed == null || dismissed.isEmpty) return true;
  return normalizeVersion(remote) != normalizeVersion(dismissed);
}

/// 解析 GitHub `releases/latest` 响应（纯函数）：缺 `tag_name` /
/// `html_url` 或整体不是对象 → null（调用方按检查失败处理）。
ReleaseInfo? parseRelease(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final tag = json['tag_name'];
  final url = json['html_url'];
  if (tag is! String || tag.trim().isEmpty) return null;
  if (url is! String || url.trim().isEmpty) return null;
  final body = json['body'];
  return ReleaseInfo(
    tagName: tag.trim(),
    version: normalizeVersion(tag),
    body: body is String ? body : '',
    htmlUrl: url.trim(),
  );
}

/// 拉取最新 Release：[timeout]（默认 8s）内完成，否则 / 网络失败 /
/// 非 200 / 坏 JSON 一律返回 null —— 绝不抛出去。
Future<ReleaseInfo?> fetchLatestRelease({
  Duration timeout = kUpdateCheckTimeout,
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    // _getLatest 自己吞掉一切异常，外层再套总超时；超时后 client 在
    // finally 里被强制关闭，挂起的请求随之终结。
    return await _getLatest(client).timeout(timeout);
  } catch (_) {
    return null; // TimeoutException 等 → 静默失败
  } finally {
    client.close(force: true);
  }
}

Future<ReleaseInfo?> _getLatest(HttpClient client) async {
  try {
    final request = await client.getUrl(Uri.parse(kReleasesLatestUrl));
    // GitHub API 强制要求 User-Agent；带上 JSON Accept 走稳定响应形态。
    request.headers.set(HttpHeaders.userAgentHeader, 'wenchang-app');
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    final text = await response.transform(utf8.decoder).join();
    return parseRelease(jsonDecode(text));
  } catch (_) {
    return null; // 断网 / DNS / 解析失败 → 静默
  }
}

/// 读取横幅已忽略的版本号（没有 → null）。
Future<String?> getDismissedVersion() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kDismissedVersionKey);
  } catch (_) {
    return null;
  }
}

/// 记下用户关闭横幅的版本（存规范化形式，比较时两侧都规范化）。
Future<void> setDismissedVersion(String version) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kDismissedVersionKey, normalizeVersion(version));
  } catch (_) {
    // Best effort：丢一次记忆只是下次多看一眼横幅，绝不崩。
  }
}
