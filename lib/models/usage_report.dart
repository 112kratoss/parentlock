/// Usage Report Model
/// 
/// Aggregated usage data for activity reports and trends.
library;

class DailyUsageSummary {
  final String id;
  final String childId;
  final DateTime date;
  final int totalMinutes;
  final Map<String, int> appBreakdown;  // packageName -> minutes
  final String? mostUsedApp;
  final int blockedAttempts;
  final DateTime createdAt;

  DailyUsageSummary({
    required this.id,
    required this.childId,
    required this.date,
    required this.totalMinutes,
    required this.appBreakdown,
    this.mostUsedApp,
    this.blockedAttempts = 0,
    required this.createdAt,
  });

  /// Create from Supabase JSON response
  factory DailyUsageSummary.fromJson(Map<String, dynamic> json) {
    Map<String, int> breakdown = {};
    if (json['app_breakdown'] != null) {
      final raw = json['app_breakdown'] as Map<String, dynamic>;
      breakdown = raw.map((k, v) => MapEntry(k, v as int));
    }

    return DailyUsageSummary(
      id: json['id'] as String,
      childId: json['child_id'] as String,
      date: DateTime.parse(json['date'] as String),
      totalMinutes: json['total_minutes'] as int? ?? 0,
      appBreakdown: breakdown,
      mostUsedApp: json['most_used_app'] as String?,
      blockedAttempts: json['blocked_attempts'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'child_id': childId,
      'date': date.toIso8601String().split('T')[0],  // DATE format
      'total_minutes': totalMinutes,
      'app_breakdown': appBreakdown,
      'most_used_app': mostUsedApp,
      'blocked_attempts': blockedAttempts,
    };
  }

  /// Get total hours (formatted)
  String get totalHoursDisplay {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  /// Get top N apps by usage
  List<MapEntry<String, int>> getTopApps(int n) {
    final sorted = appBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).toList();
  }
}

/// Weekly summary aggregating daily data
class WeeklyUsageSummary {
  final String childId;
  final DateTime weekStart;
  final DateTime weekEnd;
  final int totalMinutes;
  final double averageMinutesPerDay;
  final List<DailyUsageSummary> dailySummaries;
  final Map<String, int> categoryBreakdown;

  WeeklyUsageSummary({
    required this.childId,
    required this.weekStart,
    required this.weekEnd,
    required this.totalMinutes,
    required this.averageMinutesPerDay,
    required this.dailySummaries,
    required this.categoryBreakdown,
  });

  /// Create from list of daily summaries
  factory WeeklyUsageSummary.fromDailySummaries(
    String childId,
    List<DailyUsageSummary> summaries,
  ) {
    if (summaries.isEmpty) {
      return WeeklyUsageSummary(
        childId: childId,
        weekStart: DateTime.now(),
        weekEnd: DateTime.now(),
        totalMinutes: 0,
        averageMinutesPerDay: 0,
        dailySummaries: [],
        categoryBreakdown: {},
      );
    }

    final sorted = [...summaries]..sort((a, b) => a.date.compareTo(b.date));
    final total = summaries.fold<int>(0, (sum, s) => sum + s.totalMinutes);
    final average = total / summaries.length;

    // Aggregate all app usage
    final Map<String, int> allApps = {};
    for (final summary in summaries) {
      summary.appBreakdown.forEach((app, mins) {
        allApps[app] = (allApps[app] ?? 0) + mins;
      });
    }

    return WeeklyUsageSummary(
      childId: childId,
      weekStart: sorted.first.date,
      weekEnd: sorted.last.date,
      totalMinutes: total,
      averageMinutesPerDay: average,
      dailySummaries: summaries,
      categoryBreakdown: allApps,
    );
  }

  /// Get total hours (formatted)
  String get totalHoursDisplay {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return '${hours}h ${mins}m';
  }

  /// Get average hours per day (formatted)
  String get averageDisplay {
    final hours = averageMinutesPerDay ~/ 60;
    final mins = (averageMinutesPerDay % 60).round();
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  /// Get data for bar chart (minutes per day)
  List<int> get dailyMinutes {
    return dailySummaries.map((s) => s.totalMinutes).toList();
  }
}

/// App category mapping (for report categorization)
class AppCategoryMapper {
  static const Map<String, String> _knownApps = {
    // Social
    'com.instagram.android': 'social',
    'com.facebook.katana': 'social',
    'com.snapchat.android': 'social',
    'com.twitter.android': 'social',
    'com.zhiliaoapp.musically': 'social',  // TikTok
    'com.whatsapp': 'social',
    'org.telegram.messenger': 'social',
    
    // Video
    'com.google.android.youtube': 'video',
    'com.netflix.mediaclient': 'video',
    'com.amazon.avod.thirdpartyclient': 'video',  // Prime Video
    'com.disney.disneyplus': 'video',
    
    // Games
    'com.supercell.clashofclans': 'games',
    'com.king.candycrushsaga': 'games',
    'com.roblox.client': 'games',
    'com.mojang.minecraftpe': 'games',
    
    // Education
    'com.duolingo': 'education',
    'com.google.android.apps.classroom': 'education',
    'com.khanacademy': 'education',
  };

  static String categorize(String packageName) {
    // Check known apps
    if (_knownApps.containsKey(packageName)) {
      return _knownApps[packageName]!;
    }
    
    // Heuristic categorization
    final lower = packageName.toLowerCase();
    if (lower.contains('game') || lower.contains('play')) return 'games';
    if (lower.contains('social') || lower.contains('chat')) return 'social';
    if (lower.contains('video') || lower.contains('stream')) return 'video';
    if (lower.contains('edu') || lower.contains('learn')) return 'education';
    
    return 'other';
  }

  /// Aggregate usage by category
  static Map<String, int> aggregateByCategory(Map<String, int> appUsage) {
    final Map<String, int> categories = {};
    appUsage.forEach((package, minutes) {
      final category = categorize(package);
      categories[category] = (categories[category] ?? 0) + minutes;
    });
    return categories;
  }
}
