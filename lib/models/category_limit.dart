class CategoryLimit {
  final String id;
  final String childId;
  final String category;
  final int dailyLimitMinutes;
  final DateTime lastUpdated;

  CategoryLimit({
    required this.id,
    required this.childId,
    required this.category,
    required this.dailyLimitMinutes,
    required this.lastUpdated,
  });

  factory CategoryLimit.fromJson(Map<String, dynamic> json) {
    return CategoryLimit(
      id: json['id'] as String,
      childId: json['child_id'] as String,
      category: json['category'] as String,
      dailyLimitMinutes: json['daily_limit_minutes'] as int,
      lastUpdated: DateTime.parse(json['last_updated'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'child_id': childId,
      'category': category,
      'daily_limit_minutes': dailyLimitMinutes,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}
