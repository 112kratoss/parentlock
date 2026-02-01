/// Child Activity Model
/// 
/// Tracks app usage and limits for a child's device.
/// Used for monitoring and blocking apps when limits are exceeded.
library;

class ChildActivity {
  final String id;
  final String childId;
  final String appPackageName;
  final String appDisplayName;
  final int dailyLimitMinutes;
  final int minutesUsed;
  final bool isBlocked;
  final DateTime lastUpdated;
  final String category; // 'social', 'game', etc. (System detected)
  final String? manualCategory; // User override

  ChildActivity({
    required this.id,
    required this.childId,
    required this.appPackageName,
    required this.appDisplayName,
    required this.dailyLimitMinutes,
    required this.minutesUsed,
    required this.isBlocked,
    required this.lastUpdated,
    this.category = 'other',
    this.manualCategory,
  });

  /// Create from Supabase JSON response
  factory ChildActivity.fromJson(Map<String, dynamic> json) {
    return ChildActivity(
      id: json['id'] as String,
      childId: json['child_id'] as String,
      appPackageName: json['app_package_name'] as String,
      appDisplayName: json['app_display_name'] as String,
      dailyLimitMinutes: json['daily_limit_minutes'] as int,
      minutesUsed: json['minutes_used'] as int,
      isBlocked: json['is_blocked'] as bool,
      lastUpdated: DateTime.parse(json['last_updated'] as String),
      category: json['category'] as String? ?? 'other',
      manualCategory: json['manual_category'] as String?,
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'child_id': childId,
      'app_package_name': appPackageName,
      'app_display_name': appDisplayName,
      'daily_limit_minutes': dailyLimitMinutes,
      'minutes_used': minutesUsed,
      'is_blocked': isBlocked,
      'last_updated': lastUpdated.toIso8601String(),
      'category': category,
      'manual_category': manualCategory,
    };
  }

  /// Create a copy with updated fields
  ChildActivity copyWith({
    String? id,
    String? childId,
    String? appPackageName,
    String? appDisplayName,
    int? dailyLimitMinutes,
    int? minutesUsed,
    bool? isBlocked,
    DateTime? lastUpdated,
    String? category,
    String? manualCategory,
  }) {
    return ChildActivity(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      appPackageName: appPackageName ?? this.appPackageName,
      appDisplayName: appDisplayName ?? this.appDisplayName,
      dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
      minutesUsed: minutesUsed ?? this.minutesUsed,
      isBlocked: isBlocked ?? this.isBlocked,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      category: category ?? this.category,
      manualCategory: manualCategory ?? this.manualCategory,
    );
  }

  /// Get effective category (Manual > System > Other)
  String get effectiveCategory => manualCategory?.isNotEmpty == true ? manualCategory! : category;

  /// Remaining minutes before limit
  int get remainingMinutes => dailyLimitMinutes - minutesUsed;
  
  /// Whether the limit has been exceeded
  bool get isLimitExceeded => minutesUsed >= dailyLimitMinutes;

  /// Whether the app is effectively blocked (manual or limit exceeded)
  bool get isEffectivelyBlocked => isBlocked || isLimitExceeded;
  
  /// Usage percentage (0.0 to 1.0+)
  double get usagePercentage => dailyLimitMinutes > 0 
      ? minutesUsed / dailyLimitMinutes 
      : 0.0;
}
