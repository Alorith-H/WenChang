/// Persisted SRS + "learned today" state, backed by shared_preferences.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'app_data.dart';
import 'srs_logic.dart';

const _kStatesKey = 'srs_states';
const _kLearnedKey = 'learned_dates';
const _kSeenKey = 'seen_cards';
const _kSessionKey = 'review_session';
const _kLastSectionKey = 'last_section';
const _kLastStudyKey = 'last_study';
const _kDailyKey = 'daily_answers';
const _kActiveDaysKey = 'active_days';
const _kFontScaleKey = 'font_scale';
const _kThemeColorKey = 'theme_color';
const _kReviewShuffleKey = 'review_shuffle';
const _kPracticeKey = 'practice_history';

/// Allowed font-size steps (textScale), paired with their labels.
const kFontScaleSteps = <double>[0.9, 1.0, 1.15, 1.3];
const kFontScaleLabels = <String>['小', '标准', '大', '特大'];

/// One of the six preset theme accents. The seed drives the app-wide
/// ColorScheme (MaterialApp theme rebuild); only in-app colors change —
/// never the launcher icon.
class ThemePreset {
  final String id;
  final String name;
  final Color seed;

  const ThemePreset(this.id, this.name, this.seed);
}

/// 预设主题色：朱红（默认）、靛蓝、松绿、黛紫、暖橙、石墨。
const kThemePresets = <ThemePreset>[
  ThemePreset('vermillion', '朱红', Color(0xFF9B3A2C)),
  ThemePreset('indigo', '靛蓝', Color(0xFF31478C)),
  ThemePreset('pine', '松绿', Color(0xFF2F6B4F)),
  ThemePreset('aubergine', '黛紫', Color(0xFF5F4180)),
  ThemePreset('amber', '暖橙', Color(0xFFB3651F)),
  ThemePreset('graphite', '石墨', Color(0xFF4C5157)),
];

/// 学习模式上次停留的位置：章 → 板块 → 板块内页码。
class LastStudy {
  final String chapterId;
  final String sectionId;
  final int page;

  const LastStudy({
    required this.chapterId,
    required this.sectionId,
    required this.page,
  });
}

/// An in-progress review session: a shuffled queue of question ids plus the
/// current position. Persisted as `{ids: [...], index: n}` so an unfinished
/// run survives process death and resumes exactly where it stopped.
class ReviewSession {
  final List<String> ids;
  final int index;

  const ReviewSession({required this.ids, required this.index});
}

/// One calendar day's answering totals: [answers] graded cards, of which
/// [good] were graded 熟练.
class DailyTotal {
  final String day;
  final int answers;
  final int good;

  const DailyTotal({
    required this.day,
    required this.answers,
    required this.good,
  });
}

/// One 习题模式 run — completed, or abandoned mid-way with its finished
/// part. Persisted as `practice_history` (`[{date, total, right,
/// wrongQids}]`) and wiped together with the other learning records.
///
/// 完全独立于 SRS：练习只统计会/不会，不写复习队列、不影响到期计算。
class PracticeRecord {
  /// `yyyy-MM-dd` of the run.
  final String date;

  /// 已答题数（结果页「本次题数」的口径；完整一轮 = 队列长度）。
  final int total;

  /// 答「会」的题数。
  final int right;

  /// 答「不会」的题 id（错题明细的入口）。
  final List<String> wrongQids;

  const PracticeRecord({
    required this.date,
    required this.total,
    required this.right,
    required this.wrongQids,
  });

  /// 正确率 = right / total（结果页与记录列表同口径）。
  double get accuracy => total > 0 ? right / total : 0;

  int get wrong => total - right;

  /// 防御式解析：结构不对返回 null（调用方直接丢弃该条）。
  static PracticeRecord? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final date = json['date'];
    final total = json['total'];
    final right = json['right'];
    if (date is! String || date.isEmpty) return null;
    final wrongQids = <String>[];
    final ids = json['wrongQids'];
    if (ids is List) wrongQids.addAll(ids.whereType<String>());
    return PracticeRecord(
      date: date,
      total: total is int && total >= 0 ? total : 0,
      right: right is int && right >= 0 ? right : 0,
      wrongQids: wrongQids,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': date,
        'total': total,
        'right': right,
        'wrongQids': wrongQids,
      };
}

