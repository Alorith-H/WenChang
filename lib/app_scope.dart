import 'package:flutter/widgets.dart';

import 'services/app_data.dart';
import 'services/content_overrides.dart';
import 'services/custom_questions.dart';
import 'services/favorites.dart';
import 'services/srs_service.dart';

/// Simple InheritedWidget carrying the app-wide services.
class AppScope extends InheritedWidget {
  final AppData data;
  final SrsService srs;

  /// 纠错覆盖服务（SharedPreferences `content_overrides`）。渲染可编辑
  /// 内容的页面订阅它：保存后立即重建，当前页即见新文本。
  final ContentOverrides overrides;

  /// 自建题存储（SharedPreferences `custom_questions`）：出题候选池与
  /// 选题页计数合并它，删除走 `deleteCustomQuestion` 联动清理。
  final CustomQuestions customQuestions;

  /// 收藏夹（SharedPreferences `favorite_qids`）：答题页星标切换、
  /// 选题页「收藏夹」入口按它组队。
  final Favorites favorites;

  /// 数据重载回调（议题 #3 导入后就地刷新）：触发 _Bootstrap 重新
  /// load。重载期间 FutureBuilder 保留旧快照 → 树形不变，SnackBar 与
  /// 路由栈都不丢；完成后本 widget 的新实例通知依赖方重建。
  final VoidCallback? reloadData;

  const AppScope({
    super.key,
    required this.data,
    required this.srs,
    required this.overrides,
    required this.customQuestions,
    required this.favorites,
    this.reloadData,
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
      overrides != oldWidget.overrides ||
      customQuestions != oldWidget.customQuestions ||
      favorites != oldWidget.favorites ||
      reloadData != oldWidget.reloadData;
}
