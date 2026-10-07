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

  const AppScope({
    super.key,
    required this.data,
    required this.srs,
    required this.overrides,
    required this.customQuestions,
    required this.favorites,
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
      favorites != oldWidget.favorites;
}