/// How the question bank splits into 已标熟 / 复习中 / 未见面. The three
/// counts always sum to the number of questions asked for.
class SrsDistribution {
  final int mature;
  final int reviewing;
  final int unseen;

  const SrsDistribution({
    required this.mature,
    required this.reviewing,
    required this.unseen,
  });

  int get total => mature + reviewing + unseen;
}

class SrsService extends ChangeNotifier {
  final SharedPreferences _prefs;

  /// question id → SRS state.
  final Map<String, SrsState> _states;

  /// `yyyy-MM-dd` → section ids whose sub-cards were all read that day.
  final Map<String, List<String>> _learned;

  /// `yyyy-MM-dd` → section id → sub-card indices flipped to their back.
  final Map<String, Map<String, Set<int>>> _seen;

  /// The unfinished review session (null when none / completed).
  ReviewSession? _session;

  /// The section the user opened most recently — the "继续学习" target on
  /// the home screen's main entry card.
  String? _lastSection;

  /// Exact card position (章 / 板块 / 板块内页) of the most recent study
  /// visit — restored when re-entering 学习模式 (null when never / cleared).
  LastStudy? _lastStudy;

  /// Index into [kThemePresets] (0 = 朱红, the default).
  int _themeIndex;

  /// 复习随机: true = a new review session shuffles, false = due order.
  bool _reviewShuffle;

  /// `yyyy-MM-dd` → `{n: answers graded that day, g: of those, 熟练 ones}`.
  final Map<String, Map<String, int>> _daily;

  /// `yyyy-MM-dd` set of "active days": days with a review answer or a
  /// study card flipped open — the basis of the 连续打卡 streak.
  final Set<String> _activeDays;

  /// 习题模式的练习记录（追加序，旧 → 新），见 [PracticeRecord]。
  final List<PracticeRecord> _practice;

  /// Global text scale (0.9 / 1.0 / 1.15 / 1.3), persisted separately from
  /// the learning records — clearing progress keeps the font setting.
  double _fontScale;

  /// Notifies only when [fontScale] changes, so the whole app (MaterialApp
  /// text scale) can rebuild without reacting to every grade.
  final ValueNotifier<double> fontScaleListenable;

  /// Notifies only when [themePreset] changes, so MaterialApp can rebuild
  /// its theme without reacting to every grade.
  final ValueNotifier<ThemePreset> themeListenable;

  SrsService._(
    this._prefs,
    this._states,
    this._learned,
    this._seen,
    this._session,
    this._lastSection,
    this._lastStudy,
    this._daily,
    this._activeDays,
    this._practice,
    this._fontScale,
    this._themeIndex,
    this._reviewShuffle,
  ) : fontScaleListenable = ValueNotifier(_fontScale),
      themeListenable = ValueNotifier(kThemePresets[_themeIndex]);

  static Future<SrsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    final states = <String, SrsState>{};
    final learned = <String, List<String>>{};
    final seen = <String, Map<String, Set<int>>>{};
    ReviewSession? session;
    String? lastSection;
    LastStudy? lastStudy;
    final daily = <String, Map<String, int>>{};
    final activeDays = <String>{};
    final practice = <PracticeRecord>[];
    var fontScale = 1.0;
    var themeIndex = 0;
    var reviewShuffle = true;

