enum RecognizeCategory {
  animal('animal', '动物'),
  plant('plant', '植物'),
  transport('transport', '交通与建筑');

  const RecognizeCategory(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class RecognizeCandidate {
  const RecognizeCandidate({
    required this.id,
    required this.name,
    required this.score,
    required this.oneLiner,
    this.baikeUrl = '',
    this.imageUrl = '',
    this.description = '',
  });

  final String id;
  final String name;
  final double score;
  final String oneLiner;
  final String baikeUrl;
  final String imageUrl;
  final String description;

  factory RecognizeCandidate.fromJson(Map<String, dynamic> json) {
    return RecognizeCandidate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      oneLiner: json['one_liner'] as String? ?? '',
      baikeUrl: json['baike_url'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

class RecognizeResult {
  const RecognizeResult({
    required this.category,
    required this.candidates,
  });

  final RecognizeCategory category;
  final List<RecognizeCandidate> candidates;
}

class ExploreItem {
  const ExploreItem({
    required this.id,
    required this.name,
    required this.oneLiner,
    required this.emoji,
    required this.category,
    this.description = '',
  });

  final String id;
  final String name;
  final String oneLiner;
  final String emoji;
  final RecognizeCategory category;
  final String description;
}
