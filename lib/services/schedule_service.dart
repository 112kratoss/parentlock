/// Schedule Service
/// 
/// Manages screen time schedules (bedtime, homework, allowed hours).
/// Checks if device should be locked based on active schedules.
library;

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/schedule.dart';

class ScheduleService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  Timer? _checkTimer;
  String? _currentChildId;
  void Function(Schedule?)? _onScheduleChange;
  Schedule? _currentActiveSchedule;

  // ==================== CRUD OPERATIONS ====================

  /// Create a new schedule
  Future<Schedule> createSchedule(Schedule schedule) async {
    final response = await _supabase
        .from('schedules')
        .insert(schedule.toJson())
        .select()
        .single();

    return Schedule.fromJson(response);
  }

  /// Get all schedules for a child
  Future<List<Schedule>> getSchedules(String childId) async {
    final response = await _supabase
        .from('schedules')
        .select()
        .eq('child_id', childId)
        .order('created_at');

    return (response as List)
        .map((json) => Schedule.fromJson(json))
        .toList();
  }

  /// Get schedules created by a parent
  Future<List<Schedule>> getSchedulesByParent(String parentId) async {
    final response = await _supabase
        .from('schedules')
        .select()
        .eq('parent_id', parentId)
        .order('created_at');

    return (response as List)
        .map((json) => Schedule.fromJson(json))
        .toList();
  }

  /// Update a schedule
  Future<void> updateSchedule(Schedule schedule) async {
    await _supabase
        .from('schedules')
        .update(schedule.toJson())
        .eq('id', schedule.id);
  }

  /// Delete a schedule
  Future<void> deleteSchedule(String id) async {
    await _supabase.from('schedules').delete().eq('id', id);
  }

  /// Toggle schedule active status
  Future<void> toggleScheduleActive(String id, bool isActive) async {
    await _supabase
        .from('schedules')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  // ==================== SCHEDULE CHECKING ====================

  /// Get the currently active schedule for a child (if any)
  Future<Schedule?> getActiveSchedule(String childId) async {
    final schedules = await getSchedules(childId);
    final now = DateTime.now();

    for (final schedule in schedules) {
      if (schedule.isActiveNow(now)) {
        return schedule;
      }
    }

    return null;
  }

  /// Check if any bedtime or homework schedule is blocking
  Future<bool> shouldLockDevice(String childId) async {
    final activeSchedule = await getActiveSchedule(childId);
    if (activeSchedule == null) return false;

    // Bedtime blocks everything
    if (activeSchedule.scheduleType == ScheduleType.bedtime) {
      return true;
    }

    // Homework blocks if block_all_apps is true
    if (activeSchedule.scheduleType == ScheduleType.homework &&
        activeSchedule.blockAllApps) {
      return true;
    }

    return false;
  }

  /// Check if a specific app should be blocked by current schedule
  Future<bool> shouldBlockApp(String childId, String packageName) async {
    final activeSchedule = await getActiveSchedule(childId);
    if (activeSchedule == null) return false;

    // Bedtime blocks everything
    if (activeSchedule.scheduleType == ScheduleType.bedtime) {
      return true;
    }

    // Homework mode - check if app category is blocked
    if (activeSchedule.scheduleType == ScheduleType.homework) {
      if (activeSchedule.blockAllApps) return true;

      // Check if app's category is in blocked categories
      final blockedCategories = activeSchedule.blockedCategories ?? [];
      if (blockedCategories.isEmpty) return false;

      // Simple category detection based on package name
      final category = _detectAppCategory(packageName);
      return blockedCategories.contains(category);
    }

    return false;
  }

  /// Simple app category detection
  String _detectAppCategory(String packageName) {
    final lower = packageName.toLowerCase();

    // Games
    if (lower.contains('game') || 
        lower.contains('roblox') || 
        lower.contains('minecraft') ||
        lower.contains('supercell') ||
        lower.contains('com.king')) {
      return 'games';
    }

    // Social
    if (lower.contains('instagram') ||
        lower.contains('facebook') ||
        lower.contains('snapchat') ||
        lower.contains('twitter') ||
        lower.contains('tiktok') ||
        lower.contains('musically') ||
        lower.contains('whatsapp') ||
        lower.contains('telegram')) {
      return 'social';
    }

    // Video
    if (lower.contains('youtube') ||
        lower.contains('netflix') ||
        lower.contains('disney') ||
        lower.contains('video') ||
        lower.contains('twitch')) {
      return 'video';
    }

    // Education (allow list)
    if (lower.contains('duolingo') ||
        lower.contains('classroom') ||
        lower.contains('khan') ||
        lower.contains('edu')) {
      return 'education';
    }

    return 'other';
  }

  // ==================== REAL-TIME MONITORING ====================

  /// Start monitoring schedules on child device
  void startMonitoring(
    String childId, {
    required void Function(Schedule?) onScheduleChange,
  }) {
    _currentChildId = childId;
    _onScheduleChange = onScheduleChange;

    // Check immediately
    _checkSchedules();

    // Then check every minute
    _checkTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkSchedules(),
    );
  }

  /// Stop monitoring
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _currentChildId = null;
    _onScheduleChange = null;
    _currentActiveSchedule = null;
  }

  Future<void> _checkSchedules() async {
    if (_currentChildId == null || _onScheduleChange == null) return;

    final activeSchedule = await getActiveSchedule(_currentChildId!);

    // Only notify if schedule state changed
    if (activeSchedule?.id != _currentActiveSchedule?.id) {
      _currentActiveSchedule = activeSchedule;
      _onScheduleChange!(activeSchedule);
    }
  }

  // ==================== LOCK SCREEN INFO ====================

  /// Get information for display on lock screen
  LockScreenInfo? getLockScreenInfo(Schedule schedule) {
    final now = DateTime.now();
    
    // Calculate when schedule ends
    final endMinutes = schedule.endTime.hour * 60 + schedule.endTime.minute;
    final currentMinutes = now.hour * 60 + now.minute;

    DateTime unlockTime;
    if (endMinutes > currentMinutes) {
      // Ends today
      unlockTime = DateTime(
        now.year, now.month, now.day,
        schedule.endTime.hour, schedule.endTime.minute,
      );
    } else {
      // Ends tomorrow (overnight schedule)
      final tomorrow = now.add(const Duration(days: 1));
      unlockTime = DateTime(
        tomorrow.year, tomorrow.month, tomorrow.day,
        schedule.endTime.hour, schedule.endTime.minute,
      );
    }

    return LockScreenInfo(
      scheduleName: schedule.name,
      scheduleType: schedule.scheduleType,
      unlockTime: unlockTime,
      message: _getLockMessage(schedule.scheduleType),
    );
  }

  String _getLockMessage(ScheduleType type) {
    switch (type) {
      case ScheduleType.bedtime:
        return "It's bedtime! Get some rest.";
      case ScheduleType.homework:
        return "Focus on your homework!";
      case ScheduleType.allowedHours:
        return "Screen time is paused.";
    }
  }

  // ==================== REAL-TIME SUBSCRIPTIONS ====================

  /// Subscribe to schedule changes (for child device)
  RealtimeChannel subscribeToSchedules({
    required String childId,
    required void Function(List<Schedule>) onUpdate,
  }) {
    return _supabase
        .channel('schedules_$childId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'schedules',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'child_id',
            value: childId,
          ),
          callback: (_) async {
            // Refetch all schedules when any change occurs
            final schedules = await getSchedules(childId);
            onUpdate(schedules);
          },
        )
        .subscribe();
  }
}

/// Lock screen display information
class LockScreenInfo {
  final String scheduleName;
  final ScheduleType scheduleType;
  final DateTime unlockTime;
  final String message;

  LockScreenInfo({
    required this.scheduleName,
    required this.scheduleType,
    required this.unlockTime,
    required this.message,
  });

  String get unlockTimeDisplay {
    final h = unlockTime.hour % 12 == 0 ? 12 : unlockTime.hour % 12;
    final m = unlockTime.minute.toString().padLeft(2, '0');
    final ampm = unlockTime.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  String get icon {
    return scheduleType.icon;
  }
}
