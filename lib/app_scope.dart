import 'package:flutter/widgets.dart';

import 'services/app_data.dart';
import 'services/content_overrides.dart';
import 'services/srs_service.dart';

/// Simple InheritedWidget carrying the app-wide services.
class AppScope extends InheritedWidget {
  final AppData data;
  final SrsService srs;

  /// 纠错覆盖服务（SharedPreferences `content_overrides`）。渲染可编辑
  /// 内容的页面订阅它：保存后立即重建，当前页即见新文本。
  final ContentOverrides overrides;

  const AppScope({
    super.key,
    required this.data,
    required this.srs,
    required this.overrides,
    required super.child,
  });

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      data != oldWidget.data ||
      srs != oldWidget.srs ||
      overrides != oldWidget.overrides;
}
