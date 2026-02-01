/// Schedule Enforcer Service
/// 
/// Bridges ScheduleService and NativeService to enforce screen time rules.
/// Monitors active schedules and updates native blocked apps list in real-time.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/schedule.dart';
import 'schedule_service.dart';
import 'native_service.dart';
import 'notification_service.dart';

/// Callback for when lock state changes
typedef LockStateCallback = void Function(bool isLocked, LockScreenInfo? info);

class ScheduleEnforcer {
  final ScheduleService _scheduleService = ScheduleService();
  final NativeService _nativeService = NativeService();
  final NotificationService _notificationService = NotificationService();
  
  Timer? _checkTimer;
  RealtimeChannel? _scheduleSubscription;
  String? _currentChildId;
  Schedule? _currentActiveSchedule;
  LockStateCallback? _onLockStateChange;
  
  bool _isLocked = false;
  List<String> _currentBlockedApps = [];

  /// Start enforcing schedules for a child
  Future<void> startEnforcing({
    required String childId,
    LockStateCallback? onLockStateChange,
  }) async {
    _currentChildId = childId;
    _onLockStateChange = onLockStateChange;
    
    // Check immediately
    await _checkAndEnforce();
    
    // Check every 30 seconds
    _checkTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkAndEnforce(),
    );
    
