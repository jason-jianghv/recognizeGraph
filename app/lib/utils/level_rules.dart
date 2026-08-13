/// 与后端 `app/auth/levels.py` 保持一致：前期好升、后期变难。
abstract final class LevelRules {
  static const thresholds = <int>[
    0, 1, 3, 6, 10, 16, 24, 34, 48, 66,
    90, 120, 158, 206, 266, 341, 436, 556, 706, 896,
  ];

  static int get maxLevel => thresholds.length;

  static int levelFromLearnCount(int learnCount) {
    final n = learnCount < 0 ? 0 : learnCount;
    var level = 1;
    for (var i = 0; i < thresholds.length; i++) {
      if (n >= thresholds[i]) {
        level = i + 1;
      } else {
        break;
      }
    }
    return level;
  }

  static int? nextLevel(int learnCount) {
    final level = levelFromLearnCount(learnCount);
    if (level >= maxLevel) return null;
    return level + 1;
  }

  static int? learnsToNext(int learnCount) {
    final nxt = nextLevel(learnCount);
    if (nxt == null) return null;
    final need = thresholds[nxt - 1];
    final n = learnCount < 0 ? 0 : learnCount;
    final remain = need - n;
    return remain < 0 ? 0 : remain;
  }

  static String hint(int learnCount) {
    final nxt = nextLevel(learnCount);
    final remain = learnsToNext(learnCount);
    if (nxt == null || remain == null) return '已是最高等级啦';
    return '再学 $remain 次就到 Lv $nxt';
  }
}
