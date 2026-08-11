import 'package:shitu_app/models/models.dart';

final exploreAnimals = <ExploreItem>[
  ExploreItem(
    id: 'rabbit',
    name: '小兔子',
    oneLiner: '长耳朵，爱吃胡萝卜',
    emoji: '🐰',
    category: RecognizeCategory.animal,
    description: '兔子是可爱的小动物，走路一蹦一跳。它们喜欢吃青菜和胡萝卜，耳朵很长，听声音特别灵敏。',
  ),
  ExploreItem(
    id: 'cat',
    name: '小猫咪',
    oneLiner: '喵喵叫，爱晒太阳',
    emoji: '🐱',
    category: RecognizeCategory.animal,
    description: '猫咪是很多小朋友的好朋友。它们会呼噜呼噜，喜欢干净，晚上也能看清楚东西。',
  ),
  ExploreItem(
    id: 'panda',
    name: '小熊猫',
    oneLiner: '黑眼圈，爱吃竹子',
    emoji: '🐼',
    category: RecognizeCategory.animal,
    description: '大熊猫黑白相间，特别喜欢吃竹子。它们是中国的国宝，也是大家眼里的萌萌宝贝。',
  ),
];

final explorePlants = <ExploreItem>[
  ExploreItem(
    id: 'sunflower',
    name: '向日葵',
    oneLiner: '跟着太阳转的大黄花',
    emoji: '🌻',
    category: RecognizeCategory.plant,
    description: '向日葵开出金黄色大花盘，花会慢慢转向太阳。籽粒可以做成香香的瓜子。',
  ),
  ExploreItem(
    id: 'lotus',
    name: '荷花',
    oneLiner: '夏天池塘里的粉红花',
    emoji: '🪷',
    category: RecognizeCategory.plant,
    description: '荷花长在水里，叶子又圆又大。夏天盛开，有的是粉红，有的是白色。',
  ),
  ExploreItem(
    id: 'ginkgo',
    name: '银杏',
    oneLiner: '秋天变成小扇子叶',
    emoji: '🍂',
    category: RecognizeCategory.plant,
    description: '银杏叶子像小扇子。秋天会变成金色，铺满小路，特别好看。',
  ),
];

final exploreTransport = <ExploreItem>[
  ExploreItem(
    id: 'bus',
    name: '校车',
    oneLiner: '黄色大个子，送小朋友上学',
    emoji: '🚌',
    category: RecognizeCategory.transport,
    description: '校车通常是黄色的，车身很长，专门接送小朋友安全上下学。',
  ),
  ExploreItem(
    id: 'train',
    name: '火车',
    oneLiner: '沿着铁轨呜呜跑',
    emoji: '🚆',
    category: RecognizeCategory.transport,
    description: '火车在铁轨上行驶，可以载很多人去很远的地方，发出呜呜的声音。',
  ),
  ExploreItem(
    id: 'lighthouse',
    name: '灯塔',
    oneLiner: '海边指路的亮亮塔',
    emoji: '🗼',
    category: RecognizeCategory.transport,
    description: '灯塔立在海边或岛上，夜里发出亮光，帮助船只认清方向、安全航行。',
  ),
];

List<ExploreItem> itemsFor(RecognizeCategory category) {
  switch (category) {
    case RecognizeCategory.animal:
      return exploreAnimals;
    case RecognizeCategory.plant:
      return explorePlants;
    case RecognizeCategory.transport:
      return exploreTransport;
  }
}
