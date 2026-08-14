#!/usr/bin/env python3
"""从 Tropicals species.csv.gz（可选）+ seed 重建中英名称词表。

用法：
  # 将 species.csv.gz 放到 server/data/name_en/ 后：
  python3 scripts/build_name_en_lexicon.py
"""

from __future__ import annotations

import csv
import gzip
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "server" / "data" / "name_en" / "species.csv.gz"
OUT_DIR = ROOT / "server" / "resources" / "name_en"


def clean_en(s: str) -> str:
    s = (s or "").strip().split(",")[0].strip()
    s = re.sub(r"\s+", " ", s)
    return "" if len(s) > 40 else s


def clean_zh(s: str) -> str:
    s = re.sub(r"\s+", "", (s or "").strip())
    return s.strip("《》【】（）()")


def is_good_zh(zh: str) -> bool:
    return bool(zh) and 2 <= len(zh) <= 12 and not re.search(r"[A-Za-z0-9]", zh)


def score_row(zh: str, en: str, sub: str, country: str, has_image: str) -> float:
    sc = 0.0
    if "CN" in (country or ""):
        sc += 3
    if has_image in ("1", "true", "True"):
        sc += 1
    L = len(zh)
    sc += 5 if 2 <= L <= 4 else 3 if L == 5 else 1 if L <= 6 else -2
    en_l = len(en.split())
    sc += 3 if en_l <= 2 else 1 if en_l == 3 else -1
    prefer = {
        "观叶植物": 2,
        "热带水果": 2,
        "切花": 1,
        "热带蔬菜": 1,
        "蕨类": 1,
        "热带鱼": 2,
        "鲤科鱼": 1,
        "海水鱼": 1,
        "树蛙": 1,
        "甲虫": -1,
        "硬珊瑚": -2,
        "热带木材": -3,
    }
    sc += prefer.get(sub or "", 0)
    if zh.endswith("属") or zh.endswith("科"):
        sc -= 5
    return sc


SEED_ANIMALS = {
    "兔子": "Rabbit",
    "小兔子": "Rabbit",
    "兔": "Rabbit",
    "野兔": "Hare",
    "猫": "Cat",
    "小猫": "Cat",
    "猫咪": "Cat",
    "小猫咪": "Cat",
    "狗": "Dog",
    "小狗": "Dog",
    "小狗狗": "Dog",
    "犬": "Dog",
    "熊猫": "Panda",
    "大熊猫": "Giant Panda",
    "小猫熊": "Red Panda",
    "小熊猫": "Red Panda",
    "老虎": "Tiger",
    "狮子": "Lion",
    "大象": "Elephant",
    "长颈鹿": "Giraffe",
    "斑马": "Zebra",
    "猴子": "Monkey",
    "猩猩": "Orangutan",
    "大猩猩": "Gorilla",
    "袋鼠": "Kangaroo",
    "考拉": "Koala",
    "树袋熊": "Koala",
    "企鹅": "Penguin",
    "海豚": "Dolphin",
    "鲸鱼": "Whale",
    "鲨鱼": "Shark",
    "金鱼": "Goldfish",
    "鲤鱼": "Carp",
    "草鱼": "Grass carp",
    "青蛙": "Frog",
    "蟾蜍": "Toad",
    "乌龟": "Turtle",
    "海龟": "Sea turtle",
    "蛇": "Snake",
    "壁虎": "Gecko",
    "蜥蜴": "Lizard",
    "鳄鱼": "Crocodile",
    "蝴蝶": "Butterfly",
    "蜜蜂": "Bee",
    "蚂蚁": "Ant",
    "蜻蜓": "Dragonfly",
    "蜗牛": "Snail",
    "螃蟹": "Crab",
    "龙虾": "Lobster",
    "章鱼": "Octopus",
    "鸡": "Chicken",
    "小鸡": "Chick",
    "鸭": "Duck",
    "鹅": "Goose",
    "鸽子": "Pigeon",
    "麻雀": "Sparrow",
    "燕子": "Swallow",
    "老鹰": "Eagle",
    "猫头鹰": "Owl",
    "孔雀": "Peacock",
    "鹦鹉": "Parrot",
    "天鹅": "Swan",
    "马": "Horse",
    "小马": "Pony",
    "牛": "Cow",
    "羊": "Sheep",
    "小羊": "Lamb",
    "猪": "Pig",
    "小猪": "Piglet",
    "老鼠": "Mouse",
    "仓鼠": "Hamster",
    "刺猬": "Hedgehog",
    "松鼠": "Squirrel",
    "狐狸": "Fox",
    "狼": "Wolf",
    "熊": "Bear",
    "棕熊": "Brown bear",
    "北极熊": "Polar bear",
    "骆驼": "Camel",
    "鹿": "Deer",
    "梅花鹿": "Sika deer",
    "麋鹿": "Elk",
    "河马": "Hippo",
    "犀牛": "Rhino",
    "海豹": "Seal",
    "海狮": "Sea lion",
    "海星": "Starfish",
    "水母": "Jellyfish",
    "蚕": "Silkworm",
    "萤火虫": "Firefly",
    "知了": "Cicada",
    "蝉": "Cicada",
    "瓢虫": "Ladybug",
    "蚊子": "Mosquito",
    "苍蝇": "Fly",
    "蟑螂": "Cockroach",
}

