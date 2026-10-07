import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_check.dart';

/// 「发现新版本」对话框（议题 #5）—— 手动检查与主页静默横幅共用：
/// 新版本号 + 更新内容（Release body 原文，可滚动/可选中）+
/// 「去下载」（url_launcher 打开该 Release 页面）。
Future<void> showUpdateDialog(BuildContext context, ReleaseInfo release) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('发现新版本 ${release.tagName}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: SelectableText(
            release.body.isEmpty ? '打开 Release 页面查看更新内容。' : release.body,
            style: const TextStyle(fontSize: 14, height: 1.7),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () => _openRelease(ctx, release),
          child: const Text('去下载'),
        ),
      ],
    ),
  );
}

/// 打开 Release 页面；设备上打不开时给一条 SnackBar，不崩不卡。
Future<void> _openRelease(BuildContext ctx, ReleaseInfo release) async {
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(release.htmlUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (opened || !ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(
    const SnackBar(content: Text('无法打开下载页面，请稍后重试')),
  );
}
