"""学习次数 → 等级（前期好升、后期变难）。

累计门槛见 LEVEL_THRESHOLDS：索引 0 对应 Lv1（0 次），
索引 i 对应 Lv(i+1) 所需最少 learn_count。
"""

from __future__ import annotations

from typing import Optional, Tuple

# Lv1..Lv20 所需累计学习次数（含该级）
LEVEL_THRESHOLDS: tuple[int, ...] = (
    0,  # Lv1
    1,  # Lv2
    3,  # Lv3
    6,  # Lv4
    10,  # Lv5
    16,  # Lv6
    24,  # Lv7
    34,  # Lv8
    48,  # Lv9
    66,  # Lv10
    90,  # Lv11
    120,  # Lv12
    158,  # Lv13
    206,  # Lv14
    266,  # Lv15
    341,  # Lv16
    436,  # Lv17
    556,  # Lv18
    706,  # Lv19
    896,  # Lv20
)

MAX_LEVEL = len(LEVEL_THRESHOLDS)


def level_from_learn_count(learn_count: int) -> int:
    n = max(0, int(learn_count or 0))
    level = 1
    for i, need in enumerate(LEVEL_THRESHOLDS):
        if n >= need:
            level = i + 1
        else:
            break
    return level


def next_level_progress(learn_count: int) -> Tuple[int, Optional[int], Optional[int]]:
    """返回 (current_level, next_level|None, learns_to_next|None)。"""
    n = max(0, int(learn_count or 0))
    level = level_from_learn_count(n)
    if level >= MAX_LEVEL:
        return level, None, None
    next_level = level + 1
    need = LEVEL_THRESHOLDS[next_level - 1]
    return level, next_level, max(0, need - n)


def level_hint(learn_count: int) -> str:
    level, nxt, remain = next_level_progress(learn_count)
    if nxt is None or remain is None:
        return "已是最高等级啦"
    return f"再学 {remain} 次就到 Lv {nxt}"
