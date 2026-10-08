import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_check.dart';
import '../services/update_download.dart';

/// 「发现新版本」对话框（议题 #5 / 任务 16）—— 手动检查与主页静默横幅
/// 共用：新版本号 + 更新内容（Release body 原文，可滚动/可选中）+
/// 「去下载」。
///
/// 点「去下载」原地切成下载态（LinearProgressIndicator + 百分比/已下 MB +
/// 取消按钮）；下载成功经 FileProvider 拉起系统安装器。**任何失败自动兜底
/// 打开该 Release 页面**（SnackBar 提示）；用户主动取消不算失败 —— 静默关，
/// 不跳转。每一步的去向都由 [decideUpdateAction] 这个纯函数裁决。
Future<void> showUpdateDialog(BuildContext context, ReleaseInfo release) {
  return showDialog<void>(
    context: context,
    builder: (_) => _UpdateDialog(release: release),
  );
}

/// 对话框阶段：info = 更新说明 + 去下载；downloading = 进度 + 取消。
enum _UpdatePhase { info, downloading }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release});

  final ReleaseInfo release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  /// 当前阶段（下载中返回键/遮罩都关不掉，只能走「取消」或等结果）。
  _UpdatePhase _phase = _UpdatePhase.info;

  /// 下载进度：已收字节 / 总字节（content-length 未知 → null）。
  int _receivedBytes = 0;
  int? _totalBytes;

  /// 进行中的取消令牌；对话框销毁时兜底取消，绝不留孤儿 stream。
  DownloadCancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _phase == _UpdatePhase.downloading;
    // 下载中 canPop=false：返回键与遮罩都关不掉，只能点「取消」或等结果。
    return PopScope(
      canPop: !downloading,
      child: AlertDialog(
        title: Text(
          downloading
              ? '正在下载 ${widget.release.tagName}'
              : '发现新版本 ${widget.release.tagName}',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: downloading ? _buildProgress() : _buildReleaseBody(),
        ),
        actions:
            downloading ? _buildDownloadingActions() : _buildInfoActions(),
      ),
    );
  }

  /// 更新说明（与议题 #5 原版一致：可滚动、可选中）。
  Widget _buildReleaseBody() {
    return SingleChildScrollView(
      child: SelectableText(
        widget.release.body.isEmpty
            ? '打开 Release 页面查看更新内容。'
            : widget.release.body,
        style: const TextStyle(fontSize: 14, height: 1.7),
      ),
    );
  }

  /// 下载进度 UI：进度条 + 百分比/已下 MB（content-length 未知则只报
  /// 流量数，进度条走不确定态转圈）。
  Widget _buildProgress() {
    final total = _totalBytes;
    final hasTotal = total != null && total > 0;
    final String label;
    if (hasTotal) {
      final percent = (_receivedBytes * 100 / total).floor();
      label = '已下载 $percent%（${_mb(_receivedBytes)} / ${_mb(total)} MB）';
    } else {
      label = '已下载 ${_mb(_receivedBytes)} MB';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: hasTotal ? (_receivedBytes / total).clamp(0.0, 1.0) : null,
        ),
        const SizedBox(height: 16),
        Text(label, style: const TextStyle(fontSize: 14, height: 1.6)),
      ],
    );
  }

  List<Widget> _buildInfoActions() {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: _startDownload,
        child: const Text('去下载'),
      ),
    ];
  }

  List<Widget> _buildDownloadingActions() {
    return [
      TextButton(
        onPressed: _cancelDownload,
        child: const Text('取消'),
      ),
    ];
  }

  /// 点「去下载」：先问纯函数决策（无 apk 资产 → 直接兜底跳 Release 页），
  /// 有资产才切下载态开跑；结束后按结局拉安装器 / 兜底 / 静默。
  Future<void> _startDownload() async {
    final release = widget.release;
    final apkUrl = release.apkUrl;
    final action = decideUpdateAction(apkUrl: apkUrl);
    if (action != UpdateFlowAction.startDownload) {
      await _applyAction(action);
      return;
    }

    // 切下载态：进度 UI 立即出现，下载中不可被返回键/遮罩关闭。
    final token = DownloadCancelToken();
    setState(() {
      _phase = _UpdatePhase.downloading;
      _cancelToken = token;
      _receivedBytes = 0;
      _totalBytes = null;
    });

    Directory cacheDir;
    try {
      cacheDir = await getApplicationCacheDirectory();
    } catch (_) {
      if (mounted) await _applyAction(UpdateFlowAction.openReleasePage);
      return;
    }
    if (!mounted || token.isCancelled) return; // 期间已取消 → 静默收场

    //下载到缓存目录（file_paths.xml 的 <cache-path> 覆盖它），先删旧文件。
    final destination = File('${cacheDir.path}/$kUpdateApkFileName');
    final outcome = await downloadApk(
      url: Uri.parse(apkUrl!), // decideUpdateAction 只在有资产时给 startDownload
      destination: destination,
      cancelToken: token,
      onProgress: (received, total) {
        if (!mounted || _phase != _UpdatePhase.downloading) return;
        setState(() {
          _receivedBytes = received;
          _totalBytes = total;
        });
      },
    );
    if (!mounted) return; // 用户点了取消并已关掉对话框 → 静默，不跳转
    await _applyAction(
      decideUpdateAction(outcome: outcome),
      apkPath: destination.path,
    );
  }

  /// 点「取消」：中断下载 stream 后静默关闭 —— 用户主动取消不算失败，
  /// 不弹 SnackBar、不跳 Release 页。
  void _cancelDownload() {
    _cancelToken?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  /// 执行 [decideUpdateAction] 给出的下一步。
  Future<void> _applyAction(UpdateFlowAction action, {String? apkPath}) async {
    switch (action) {
      case UpdateFlowAction.startDownload:
        return; // 仅「去下载」入口产生，这里不处理
      case UpdateFlowAction.dismiss:
        if (mounted) Navigator.of(context).pop();
        return;
      case UpdateFlowAction.openInstaller:
        // FileProvider / intent 异常 → 归入失败，同样兜底跳 Release 页。
        final launched =
            apkPath != null && await launchSystemInstaller(apkPath);
        if (launched) {
          if (mounted) Navigator.of(context).pop(); // 安装器接管，收掉对话框
        } else {
          await _openReleaseFallback();
        }
        return;
      case UpdateFlowAction.openReleasePage:
        await _openReleaseFallback();
        return;
    }
  }

  /// 兜底：关掉对话框 → SnackBar「下载失败，已为你打开发布页」→ 打开该
  /// Release 页面（release.html_url，不是 asset 直链）。浏览器也打不开时
  /// 再补一条提示，绝不崩。
  Future<void> _openReleaseFallback() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final release = widget.release;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('下载失败，已为你打开发布页')),
    );
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(release.htmlUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('无法打开下载页面，请稍后重试')),
      );
    }
  }

  /// 字节数 → MB 文本（一位小数）。
  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
