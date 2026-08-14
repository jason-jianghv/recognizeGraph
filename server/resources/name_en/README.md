# 中英名称词表（识图）

## 文件
- `zh_en_map.json`：运行时查表（中文 → 英文）
- `zh_en_species.json`：带 category/source 的完整条目（便于审计）

## 规模（约）
- 动物 ≥1000、植物 ≥1000（另含少量交通建筑常用名）
- 来源优先级：seed（儿童向精校）> Wikidata 标签 > Tropicals.cn 俗名

## 授权与署名
- 部分条目衍生自 **Tropicals.cn Tropical Species Encyclopedia**（**CC-BY 4.0**）  
  请保留署名：Tropicals.cn — https://tropicals.cn  
- Wikidata 标签通常为 CC0
- seed 条目由识图项目为儿童点读精校

## 重建
可选下载 Tropicals `species.csv.gz` 后运行：

```bash
python3 scripts/build_name_en_lexicon.py
```
