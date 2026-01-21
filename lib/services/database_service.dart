/// Database Service
/// 
/// Handles all Supabase database operations for:
/// - Child activity tracking
/// - App usage statistics
/// - Real-time subscriptions
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/child_activity.dart';
import '../models/user_profile.dart';

/// Extension to capitalize first letter of string
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}

class DatabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ==================== PROFILES ====================

  /// Get all children linked to a parent
  Future<List<UserProfile>> getLinkedChildren(String parentId) async {
    final response = await _supabase
        .from('profiles')
        .select()
        .eq('role', 'child')
        .eq('linked_to', parentId);

    return (response as List)
        .map((json) => UserProfile.fromJson(json))
        .toList();
  }

  /// Get a profile by ID
  Future<UserProfile?> getProfile(String id) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', id)
          .single();

      return UserProfile.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  // ==================== CHILD ACTIVITY ====================

  /// Get all activity records for a child
  Future<List<ChildActivity>> getChildActivities(String childId) async {
    final response = await _supabase
        .from('child_activity')
        .select()
        .eq('child_id', childId)
        .order('app_display_name');

    return (response as List)
        .map((json) => ChildActivity.fromJson(json))
        .toList();
  }

  /// Get all activities for all children of a parent
  Future<List<ChildActivity>> getParentChildrenActivities(String parentId) async {
    // First get all children
    final children = await getLinkedChildren(parentId);
    
    if (children.isEmpty) return [];

    final childIds = children.map((c) => c.id).toList();
    
    final response = await _supabase
        .from('child_activity')
        .select()
        .inFilter('child_id', childIds)
        .order('app_display_name');

    return (response as List)
        .map((json) => ChildActivity.fromJson(json))
        .toList();
  }

  /// Add or update app activity for a child
  Future<void> upsertActivity(ChildActivity activity) async {
    await _supabase
        .from('child_activity')
        .upsert(activity.toJson());
  }

  /// Sync all usage stats from device to database
  /// Creates entries for new apps, updates existing ones
  Future<void> syncAllUsageStats({
    required String childId,
    required List<Map<String, dynamic>> fullUsageStats,
  }) async {
    if (fullUsageStats.isEmpty) return;

    // Get existing activities for this child
    final existingActivities = await getChildActivities(childId);
    final existingPackages = {for (var a in existingActivities) a.appPackageName: a};

    for (final app in fullUsageStats) {
      final packageName = app['packageName'] as String;
      final displayName = app['displayName'] as String;
      final minutesUsed = app['minutesUsed'] as int;
      
      // Skip system apps and very short usage
      if (packageName.startsWith('com.android.') || 
          packageName.startsWith('com.google.android.') ||
          minutesUsed < 1) {
        continue;
      }

      final existing = existingPackages[packageName];
      
      if (existing != null) {
        // Update existing entry
        await _supabase
            .from('child_activity')
            .update({
              'minutes_used': minutesUsed,
              'app_display_name': displayName, // Update with actual app name
              'is_blocked': minutesUsed >= existing.dailyLimitMinutes && existing.dailyLimitMinutes > 0,
              'last_updated': DateTime.now().toIso8601String(),
            })
            .eq('child_id', childId)
            .eq('app_package_name', packageName);
      } else {
        // Insert new entry (no limit set, just tracking)
        await _supabase
            .from('child_activity')
            .upsert({
              'child_id': childId,
              'app_package_name': packageName,
              'app_display_name': displayName,
              'daily_limit_minutes': 0, // 0 means no limit
              'minutes_used': minutesUsed,
              'is_blocked': false,
              'last_updated': DateTime.now().toIso8601String(),
            });
      }
    }
  }

  /// Format package name to display name
  String _formatAppName(String packageName) {
    // Extract app name from package (e.g., com.youtube.android -> YouTube)
    final parts = packageName.split('.');
    if (parts.length > 1) {
      final name = parts[parts.length - 1];
      if (name == 'android' && parts.length > 2) {
        return parts[parts.length - 2].capitalize();
      }
      return name.capitalize();
    }
    return packageName;
  }

  /// Update minutes used for an app
  Future<void> updateMinutesUsed({
    required String childId,
    required String appPackageName,
    required int minutesUsed,
  }) async {
    final isBlocked = await _checkIfShouldBlock(childId, appPackageName, minutesUsed);
    
    await _supabase
        .from('child_activity')
        .update({
          'minutes_used': minutesUsed,
          'is_blocked': isBlocked,
          'last_updated': DateTime.now().toIso8601String(),
        })
        .eq('child_id', childId)
        .eq('app_package_name', appPackageName);
  }

  /// Check if app should be blocked based on limit
  Future<bool> _checkIfShouldBlock(
    String childId, 
    String appPackageName, 
    int minutesUsed,
  ) async {
    final response = await _supabase
        .from('child_activity')
        .select('daily_limit_minutes')
        .eq('child_id', childId)
        .eq('app_package_name', appPackageName)
        .single();

    final limit = response['daily_limit_minutes'] as int;
    return minutesUsed >= limit;
  }

  /// Set daily limit for an app
  Future<void> setAppLimit({
    required String childId,
    required String appPackageName,
    required String appDisplayName,
    required int dailyLimitMinutes,
  }) async {
    await _supabase
        .from('child_activity')
        .upsert({
          'child_id': childId,
          'app_package_name': appPackageName,
          'app_display_name': appDisplayName,
          'daily_limit_minutes': dailyLimitMinutes,
          'minutes_used': 0,
          'is_blocked': false,
          'last_updated': DateTime.now().toIso8601String(),
        });
  }

  /// Reset daily usage (call at midnight)
  Future<void> resetDailyUsage(String childId) async {
    await _supabase
        .from('child_activity')
        .update({
          'minutes_used': 0,
          'is_blocked': false,
          'last_updated': DateTime.now().toIso8601String(),
        })
        .eq('child_id', childId);
  }

  /// Get blocked apps for a child
  Future<List<String>> getBlockedApps(String childId) async {
    final response = await _supabase
        .from('child_activity')
        .select('app_package_name')
        .eq('child_id', childId)
        .eq('is_blocked', true);

    return (response as List)
        .map((json) => json['app_package_name'] as String)
        .toList();
  }

  // ==================== REAL-TIME SUBSCRIPTIONS ====================

  /// Subscribe to child activity changes (for parent dashboard)
  RealtimeChannel subscribeToChildActivities({
    required String childId,
    required void Function(ChildActivity) onUpdate,
  }) {
    return _supabase
        .channel('child_activity_$childId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'child_activity',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'child_id',
            value: childId,
          ),
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              onUpdate(ChildActivity.fromJson(payload.newRecord));
            }
          },
        )
        .subscribe();
  }

  /// Subscribe to blocked status changes (for child device)
  RealtimeChannel subscribeToBlockedApps({
    required String childId,
    required void Function(List<String>) onBlockedAppsChanged,
  }) {
    return _supabase
        .channel('blocked_apps_$childId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'child_activity',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'child_id',
            value: childId,
          ),
          callback: (payload) async {
            // Fetch all blocked apps when any update occurs
            final blockedApps = await getBlockedApps(childId);
            onBlockedAppsChanged(blockedApps);
          },
        )
        .subscribe();
  }

  /// Unsubscribe from a channel
  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _supabase.removeChannel(channel);
  }
}
