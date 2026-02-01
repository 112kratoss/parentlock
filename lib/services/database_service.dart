/// Database Service
/// 
/// Handles all Supabase database operations for:
/// - Child activity tracking
/// - App usage statistics
/// - Real-time subscriptions
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/child_activity.dart';
import '../models/category_limit.dart';
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
  
  SupabaseClient get supabase => _supabase;

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
  /// Creates entries for new apps, updates existing ones (preserving limits)
  Future<void> syncAllUsageStats({
    required String childId,
    required List<Map<String, dynamic>> fullUsageStats,
  }) async {
    if (fullUsageStats.isEmpty) return;

    // Get existing activities to preserve their limits
    Map<String, ChildActivity> existingActivityMap = {};
    try {
      final existingActivities = await getChildActivities(childId);
      for (var a in existingActivities) {
        existingActivityMap[a.appPackageName] = a;
      }
    } catch (e) {
      debugPrint('syncAllUsageStats: Error getting existing activities: $e');
    }

    // Fetch category limits first
    Map<String, int> categoryLimitsMap = {};
    try {
      final limits = await getCategoryLimits(childId);
      for (var l in limits) {
        categoryLimitsMap[l.category] = l.dailyLimitMinutes;
      }
    } catch(e) { /* ignore */ }

    // Calculate total usage per category from the CURRENT sync payload, respecting manual overrides
    Map<String, int> categoryUsage = {};
    for (final app in fullUsageStats) {
      final packageName = app['packageName'] as String;
      final nativeCategory = (app['app_category'] as String?) ?? 'other';
      final minutesUsed = (app['minutesUsed'] as int?) ?? 0;
      
      // Check for manual override
      final existingActivity = existingActivityMap[packageName];
      final manualCategory = existingActivity?.manualCategory;
      final effectiveCategory = manualCategory?.isNotEmpty == true ? manualCategory! : nativeCategory;
      
      categoryUsage[effectiveCategory] = (categoryUsage[effectiveCategory] ?? 0) + minutesUsed;
    }

    // Use a Map to deduplicate by package name (keeps the last occurrence)
    final recordsMap = <String, Map<String, dynamic>>{};
    
    // Track which apps we have updated from native stats
    final updatedPackageNames = <String>{};
    
    // 3. Prepare Batch Payload
    List<Map<String, dynamic>> batchPayload = [];
    int skippedCount = 0;

    // Helper to check for changes
    bool hasChanged(Map<String, dynamic> newRecord, ChildActivity? existing) {
      if (existing == null) return true; // New record
      
      // Check for meaningful changes
      if (newRecord['minutes_used'] != existing.minutesUsed) return true;
      if (newRecord['daily_limit_minutes'] != existing.dailyLimitMinutes) return true;
      if (newRecord['is_blocked'] != existing.isBlocked) return true;
      if (newRecord['app_display_name'] != existing.appDisplayName) return true;
      if (newRecord['category'] != existing.category) return true;
      if (newRecord['manual_category'] != existing.manualCategory) return true;
      
      return false; 
    }

    // Process active usage from native
    for (final app in fullUsageStats) {
      final packageName = app['packageName'] as String;
      final displayName = app['displayName'] as String;
      final minutesUsed = app['minutesUsed'] as int;
      final category = (app['app_category'] as String?) ?? 'other';
      
      // Skip system apps
      if (packageName.startsWith('com.android.') || 
          packageName == 'com.google.android.gms' ||
          packageName == 'com.google.android.gsf' || 
          packageName == 'com.google.android.packageinstaller') {
        continue;
      }

      final existingActivity = existingActivityMap[packageName];
      var limit = existingActivity?.dailyLimitMinutes ?? 1440;
      
      if (existingActivity != null && limit == 0 && !existingActivity.isBlocked) {
        limit = 1440;
      }
      
      final manualCategory = existingActivity?.manualCategory;
      final effectiveCategory = manualCategory?.isNotEmpty == true ? manualCategory! : category;
      
      final isAppLimitBlocked = limit == 0 || (limit > 0 && minutesUsed >= limit);
      final catLimit = categoryLimitsMap[effectiveCategory];
      final currentCategoryTotal = categoryUsage[effectiveCategory] ?? 0;
      final isCategoryBlocked = catLimit != null && currentCategoryTotal >= catLimit;
      
      final isBlocked = isAppLimitBlocked || isCategoryBlocked;

      final record = {
        'child_id': childId,
        'app_package_name': packageName,
        'app_display_name': displayName,
        'daily_limit_minutes': limit,
        'minutes_used': minutesUsed,
        'is_blocked': isBlocked,
        'last_updated': DateTime.now().toIso8601String(),
        'category': category,
        'manual_category': manualCategory,
      };

      if (hasChanged(record, existingActivity)) {
        batchPayload.add(record);
      } else {
        skippedCount++;
      }
      
      updatedPackageNames.add(packageName);
    }

    // Process implicit resets (apps not in native list but in DB)
    final existingActivitiesList = await getChildActivities(childId);
    for (var activity in existingActivitiesList) {
      if (!updatedPackageNames.contains(activity.appPackageName)) {
        final isBlocked = activity.dailyLimitMinutes == 0;
        
        final record = {
          'child_id': childId,
          'app_package_name': activity.appPackageName,
          'app_display_name': activity.appDisplayName,
          'daily_limit_minutes': activity.dailyLimitMinutes,
          'minutes_used': 0,
          'is_blocked': isBlocked, 
          'last_updated': DateTime.now().toIso8601String(),
          'category': activity.category,
          'manual_category': activity.manualCategory,
        };
        
        if (hasChanged(record, activity)) {
          batchPayload.add(record);
        } else {
          skippedCount++;
        }
      }
    }

    if (batchPayload.isEmpty) {
      debugPrint('syncAllUsageStats: No changes to sync. Skipped $skippedCount records.');
      return;
    }

    // execute RPC
    try {
      await _supabase.rpc(
        'bulk_upsert_child_activity', 
        params: {'p_records': batchPayload},
      );
      debugPrint('syncAllUsageStats: Batched sync successful. Updated ${batchPayload.length}, Skipped $skippedCount');
    } catch (e) {
      debugPrint('syncAllUsageStats: Batch sync failed: $e');
      // Fallback to individual upserts if RPC fails (e.g. function not found yet)
      // Or just log error. For production stability, a fallback is nice, but creates noise.
      // Let's assume migration is run.
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
    // Limit 0 = Manual Block
    return limit == 0 || (limit > 0 && minutesUsed >= limit);
  }

  /// Set daily limit for an app
  Future<void> setAppLimit({
    required String childId,
    required String appPackageName,
    required String appDisplayName,
    required int dailyLimitMinutes,
  }) async {
    // Calculate blocked status upfront
    // If limit is 0, we block immediately.
    // If limit > 0, we need to check current usage... but to be safe/consistent, 
    // we let usage sync handle the time-based block, unless we can check usage right now.
    // For manual block (0), we set is_blocked = true.
    
    final isBlocked = dailyLimitMinutes == 0;

    // Try to update first (for existing entries)
    final updateResult = await _supabase
        .from('child_activity')
        .update({
          'daily_limit_minutes': dailyLimitMinutes,
          'is_blocked': isBlocked, // Update blocked flag based on new limit
          'last_updated': DateTime.now().toIso8601String(),
        })
        .eq('child_id', childId)
        .eq('app_package_name', appPackageName)
        .select();

    // If no rows were updated, insert a new entry
    if ((updateResult as List).isEmpty) {
      await _supabase
          .from('child_activity')
          .insert({
            'child_id': childId,
            'app_package_name': appPackageName,
            'app_display_name': appDisplayName,
            'daily_limit_minutes': dailyLimitMinutes,
            'minutes_used': 0,
            'is_blocked': isBlocked,
            'last_updated': DateTime.now().toIso8601String(),
          });
    }
  }

  /// Reset daily usage (call at midnight)
  Future<void> resetDailyUsage(String childId) async {
    // We cannot just bulk update 'is_blocked': false because manually blocked apps (limit 0) must stay blocked.
    // We must run a conditional update or logic.
    // Postgres doesn't easily support "set is_blocked = (daily_limit_minutes == 0)" in a simple update without raw SQL or function.
    // For simplicity efficiently, we can fetch all, modify, and upsert, OR use a raw query if possible.
    // Given the constraints and typical 50 apps, fetch/update is safe.
    
    final activities = await getChildActivities(childId);
    for (var a in activities) {
      final shouldStayBlocked = a.dailyLimitMinutes == 0;
      
      await _supabase
          .from('child_activity')
          .update({
            'minutes_used': 0,
            'is_blocked': shouldStayBlocked,
            'last_updated': DateTime.now().toIso8601String(),
          })
          .eq('id', a.id);
    }
  }

  /// Get blocked apps for a child (calculates based on limits locally for reliability)
  Future<List<String>> getBlockedApps(String childId) async {
    final activities = await getChildActivities(childId);
    return activities
        .where((a) {
          // Block if explicitly blocked flag is true
          if (a.isBlocked) return true;
          // Block if limit is 0 (manual block or time out)
          if (a.dailyLimitMinutes == 0) return true;
          // Block if usage exceeds limit (and limit is set)
          if (a.dailyLimitMinutes > 0 && a.minutesUsed >= a.dailyLimitMinutes) return true;
          
          return false;
        })
        .map((a) => a.appPackageName)
        .toList();
  }

  // ==================== CATEGORY LIMITS ====================

  /// Get category limits for a child
  Future<List<CategoryLimit>> getCategoryLimits(String childId) async {
    final response = await _supabase
        .from('category_limits')
        .select()
        .eq('child_id', childId);

    return (response as List)
        .map((json) => CategoryLimit.fromJson(json))
        .toList();
  }

  /// Add or update a category limit
  Future<void> upsertCategoryLimit(CategoryLimit limit) async {
    await _supabase
        .from('category_limits')
        .upsert(limit.toJson());
  }

  /// Delete a category limit (unlimited)
  Future<void> deleteCategoryLimit(String childId, String category) async {
    await _supabase
        .from('category_limits')
        .delete()
        .eq('child_id', childId)
        .eq('category', category);
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

  // ==================== USAGE REPORTS ====================

  /// Get daily usage summary for a specific date
  Future<Map<String, dynamic>?> getDailySummary(String childId, DateTime date) async {
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      final response = await _supabase
          .from('daily_usage_summary')
          .select()
          .eq('child_id', childId)
          .eq('date', dateStr)
          .single();
      return response;
    } catch (e) {
      return null;
    }
  }

  /// Get usage summaries for date range (for trends)
  Future<List<Map<String, dynamic>>> getUsageTrend(
    String childId, {
    int days = 7,
  }) async {
    final startDate = DateTime.now().subtract(Duration(days: days));
    final startStr = startDate.toIso8601String().split('T')[0];

    final response = await _supabase
        .from('daily_usage_summary')
        .select()
        .eq('child_id', childId)
        .gte('date', startStr)
        .order('date');

    return (response as List).cast<Map<String, dynamic>>();
  }

  /// Generate and save daily summary (call at end of day)
  Future<void> generateDailySummary(String childId) async {
    // Get today's activities
    final activities = await getChildActivities(childId);
    
    if (activities.isEmpty) return;

    // Calculate totals
    final totalMinutes = activities.fold<int>(0, (sum, a) => sum + a.minutesUsed);
    
    // Build app breakdown
    final appBreakdown = <String, int>{};
    for (final activity in activities) {
      appBreakdown[activity.appPackageName] = activity.minutesUsed;
    }

    // Find most used app
    String? mostUsedApp;
    int maxMinutes = 0;
    appBreakdown.forEach((app, mins) {
      if (mins > maxMinutes) {
        maxMinutes = mins;
        mostUsedApp = app;
      }
    });

    // Count blocked attempts
    final blockedAttempts = activities.where((a) => a.isBlocked).length;

    // Upsert summary
    final today = DateTime.now().toIso8601String().split('T')[0];
    await _supabase.from('daily_usage_summary').upsert({
      'child_id': childId,
      'date': today,
      'total_minutes': totalMinutes,
      'app_breakdown': appBreakdown,
      'most_used_app': mostUsedApp,
      'blocked_attempts': blockedAttempts,
    });
  }

  /// Get aggregated stats for parent dashboard
  Future<Map<String, dynamic>> getChildStats(String childId) async {
    final activities = await getChildActivities(childId);
    
    final totalMinutes = activities.fold<int>(0, (sum, a) => sum + a.minutesUsed);
    final blockedCount = activities.where((a) => a.isBlocked).length;
    final activeCount = activities.where((a) => !a.isBlocked).length;

    // Get weekly trend
    final weeklyData = await getUsageTrend(childId, days: 7);
    final weeklyTotal = weeklyData.fold<int>(
      0, 
      (sum, d) => sum + (d['total_minutes'] as int? ?? 0),
    );

    return {
      'today_minutes': totalMinutes,
      'blocked_apps': blockedCount,
      'active_apps': activeCount,
      'weekly_total_minutes': weeklyTotal,
      'app_count': activities.length,
    };
  }
}