SEED_PLANTS = {
    "向日葵": "Sunflower",
    "荷花": "Lotus",
    "莲花": "Lotus",
    "玫瑰": "Rose",
    "月季": "China rose",
    "牡丹": "Peony",
    "芍药": "Peony",
    "菊花": "Chrysanthemum",
    "梅花": "Plum blossom",
    "桃花": "Peach blossom",
    "樱花": "Cherry blossom",
    "兰花": "Orchid",
    "桂花": "Osmanthus",
    "茉莉": "Jasmine",
    "茉莉花": "Jasmine",
    "郁金香": "Tulip",
    "百合": "Lily",
    "康乃馨": "Carnation",
    "满天星": "Baby's breath",
    "银杏": "Ginkgo",
    "柳树": "Willow",
    "松树": "Pine",
    "柏树": "Cypress",
    "竹子": "Bamboo",
    "水稻": "Rice",
    "小麦": "Wheat",
    "玉米": "Corn",
    "土豆": "Potato",
    "马铃薯": "Potato",
    "番茄": "Tomato",
    "西红柿": "Tomato",
    "黄瓜": "Cucumber",
    "茄子": "Eggplant",
    "辣椒": "Chili pepper",
    "白菜": "Cabbage",
    "萝卜": "Radish",
    "胡萝卜": "Carrot",
    "洋葱": "Onion",
    "大蒜": "Garlic",
    "苹果": "Apple",
    "香蕉": "Banana",
    "橙子": "Orange",
    "橘子": "Tangerine",
    "葡萄": "Grape",
    "西瓜": "Watermelon",
    "草莓": "Strawberry",
    "菠萝": "Pineapple",
    "芒果": "Mango",
    "梨": "Pear",
    "桃": "Peach",
    "李子": "Plum",
    "仙人掌": "Cactus",
    "多肉": "Succulent",
    "芦荟": "Aloe",
    "牵牛花": "Morning glory",
    "蒲公英": "Dandelion",
    "三叶草": "Clover",
    "枫树": "Maple",
    "梧桐": "Plane tree",
    "樟树": "Camphor tree",
    "麦子": "Wheat",
    "高粱": "Sorghum",
    "大豆": "Soybean",
    "花生": "Peanut",
    "芝麻": "Sesame",
    "棉花": "Cotton",
    "茶": "Tea",
    "咖啡": "Coffee",
    "可可": "Cocoa",
    "椰子": "Coconut",
    "榴莲": "Durian",
}

