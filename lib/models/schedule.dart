/// Schedule Model
/// 
/// Represents a screen time schedule (bedtime, homework, allowed hours).
library;

/// Schedule types
enum ScheduleType {
  allowedHours,  // When phone is allowed
  bedtime,       // Block everything at night
  homework;      // Block distracting apps during study

  String toJson() {
    switch (this) {
      case ScheduleType.allowedHours:
        return 'allowed_hours';
      case ScheduleType.bedtime:
        return 'bedtime';
      case ScheduleType.homework:
        return 'homework';
    }
  }

  static ScheduleType fromJson(String json) {
    switch (json) {
      case 'allowed_hours':
        return ScheduleType.allowedHours;
      case 'bedtime':
        return ScheduleType.bedtime;
      case 'homework':
        return ScheduleType.homework;
      default:
        return ScheduleType.allowedHours;
    }
  }

  String get displayName {
    switch (this) {
      case ScheduleType.allowedHours:
        return 'Allowed Hours';
      case ScheduleType.bedtime:
        return 'Bedtime';
      case ScheduleType.homework:
        return 'Homework Time';
    }
  }

  String get icon {
    switch (this) {
      case ScheduleType.allowedHours:
        return '📱';
      case ScheduleType.bedtime:
        return '🌙';
      case ScheduleType.homework:
        return '📚';
    }
  }
}

/// App categories that can be blocked
enum AppCategory {
  games,
  social,
  video,
  music,
  education,
  productivity;

  String get displayName {
    switch (this) {
      case AppCategory.games:
        return 'Games';
      case AppCategory.social:
        return 'Social Media';
      case AppCategory.video:
        return 'Video & Streaming';
      case AppCategory.music:
        return 'Music';
      case AppCategory.education:
        return 'Education';
      case AppCategory.productivity:
        return 'Productivity';
    }
  }
}

class Schedule {
  final String id;
  final String parentId;
  final String childId;
  final String name;
  final ScheduleType scheduleType;
  final List<int> daysOfWeek;  // 0=Sun, 1=Mon, etc.
  final TimeOfDayData startTime;
  final TimeOfDayData endTime;
  final List<String>? blockedCategories;
  final bool blockAllApps;
  final bool isActive;
  final DateTime createdAt;

  Schedule({
    required this.id,
    required this.parentId,
    required this.childId,
    required this.name,
    required this.scheduleType,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    this.blockedCategories,
    this.blockAllApps = false,
    this.isActive = true,
    required this.createdAt,
  });

  /// Create from Supabase JSON response
  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id'] as String,
      parentId: json['parent_id'] as String,
      childId: json['child_id'] as String,
      name: json['name'] as String,
      scheduleType: ScheduleType.fromJson(json['schedule_type'] as String),
      daysOfWeek: (json['days_of_week'] as List).cast<int>(),
      startTime: TimeOfDayData.fromTimeString(json['start_time'] as String),
      endTime: TimeOfDayData.fromTimeString(json['end_time'] as String),
      blockedCategories: json['blocked_categories'] != null
          ? (json['blocked_categories'] as List).cast<String>()
          : null,
      blockAllApps: json['block_all_apps'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'parent_id': parentId,
      'child_id': childId,
      'name': name,
      'schedule_type': scheduleType.toJson(),
      'days_of_week': daysOfWeek,
      'start_time': startTime.toTimeString(),
      'end_time': endTime.toTimeString(),
      'blocked_categories': blockedCategories,
      'block_all_apps': blockAllApps,
      'is_active': isActive,
    };
  }

  /// Check if schedule is active right now
  bool isActiveNow(DateTime now) {
    if (!isActive) return false;

    // Check day of week (DateTime uses 1=Mon, 7=Sun, but we use 0=Sun, 1=Mon)
    final dayOfWeek = now.weekday == 7 ? 0 : now.weekday;
    if (!daysOfWeek.contains(dayOfWeek)) return false;

    // Check time
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;

    // Handle overnight schedules (e.g., 9 PM - 7 AM)
    if (startMinutes > endMinutes) {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }

    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  /// Get human-readable time range
  String get timeRangeDisplay {
    return '${startTime.format()} - ${endTime.format()}';
  }

  /// Get human-readable days display
  String get daysDisplay {
    if (daysOfWeek.length == 7) return 'Every day';
    if (_listEquals(daysOfWeek, [1, 2, 3, 4, 5])) return 'Weekdays';
    if (_listEquals(daysOfWeek, [0, 6])) return 'Weekends';
    
    final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return daysOfWeek.map((d) => dayNames[d]).join(', ');
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final sortedA = [...a]..sort();
    final sortedB = [...b]..sort();
    for (int i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }

  /// Create a copy with updated fields
  Schedule copyWith({
    String? id,
    String? parentId,
    String? childId,
    String? name,
    ScheduleType? scheduleType,
    List<int>? daysOfWeek,
    TimeOfDayData? startTime,
    TimeOfDayData? endTime,
    List<String>? blockedCategories,
    bool? blockAllApps,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Schedule(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      childId: childId ?? this.childId,
      name: name ?? this.name,
      scheduleType: scheduleType ?? this.scheduleType,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      blockedCategories: blockedCategories ?? this.blockedCategories,
      blockAllApps: blockAllApps ?? this.blockAllApps,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'Schedule(name: $name, type: ${scheduleType.displayName}, time: $timeRangeDisplay)';
  }
}

/// Simple time of day data class (to avoid Flutter dependency in model)
class TimeOfDayData {
  final int hour;
  final int minute;

  const TimeOfDayData({required this.hour, required this.minute});

  /// Parse from "HH:MM:SS" or "HH:MM" format
  factory TimeOfDayData.fromTimeString(String time) {
    final parts = time.split(':');
    return TimeOfDayData(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  /// Convert to "HH:MM:SS" format for Supabase TIME type
  String toTimeString() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  /// Human-readable format (e.g., "9:00 PM")
  String format() {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}