    try {
      final raw = prefs.getString(_kStatesKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((id, v) => states[id] = SrsState.fromJson(v));
        }
      }
    } catch (_) {
      // Corrupt state file → start fresh rather than crash.
    }

    try {
      final raw = prefs.getString(_kLearnedKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((day, v) {
            if (v is List) {
              learned[day] = v.whereType<String>().toList();
            }
          });
        }
      }
    } catch (_) {
      // Same as above.
    }

    try {
      final raw = prefs.getString(_kSeenKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((day, v) {
            if (v is! Map<String, dynamic>) return;
            final bySection = <String, Set<int>>{};
            v.forEach((sectionId, indices) {
              if (indices is List) {
                bySection[sectionId] = indices.whereType<int>().toSet();
              }
            });
            if (bySection.isNotEmpty) seen[day] = bySection;
          });
        }
      }
    } catch (_) {
      // Same as above.
    }

    try {
      final raw = prefs.getString(_kSessionKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final ids = decoded['ids'];
          final index = decoded['index'];
          if (ids is List) {
            final cleaned =
                ids.whereType<String>().where((s) => s.isNotEmpty).toList();
            final pos = index is int ? index : 0;
            // A session at/past its end is complete — treat as absent.
            if (cleaned.isNotEmpty && pos >= 0 && pos < cleaned.length) {
              session = ReviewSession(ids: cleaned, index: pos);
            }
          }
        }
      }
    } catch (_) {
      // Same as above.
    }

    try {
      lastSection = prefs.getString(_kLastSectionKey);
      if (lastSection != null && lastSection.isEmpty) lastSection = null;
    } catch (_) {
      // Same as above.
    }

    try {
      final raw = prefs.getString(_kLastStudyKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final chapterId = decoded['chapterId'];
          final sectionId = decoded['sectionId'];
          final page = decoded['page'];
          if (sectionId is String && sectionId.isNotEmpty) {
            lastStudy = LastStudy(
              chapterId: chapterId is String ? chapterId : '',
              sectionId: sectionId,
              page: page is int && page > 0 ? page : 0,
            );
            lastSection ??= sectionId;
          }
        }
      }
    } catch (_) {
      // Same as above.
    }

    try {
      final themeId = prefs.getString(_kThemeColorKey);
      if (themeId != null) {
        final i = kThemePresets.indexWhere((p) => p.id == themeId);
        if (i >= 0) themeIndex = i;
      }
    } catch (_) {
      // Same as above.
    }

    try {
      final shuffle = prefs.getBool(_kReviewShuffleKey);
      if (shuffle != null) reviewShuffle = shuffle;
    } catch (_) {
      // Same as above.
    }

    try {
      final raw = prefs.getString(_kDailyKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((day, v) {
            if (v is! Map<String, dynamic>) return;
            final n = v['n'];
            final g = v['g'];
            daily[day] = {
              'n': n is int && n > 0 ? n : 0,
              'g': g is int && g > 0 ? g : 0,
            };
          });
        }
      }
    } catch (_) {
      // Same as above.
    }

    try {
      final raw = prefs.getString(_kActiveDaysKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          activeDays.addAll(decoded.whereType<String>());
        }
      }
    } catch (_) {
      // Same as above.
    }

    try {
      final raw = prefs.getString(_kPracticeKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            final record = PracticeRecord.tryParse(entry);
            if (record != null) practice.add(record);
          }
        }
      }
    } catch (_) {
      // Same as above.
    }

    try {
      final stored = prefs.getDouble(_kFontScaleKey);
      if (stored != null && stored >= 0.5 && stored <= 2.0) {
        fontScale = stored;
      }
    } catch (_) {
      // Same as above.
    }

    return SrsService._(
      prefs,
      states,
      learned,
      seen,
      session,
      lastSection,
      lastStudy,
      daily,
      activeDays,
      practice,
      fontScale,
      themeIndex,
      reviewShuffle,
    );
  }

  @override
  void dispose() {
    fontScaleListenable.dispose();
    themeListenable.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- queries

  SrsState stateOf(String questionId) =>
      _states[questionId] ?? SrsState.initial();

  List<String> learnedToday([DateTime? now]) {
    final day = formatDay(now ?? DateTime.now());
    return List.unmodifiable(_learned[day] ?? const <String>[]);
  }

  bool isLearnedToday(String sectionId, [DateTime? now]) =>
      learnedToday(now).contains(sectionId);

  /// Sub-card indices of [sectionId] that were flipped to their back today.
  Set<int> seenCards(String sectionId, [DateTime? now]) {
    final day = formatDay(now ?? DateTime.now());
    return Set<int>.of(_seen[day]?[sectionId] ?? const <int>[]);
  }

  /// How many of a section's [totalCards] sub-cards have been read today.
  int seenCount(String sectionId, int totalCards, [DateTime? now]) {
    if (totalCards <= 0) return 0;
    var count = 0;
    for (final i in seenCards(sectionId, now)) {
      if (i >= 0 && i < totalCards) count++;
    }
    return count;
  }

  int get matureCount => _states.values.where((s) => s.mature).length;

  /// The soonest due day that is still in the future (null when everything
  /// is due now or retired).
  String? nextDueDay([DateTime? now]) {
    final today = formatDay(now ?? DateTime.now());
    String? best;
    for (final s in _states.values) {
      final due = s.due;
      if (s.mature || due == null || due.compareTo(today) <= 0) continue;
      if (best == null || due.compareTo(best) < 0) best = due;
    }
    return best;
  }

  /// The unfinished review session (same shuffled queue + progress as when
  /// the user last left review mode), or null when there is none.
  ReviewSession? get reviewSession => _session;

  /// The most recently opened section id (null when never opened / cleared).
  String? get lastSection => _lastSection;

  /// The exact card position of the last study visit (null when never
  /// opened / cleared).
  LastStudy? get lastStudy => _lastStudy;

  /// 习题模式的练习记录，追加序（旧在前）；练习记录列表倒序展示。
  List<PracticeRecord> get practiceHistory => List.unmodifiable(_practice);

  // ------------------------------------------------------------ achievements

  /// Global text scale for the app (one of [kFontScaleSteps], clamped).
  double get fontScale => _fontScale;

  /// Persists a new global text scale. Use one of [kFontScaleSteps]; the
  /// value is clamped to a sane range and pushed through
  /// [fontScaleListenable] (which the MaterialApp listens to).
  Future<void> setFontScale(double value) async {
    final clamped = value.clamp(0.5, 2.0).toDouble();
    if ((clamped - _fontScale).abs() < 0.001) return;
    _fontScale = clamped;
    fontScaleListenable.value = clamped;
    try {
      await _prefs.setDouble(_kFontScaleKey, clamped);
    } catch (_) {
      // Best effort: a lost font setting must never crash the UI.
    }
  }

  // ------------------------------------------------------------- settings

  /// Currently selected theme accent (one of [kThemePresets]).
  ThemePreset get themePreset => kThemePresets[_themeIndex];

  /// Index of [themePreset] in [kThemePresets].
  int get themeIndex => _themeIndex;

  /// Switches the app-wide theme accent (选中即生效): updates
  /// [themeListenable] (which MaterialApp listens to) and persists the id.
  Future<void> setThemePreset(int index) async {
    if (index < 0 || index >= kThemePresets.length || index == _themeIndex) {
      return;
    }
    _themeIndex = index;
    themeListenable.value = kThemePresets[index];
    try {
      await _prefs.setString(_kThemeColorKey, kThemePresets[index].id);
    } catch (_) {
      // Best effort: a lost theme must never crash the UI.
    }
  }

  /// 复习随机: when on, a brand-new review session shuffles its queue;
  /// when off, questions start in due order. Persisted in prefs.
  bool get reviewShuffle => _reviewShuffle;

  Future<void> setReviewShuffle(bool value) async {
    if (value == _reviewShuffle) return;
    _reviewShuffle = value;
    try {
      await _prefs.setBool(_kReviewShuffleKey, value);
    } catch (_) {
      // Best effort: a lost toggle must never crash the UI.
    }
  }

  /// Marks today as an active day (a review answer or a study card flipped
  /// open happened). Persists only when the day is new.
  void _markActive(String day) {
    if (_activeDays.add(day)) {
      unawaited(_prefs.setString(
        _kActiveDaysKey,
        jsonEncode(_activeDays.toList()),
      ));
    }
  }

  /// Consecutive active days ending today — or ending yesterday when today
  /// has no activity yet ("streak still alive"). 0 when neither is active.
  int streak([DateTime? now]) {
    final today = now ?? DateTime.now();
    var day = DateTime(today.year, today.month, today.day);
    if (!_activeDays.contains(formatDay(day))) {
      day = day.subtract(const Duration(days: 1));
      if (!_activeDays.contains(formatDay(day))) return 0;
    }
    var count = 0;
    while (_activeDays.contains(formatDay(day))) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  /// Per-day answering totals for the [days] days ending today, oldest
  /// first. Days without answers come back as zeros so charts stay regular.
  List<DailyTotal> dailyTotals(int days, [DateTime? now]) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final out = <DailyTotal>[];
    for (var i = days - 1; i >= 0; i--) {
      final day = formatDay(today.subtract(Duration(days: i)));
      final record = _daily[day];
      out.add(DailyTotal(
        day: day,
        answers: record?['n'] ?? 0,
        good: record?['g'] ?? 0,
      ));
    }
    return out;
  }

  /// Splits [questionIds] into 已标熟 (matured) / 复习中 (scheduled or
  /// answered at least once) / 未见面 (never answered, never scheduled).
  SrsDistribution distributionOf(Iterable<String> questionIds) {
    var mature = 0;
    var reviewing = 0;
    var unseen = 0;
    for (final id in questionIds) {
      final s = stateOf(id);
      if (s.mature) {
        mature++;
      } else if (s.due != null || s.interval > 0) {
        reviewing++;
      } else {
        unseen++;
      }
    }
    return SrsDistribution(
      mature: mature,
      reviewing: reviewing,
      unseen: unseen,
    );
  }

  /// Remembers the section the user is studying, for the home screen's
  /// "继续学习" shortcut. No-op when unchanged; notification fires after an
  /// await so it can never run mid-build.
  Future<void> setLastSection(String sectionId) async {
    if (sectionId.isEmpty || sectionId == _lastSection) return;
    _lastSection = sectionId;
    await _prefs.setString(_kLastSectionKey, sectionId);
    notifyListeners();
  }

  /// Remembers the exact study position (章 / 板块 / 板块内页) so re-entering
  /// 学习模式 lands straight on the last card. Also updates the
  /// "继续学习" section pointer. Listeners are notified only when the
  /// section itself changed (page-only moves just persist silently), and
  /// always after an await so it can never run mid-build.
  Future<void> setLastStudy({
    required String chapterId,
    required String sectionId,
    required int page,
  }) async {
    if (sectionId.isEmpty) return;
    final prev = _lastStudy;
    final unchanged =
        prev != null &&
        prev.chapterId == chapterId &&
        prev.sectionId == sectionId &&
        prev.page == page;
    final sectionChanged = sectionId != _lastSection;
    if (unchanged && !sectionChanged) return;
    _lastStudy = LastStudy(
      chapterId: chapterId,
      sectionId: sectionId,
      page: page < 0 ? 0 : page,
    );
    _lastSection = sectionId;
    try {
      await _prefs.setString(
        _kLastStudyKey,
        jsonEncode({
          'chapterId': chapterId,
          'sectionId': sectionId,
          'page': page < 0 ? 0 : page,
        }),
      );
      if (sectionChanged) {
        await _prefs.setString(_kLastSectionKey, sectionId);
      }
    } catch (_) {
      // Best effort: never crash the UI over persistence.
    }
    if (sectionChanged) notifyListeners();
  }

  // ------------------------------------------------------- review session

  /// Starts a brand-new shuffled session, replacing any previous one.
  ///
  /// Deliberately does not notify listeners: it is called while the review
  /// screen is building, and session state is only read there directly.
  Future<void> startReviewSession(List<String> ids) async {
    final cleaned = ids.where((id) => id.isNotEmpty).toList();
    _session = cleaned.isEmpty ? null : ReviewSession(ids: cleaned, index: 0);
    await _persist();
  }

  /// Records one answered question: advances the session index, and on the
  /// last question completes the session (the archive is deleted; the
  /// per-question SRS states are kept by [grade]).
  Future<void> advanceReviewSession() async {
    final session = _session;
    if (session == null) return;
    final next = session.index + 1;
    _session = next >= session.ids.length
        ? null
        : ReviewSession(ids: session.ids, index: next);
    await _persist();
    notifyListeners();
  }

  /// Appends newly due question ids to the end of the active session
  /// (total only ever grows; existing progress is untouched).
  void _appendIdsToSession(Iterable<String> ids) {
    final session = _session;
    if (session == null) return;
    final existing = session.ids.toSet();
    final fresh =
        ids.where((id) => id.isNotEmpty && !existing.contains(id)).toList();
    if (fresh.isEmpty) return;
    _session = ReviewSession(
      ids: <String>[...session.ids, ...fresh],
      index: session.index,
    );
  }

  /// Drops the in-progress session (used when it completes or is cleared).
  Future<void> clearReviewSession() async {
    if (_session == null) return;
    _session = null;
    await _persist();
    notifyListeners();
  }

  /// Wipes every learning record — SRS states, learned/seen history, daily
  /// answer totals, active (打卡) days, the in-progress review session, the
  /// "继续学习" pointer, the saved study position and the 习题模式 practice
  /// history. Question/source data, content corrections (纠错覆盖) and the
  /// settings (font size, theme, shuffle) are untouched.
  Future<void> clearAllRecords() async {
    _states.clear();
    _learned.clear();
    _seen.clear();
    _daily.clear();
    _activeDays.clear();
    _practice.clear();
    _session = null;
    _lastSection = null;
    _lastStudy = null;
    await _prefs.remove(_kLastSectionKey);
    await _prefs.remove(_kLastStudyKey);
    await _prefs.remove(_kDailyKey);
    await _prefs.remove(_kActiveDaysKey);
    await _prefs.remove(_kPracticeKey);
    await _persist();
    notifyListeners();
  }

  // ----------------------------------------------------------------- writes

  /// Records a section as "今日已学" and pulls its **never-answered**
  /// non-mature questions into today's queue (due = today).
  ///
  /// Already-answered questions are deliberately left alone: their due date
  /// was set to tomorrow-or-later by the last grade, and overwriting it here
  /// is what used to re-queue a question the user had already answered the
  /// same day (and kept 今日待复习 from reaching zero).
  ///
  /// Only called once every sub-card of the section has actually been read
  /// — see [markCardSeen].
  Future<void> markLearned(
    String sectionId,
    Iterable<Question> sectionQuestions, [
    DateTime? now,
  ]) async {
    if (sectionId.isEmpty) return;
    final today = now ?? DateTime.now();
    final day = formatDay(today);
    final list = _learned.putIfAbsent(day, () => <String>[]);
    if (!list.contains(sectionId)) list.add(sectionId);

    final newlyDue = <String>[];
    for (final q in sectionQuestions) {
      final s = stateOf(q.id);
      if (s.mature) continue;
      // Never answered ⟺ no due yet and interval still 0. Anything else has
      // been graded before and keeps its own schedule.
      if (s.due != null || s.interval != 0) continue;
      _states[q.id] = SrsState(
        interval: s.interval,
        streak: s.streak,
        goodCount: s.goodCount,
        mature: false,
        due: day,
      );
      if (q.id.isNotEmpty) newlyDue.add(q.id);
    }

    // A review session in progress absorbs this section's newly due
    // questions at the end of its queue (total only grows).
    _appendIdsToSession(newlyDue);

    await _persist();
    notifyListeners();
  }

  /// Called when a sub-card is flipped to its back: records the read and,
  /// once every sub-card ([totalCards]) has been seen, marks the section
  /// learned through the regular [markLearned] path (which also pulls its
  /// questions into today's review queue). Half-read sections are never
  /// marked and never trigger a review.
  Future<void> markCardSeen(
    String sectionId,
    int cardIndex,
    int totalCards,
    Iterable<Question> sectionQuestions, [
    DateTime? now,
  ]) async {
    if (sectionId.isEmpty || totalCards <= 0) return;
    if (cardIndex < 0 || cardIndex >= totalCards) return;

    final today = now ?? DateTime.now();
    final day = formatDay(today);
    // Flipping a study card open counts as an active (打卡) day.
    _markActive(day);
    // Reading progress only matters for today — drop older days.
    _seen.removeWhere((d, _) => d != day);
    final seen = _seen
        .putIfAbsent(day, () => <String, Set<int>>{})
        .putIfAbsent(sectionId, () => <int>{});
    seen.removeWhere((i) => i < 0 || i >= totalCards);
    if (!seen.add(cardIndex)) return; // already counted

    if (seen.length >= totalCards && !isLearnedToday(sectionId, today)) {
      // All sub-cards read → reuse the regular learned-marking entry point.
      await markLearned(sectionId, sectionQuestions, today);
      return;
    }

    await _persist();
    notifyListeners();
  }

  /// Records one review answer and persists the new state: the per-question
  /// schedule, today's answer totals (for the weekly stats) and today as an
  /// active day (打卡 streak).
  Future<void> grade(String questionId, Grade grade,
      [DateTime? now]) async {
    final today = now ?? DateTime.now();
    final day = formatDay(today);
    _states[questionId] = applyGrade(stateOf(questionId), grade, today);

    final record = _daily.putIfAbsent(day, () => {'n': 0, 'g': 0});
    record['n'] = (record['n'] ?? 0) + 1;
    if (grade == Grade.good) {
      record['g'] = (record['g'] ?? 0) + 1;
    }
    _markActive(day);

    await _persist();
    notifyListeners();
  }

  /// 追加一次习题模式记录（完成或中途退出时的已完成部分）。完全独立于
  /// SRS：只落 `practice_history`，不写复习队列、不动每日统计与打卡。
  Future<void> addPracticeRecord(PracticeRecord record) async {
    _practice.add(record);
    try {
      await _prefs.setString(
        _kPracticeKey,
        jsonEncode([for (final r in _practice) r.toJson()]),
      );
    } catch (_) {
      // Best effort: never crash the UI over persistence.
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _prefs.setString(
        _kStatesKey,
        jsonEncode(_states.map((k, v) => MapEntry(k, v.toJson()))),
      );
      await _prefs.setString(
        _kLearnedKey,
        jsonEncode(_learned),
      );
      await _prefs.setString(
        _kSeenKey,
        jsonEncode(_seen.map(
          (day, bySection) => MapEntry(
            day,
            bySection.map((id, indices) => MapEntry(id, indices.toList())),
          ),
        )),
      );
      final session = _session;
      if (session == null) {
        await _prefs.remove(_kSessionKey);
      } else {
        await _prefs.setString(
          _kSessionKey,
          jsonEncode({'ids': session.ids, 'index': session.index}),
        );
      }
      await _prefs.setString(_kDailyKey, jsonEncode(_daily));
    } catch (_) {
      // Best effort: never crash the UI over persistence.
    }
  }
}