SEED_TRANSPORT = {
    "校车": "School bus",
    "公交车": "Bus",
    "公共汽车": "Bus",
    "汽车": "Car",
    "小汽车": "Car",
    "火车": "Train",
    "高铁": "High-speed train",
    "地铁": "Subway",
    "飞机": "Airplane",
    "直升机": "Helicopter",
    "轮船": "Ship",
    "帆船": "Sailboat",
    "自行车": "Bicycle",
    "摩托车": "Motorcycle",
    "卡车": "Truck",
    "救护车": "Ambulance",
    "消防车": "Fire truck",
    "警车": "Police car",
    "出租车": "Taxi",
    "灯塔": "Lighthouse",
    "桥": "Bridge",
    "房子": "House",
    "学校": "School",
    "医院": "Hospital",
}


def pick(bucket, limit):
    best = {}
    for sc, zh, en, src in bucket:
        prev = best.get(zh)
        if prev is None or sc > prev[0]:
            best[zh] = (sc, zh, en, src)
    items = sorted(best.values(), key=lambda x: (-x[0], x[1]))
    return [{"zh": it[1], "en": it[2], "source": it[3]} for it in items[:limit]]


def main() -> None:
    animals = []
    plants = []
    seen_a = set()
    seen_p = set()

    if SRC.is_file():
        with gzip.open(SRC, "rt", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                zh = clean_zh(row.get("name_zh") or "")
                en = clean_en(row.get("vernacularName") or "")
                if not is_good_zh(zh) or not en:
                    continue
                cat = row.get("category") or ""
                sc = score_row(
                    zh,
                    en,
                    row.get("subcategory") or "",
                    row.get("countryCode") or "",
                    row.get("has_image") or "",
                )
                alts = [zh]
                for a in (row.get("vernacularName_alt") or "").split(","):
                    a = clean_zh(a)
                    if is_good_zh(a):
                        alts.append(a)
                bucket = plants if cat == "tropical_plants" else animals
                seen = seen_p if cat == "tropical_plants" else seen_a
                for a in alts:
                    if a in seen:
                        continue
                    bucket.append((sc if a == zh else sc - 0.5, a, en, "tropicals"))
                    seen.add(a)
        print(f"loaded tropicals from {SRC}")
    else:
        print(f"skip tropicals (missing {SRC})")

    for zh, en in SEED_ANIMALS.items():
        animals.append((100.0, zh, en, "seed"))
    for zh, en in SEED_PLANTS.items():
        plants.append((100.0, zh, en, "seed"))

    animals_out = pick(animals, 1200)
    plants_out = pick(plants, 1200)

    prio = {"seed": 3, "wikidata": 2, "tropicals": 1, "transport_seed": 3}
    merged = {}
    meta = {}
    for cat, rows in (("animal", animals_out), ("plant", plants_out)):
        for r in rows:
            zh, en, src = r["zh"], r["en"], r["source"]
            if zh not in merged or prio[src] > prio.get(meta[zh]["source"], 0):
                merged[zh] = en
                meta[zh] = {"en": en, "category": cat, "source": src}

    for zh, en in SEED_TRANSPORT.items():
        merged[zh] = en
        meta[zh] = {"en": en, "category": "transport", "source": "transport_seed"}

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "license_notes": [
            "Derived in part from Tropicals.cn Tropical Species Encyclopedia (CC-BY 4.0); attribution: Tropicals.cn https://tropicals.cn",
            "Seed entries curated for 识图 children app.",
        ],
        "counts": {
            "total": len(merged),
            "animal": sum(1 for v in meta.values() if v["category"] == "animal"),
            "plant": sum(1 for v in meta.values() if v["category"] == "plant"),
            "transport": sum(1 for v in meta.values() if v["category"] == "transport"),
        },
        "entries": [
            {
                "zh": k,
                "en": v["en"],
                "category": v["category"],
                "source": v["source"],
            }
            for k, v in sorted(meta.items(), key=lambda kv: (kv[1]["category"], kv[0]))
        ],
    }
    (OUT_DIR / "zh_en_species.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    (OUT_DIR / "zh_en_map.json").write_text(
        json.dumps(merged, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    print("wrote", payload["counts"], "->", OUT_DIR)


if __name__ == "__main__":
    main()
