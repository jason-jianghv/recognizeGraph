"""探索展示用：近义/叠词别名 → 规范名；个例昵称不进探索。

规则（儿童向、明显同种才合并）：
- 小狗狗 → 小狗；小猫咪/猫咪 → 小猫
- 熊猫 → 大熊猫；小猫熊 → 小熊猫（红熊猫，与大熊猫分开）
- 同物异名：马铃薯/西红柿/茉莉花/莲花/公共汽车/小汽车/树袋熊/野兔/小兔子/麦子
- 个例名（圆仔、团团圆圆）不进探索，但不改识别写库名
"""

from __future__ import annotations

# 别名 → 规范名（仅名称；调用方保证同分类语境）
SPECIES_ALIASES: dict[str, str] = {
    # 动物 · 叠词/昵称
    "小狗狗": "小狗",
    "小猫咪": "小猫",
    "猫咪": "小猫",
    "小兔子": "兔子",
    "野兔": "兔子",
    # 动物 · 同物异名（注意：小熊猫 ≠ 大熊猫）
    "熊猫": "大熊猫",
    "小猫熊": "小熊猫",
    "树袋熊": "考拉",
    # 植物
    "马铃薯": "土豆",
    "西红柿": "番茄",
    "茉莉花": "茉莉",
    "莲花": "荷花",
    "麦子": "小麦",
    # 交通
    "公共汽车": "公交车",
    "小汽车": "汽车",
}

# 个体/昵称：保留行但不进探索
EXPLORE_EXCLUDE_NAMES: frozenset[str] = frozenset(
    {
        "圆仔",
        "团团圆圆",
    }
)


def canonical_species_name(name: str) -> str:
    """识别/种子写入前：别名收束到规范名。"""
    n = (name or "").strip()
    return SPECIES_ALIASES.get(n, n)


def should_hide_from_explore(name: str) -> bool:
    """别名行、个例昵称：探索列表 is_common=0。"""
    n = (name or "").strip()
    if n in EXPLORE_EXCLUDE_NAMES:
        return True
    if n in SPECIES_ALIASES:
        return True
    return False