/// Builds today's review queue:
///
/// 1. **never-answered** questions of sections learned today (non-mature
///    only) — `due == null && interval == 0` is the definition of "新到期";
///    any grade pushes `due` to tomorrow-or-later, so a question answered
///    earlier the same day can never re-enter here,
/// 2. then every question with `due <= today`, sorted by due date.
///
/// Mature questions are excluded, as are answered questions whose schedule
/// still points into the future. The queue is deduplicated by question id.
List<Question> buildReviewQueue(
  AppData data,
  SrsService srs, [
  DateTime? now,
]) {
  final today = now ?? DateTime.now();
  final todayStr = formatDay(today);
  final learned = srs.learnedToday(today).toSet();

  final seen = <String>{};
  final fresh = <Question>[];
  final due = <Question>[];

  for (final q in data.questions) {
    if (q.id.isEmpty || seen.contains(q.id)) continue;
    final state = srs.stateOf(q.id);
    if (state.mature) continue;

    final isNewlyDue = state.due == null && state.interval == 0;
    if (learned.contains(q.sec) && isNewlyDue) {
      seen.add(q.id);
      fresh.add(q);
      continue;
    }
    final dueDay = state.due;
    if (dueDay == null || dueDay.compareTo(todayStr) > 0) continue;
    seen.add(q.id);
    due.add(q);
  }

  due.sort((a, b) {
    final da = srs.stateOf(a.id).due ?? '';
    final db = srs.stateOf(b.id).due ?? '';
    final c = da.compareTo(db);
    return c != 0 ? c : a.id.compareTo(b.id);
  });

  return [...fresh, ...due];
}