    // Subscribe to real-time schedule changes
    _subscribeToScheduleChanges(childId);
  }

  /// Stop enforcing schedules
  void stopEnforcing() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _scheduleSubscription?.unsubscribe();
    _scheduleSubscription = null;
    _currentChildId = null;
    _currentActiveSchedule = null;
    _onLockStateChange = null;
    _isLocked = false;
    _currentBlockedApps = [];
  }

  /// Check current schedule and enforce blocking
  Future<void> _checkAndEnforce() async {
    if (_currentChildId == null) return;

    try {
      final activeSchedule = await _scheduleService.getActiveSchedule(_currentChildId!);
      
      // Check if schedule state changed
      final wasLocked = _isLocked;
      final previousScheduleId = _currentActiveSchedule?.id;
      
      _currentActiveSchedule = activeSchedule;
      
      if (activeSchedule != null) {
        await _enforceSchedule(activeSchedule);
      } else {
        await _clearEnforcement();
      }
      
      // Notify if lock state changed
      if (wasLocked != _isLocked || previousScheduleId != activeSchedule?.id) {
        _notifyLockStateChange();
        
        // Show notification if schedule just started or ended
        if (activeSchedule != null && previousScheduleId != activeSchedule.id) {
          await _notificationService.showScheduleNotification(
            scheduleName: activeSchedule.name,
            isStarting: true,
          );
        } else if (activeSchedule == null && previousScheduleId != null) {
          await _notificationService.showScheduleNotification(
            scheduleName: _currentActiveSchedule?.name ?? 'Schedule',
            isStarting: false,
          );
        }
      }
    } catch (e) {
      debugPrint('ScheduleEnforcer error: $e');
    }
  }

  /// Enforce the active schedule
  Future<void> _enforceSchedule(Schedule schedule) async {
    switch (schedule.scheduleType) {
      case ScheduleType.bedtime:
        // Bedtime blocks everything - show lock screen
        _isLocked = true;
        await _blockAllApps();
        break;
        
      case ScheduleType.homework:
        if (schedule.blockAllApps) {
          // Block all apps during homework
          _isLocked = true;
          await _blockAllApps();
        } else {
          // Block specific categories
          _isLocked = false;
          await _blockCategories(schedule.blockedCategories ?? []);
        }
        break;
        
      case ScheduleType.allowedHours:
        // During allowed hours, everything is allowed (no blocking)
        _isLocked = false;
        await _clearEnforcement();
        break;
    }
  }

  /// Block all non-essential apps
  Future<void> _blockAllApps() async {
    // Get list of all installed apps from native
    try {
      final usageStats = await _nativeService.getFullUsageStats();
      
      // Block all apps except essential ones
      final appsToBlock = usageStats
          .map((app) => app['packageName'] as String)
          .where((pkg) => !_isEssentialApp(pkg))
          .toList();
      
      if (!listEquals(appsToBlock, _currentBlockedApps)) {
        _currentBlockedApps = appsToBlock;
        await _nativeService.updateBlockedApps(appsToBlock);
      }
    } catch (e) {
      debugPrint('Failed to block all apps: $e');
    }
  }

  /// Block apps in specific categories
  Future<void> _blockCategories(List<String> categories) async {
    if (categories.isEmpty) {
      await _clearEnforcement();
      return;
    }
    
    try {
      final usageStats = await _nativeService.getFullUsageStats();
      
      // Block apps matching the categories
      final appsToBlock = usageStats
          .map((app) => app['packageName'] as String)
          .where((pkg) => categories.contains(_detectAppCategory(pkg)))
          .toList();
      
      if (!listEquals(appsToBlock, _currentBlockedApps)) {
        _currentBlockedApps = appsToBlock;
        await _nativeService.updateBlockedApps(appsToBlock);
      }
    } catch (e) {
      debugPrint('Failed to block categories: $e');
    }
  }

  /// Clear all blocking
  Future<void> _clearEnforcement() async {
    _isLocked = false;
    if (_currentBlockedApps.isNotEmpty) {
      _currentBlockedApps = [];
      try {
        await _nativeService.updateBlockedApps([]);
      } catch (e) {
        debugPrint('Failed to clear blocking: $e');
      }
    }
  }

  /// Check if an app is essential and should never be blocked
  bool _isEssentialApp(String packageName) {
    final essential = [
      'com.android.phone',
      'com.android.contacts',
      'com.android.settings',
      'com.android.emergency',
      'com.google.android.dialer',
      'com.samsung.android.dialer',
      'com.parentlock.parentlock', // Don't block ourselves!
    ];
    return essential.any((e) => packageName.contains(e));
  }

  /// Simple app category detection
  String _detectAppCategory(String packageName) {
    final lower = packageName.toLowerCase();

    // Games
    if (lower.contains('game') || 
        lower.contains('roblox') || 
        lower.contains('minecraft') ||
        lower.contains('supercell') ||
        lower.contains('com.king') ||
        lower.contains('com.ea.') ||
        lower.contains('gameloft')) {
      return 'games';
    }

    // Social
    if (lower.contains('instagram') ||
        lower.contains('facebook') ||
        lower.contains('snapchat') ||
        lower.contains('twitter') ||
        lower.contains('tiktok') ||
        lower.contains('whatsapp') ||
        lower.contains('telegram') ||
        lower.contains('discord')) {
      return 'social';
    }

    // Video
    if (lower.contains('youtube') ||
        lower.contains('netflix') ||
        lower.contains('disney') ||
        lower.contains('twitch') ||
        lower.contains('hulu') ||
        lower.contains('prime video')) {
      return 'video';
    }

    return 'other';
  }

  /// Notify listener about lock state change
  void _notifyLockStateChange() {
    if (_onLockStateChange == null) return;
    
    LockScreenInfo? info;
    if (_currentActiveSchedule != null) {
      info = _scheduleService.getLockScreenInfo(_currentActiveSchedule!);
    }
    
    _onLockStateChange!(_isLocked, info);
  }

  /// Subscribe to real-time schedule changes
  void _subscribeToScheduleChanges(String childId) {
    _scheduleSubscription = _scheduleService.subscribeToSchedules(
      childId: childId,
      onUpdate: (_) {
        // Re-check enforcement when schedules change
        _checkAndEnforce();
      },
    );
  }

  /// Force check schedules now (call after schedule update)
  Future<void> refreshEnforcement() async {
    await _checkAndEnforce();
  }

  /// Get current lock state
  bool get isLocked => _isLocked;

  /// Get current active schedule
  Schedule? get activeSchedule => _currentActiveSchedule;

  /// Get current blocked apps list
  List<String> get blockedApps => List.unmodifiable(_currentBlockedApps);
}
