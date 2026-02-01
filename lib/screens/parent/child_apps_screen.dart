/// Child Apps Screen
/// 
/// Lists all installed/monitored apps for a child and allows management.
library;

import 'package:flutter/material.dart';
import '../../models/child_activity.dart';
import '../../models/user_profile.dart';
import '../../services/database_service.dart';
import 'category_limits_screen.dart';

class ChildAppsScreen extends StatefulWidget {
  final List<UserProfile> children;
  final List<ChildActivity> activities;
  final bool showBlockedOnly;

  const ChildAppsScreen({
    super.key,
    required this.children,
    required this.activities,
    this.showBlockedOnly = false,
  });

  @override
  State<ChildAppsScreen> createState() => _ChildAppsScreenState();
}

class _ChildAppsScreenState extends State<ChildAppsScreen> {
  final _databaseService = DatabaseService();
  late List<ChildActivity> _activities;
  bool _isLoading = false;
  bool _showBlockedOnly = false;

  @override
  void initState() {
    super.initState();
    _activities = List.from(widget.activities);
    _showBlockedOnly = widget.showBlockedOnly;
    // Fetch fresh data immediately to ensure we aren't showing stale state
    _refreshActivities();
  }

  Future<void> _refreshActivities() async {
    try {
      if (widget.children.isEmpty) return;
      
      // Fetch for all linked children
      // We can use the existing parent fetch method from database service
      // assuming we have the parent ID (current user)
      final active = await _databaseService.getParentChildrenActivities(
        _databaseService.supabase.auth.currentUser!.id
      );
      
      if (mounted) {
        setState(() {
          _activities = active;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing activities: $e');
    }
  }

  Future<void> _toggleBlock(ChildActivity activity) async {
    setState(() => _isLoading = true);
    try {
      final isCurrentlyBlocked = activity.isEffectivelyBlocked;
      final newLimit = isCurrentlyBlocked ? 1440 : 0; // Unblock to unlimited, or Block (0)
      
      // Update local state first
      setState(() {
        final index = _activities.indexWhere((a) => a.id == activity.id);
        if (index != -1) {
          _activities[index] = activity.copyWith(
            dailyLimitMinutes: newLimit,
            isBlocked: newLimit == 0,
          );
        }
      });
      
      await _databaseService.setAppLimit(
        childId: activity.childId,
        appPackageName: activity.appPackageName,
        appDisplayName: activity.appDisplayName,
        dailyLimitMinutes: newLimit,
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating app: $e'), backgroundColor: Colors.red),
        );
      }
      // Revert on error - logic omitted for brevity as typically we'd reload
      _refreshActivities();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showLimitDialog(ChildActivity activity) async {
    int currentLimit = activity.dailyLimitMinutes;
    // If blocked (0), show as 30 min default when opening dialog
    if (currentLimit == 0) currentLimit = 30;
    // If unlimited (1440), show as max or handle visually? Let's cap slider at 4 hours (240 min)
    if (currentLimit > 240) currentLimit = 240;

    int selectedLimit = currentLimit;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: const Icon(Icons.timer, color: Colors.blue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Limit: ${activity.appDisplayName}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            selectedLimit == 240 ? 'Unlimited (4h+)' : '$selectedLimit minutes per day',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('5m'),
                    Expanded(
                      child: Slider(
                        value: selectedLimit.toDouble(),
                        min: 5,
                        max: 240, // 4 hours
                        divisions: 47,
                        label: '$selectedLimit m',
                        onChanged: (value) {
                          setSheetState(() => selectedLimit = value.round());
                        },
                      ),
                    ),
                    const Text('4h'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                     TextButton(
                      onPressed: () {
                         // Set to "Unlimited" (1440 mins)
                         _updateAppLimit(activity, 1440);
                         Navigator.pop(context);
                      },
                      child: const Text('Remove Limit'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        _updateAppLimit(activity, selectedLimit);
                        Navigator.pop(context);
                      },
                      child: const Text('Set Limit'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateAppLimit(ChildActivity activity, int limit) async {
    setState(() => _isLoading = true);
    try {
      // Optimistic update
       setState(() {
        final index = _activities.indexWhere((a) => a.id == activity.id);
        if (index != -1) {
          // If limit is 0, it's blocked. If > 0, it depends on usage (handled by DB/Native)
          // But here we are just setting the limit.
          _activities[index] = activity.copyWith(dailyLimitMinutes: limit);
        }
      });

      await _databaseService.setAppLimit(
        childId: activity.childId,
        appPackageName: activity.appPackageName,
        appDisplayName: activity.appDisplayName,
        dailyLimitMinutes: limit,
      );
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error setting limit: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showCategoryEditDialog(ChildActivity activity) async {
    final categories = ['social', 'game', 'video', 'audio', 'productivity', 'image', 'maps', 'news', 'other'];
    String? selectedCategory = activity.manualCategory ?? activity.category;
    if (!categories.contains(selectedCategory)) selectedCategory = 'other';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Edit Category for ${activity.appDisplayName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: categories.map((cat) {
                  return RadioListTile<String>(
                    title: Text(cat.capitalize()),
                    value: cat,
                    groupValue: selectedCategory,
                    onChanged: (value) {
                      setDialogState(() => selectedCategory = value);
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
               TextButton(
                onPressed: () {
                  // Reset to auto-detect
                  _updateAppCategory(activity, null);
                  Navigator.pop(context);
                },
                child: const Text('Reset to Auto'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                   _updateAppCategory(activity, selectedCategory);
                   Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateAppCategory(ChildActivity activity, String? manualCategory) async {
    setState(() => _isLoading = true);
    try {
      // Optimistic update
      setState(() {
        final index = _activities.indexWhere((a) => a.id == activity.id);
        if (index != -1) {
          _activities[index] = activity.copyWith(manualCategory: manualCategory);
        }
      });
      
      // Update DB
      await _databaseService.supabase
          .from('child_activity')
          .update({
            'manual_category': manualCategory,
            'last_updated': DateTime.now().toIso8601String(),
          })
          .eq('child_id', activity.childId)
          .eq('app_package_name', activity.appPackageName);

    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating category: $e'), backgroundColor: Colors.red),
        );
      }
      _refreshActivities();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showBlockedOnly ? 'Blocked Apps' : 'Manage Apps'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showBlockedOnly ? Icons.filter_list_off : Icons.filter_list),
            onPressed: () => setState(() => _showBlockedOnly = !_showBlockedOnly),
            tooltip: _showBlockedOnly ? 'Show All Apps' : 'Show Blocked Only',
          ),
        ],
      ),
      body: widget.children.isEmpty
          ? const Center(child: Text('No children linked'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.children.length,
              itemBuilder: (context, index) {
                final child = widget.children[index];
                final childApps = _activities
                    .where((a) => a.childId == child.id)
                    .where((a) => !_showBlockedOnly || a.isEffectivelyBlocked)
                    .toList();
                
                // Sort: Blocked first, then by name
                childApps.sort((a, b) {
                  if (a.isEffectivelyBlocked != b.isEffectivelyBlocked) {
                    return a.isEffectivelyBlocked ? -1 : 1;
                  }
                  return a.appDisplayName.compareTo(b.appDisplayName);
                });

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Child Header
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.blue.shade100,
                                child: const Icon(Icons.person, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Child Device (${child.id.substring(0, 4)}...)',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.category, size: 16),
                            label: const Text('Categories'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CategoryLimitsScreen(
                                    childId: child.id,
                                    childName: 'Child Device', // Ideally pass real name
                                  ),
                                ),
                              ).then((_) => _refreshActivities());
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    if (childApps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No usage data yet.', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ...childApps.map((app) {
                        final categoryDisplay = app.effectiveCategory.capitalize();
                        final isOverridden = app.manualCategory != null;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: app.isEffectivelyBlocked 
                                  ? Colors.red.withOpacity(0.1) 
                                  : Colors.transparent, 
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    // App Icon
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: app.isEffectivelyBlocked
                                            ? Colors.red.shade50
                                            : Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        app.isEffectivelyBlocked
                                            ? Icons.block_flipped
                                            : Icons.android_rounded,
                                        color: app.isEffectivelyBlocked
                                            ? Colors.red
                                            : Colors.green,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    
                                    // App Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            app.appDisplayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            app.appPackageName,
                                            style: TextStyle(
                                              color: Colors.grey[500],
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    // Block Toggle
                                    IconButton.filledTonal(
                                      onPressed: _isLoading ? null : () => _toggleBlock(app),
                                      icon: Icon(
                                        app.isEffectivelyBlocked ? Icons.lock : Icons.lock_open_rounded,
                                        color: app.isEffectivelyBlocked ? Colors.red : Colors.green,
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor: app.isEffectivelyBlocked 
                                            ? Colors.red.shade50 
                                            : Colors.green.shade50,
                                      ),
                                      tooltip: app.isEffectivelyBlocked ? 'Unblock' : 'Block',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Divider(height: 1),
                                const SizedBox(height: 12),
                                
                                // Action Row: Category & Usage/Limit
                                Row(
                                  children: [
                                    // Category Chip
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: InkWell(
                                          onTap: () => _showCategoryEditDialog(app),
                                          borderRadius: BorderRadius.circular(20),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12, 
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(20),
                                              border: isOverridden
                                                  ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1)
                                                  : null,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.category_outlined,
                                                  size: 14,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    categoryDisplay,
                                                    style: TextStyle(
                                                      color: Theme.of(context).colorScheme.primary,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isOverridden) ...[
                                                  const SizedBox(width: 4),
                                                  Icon(
                                                    Icons.edit,
                                                    size: 10,
                                                    color: Theme.of(context).colorScheme.primary,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    
                                    // Usage & Limit
                                    Row(
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${app.minutesUsed}m used',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (app.dailyLimitMinutes > 0 && app.dailyLimitMinutes < 1440)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(
                                                  'Limit: ${app.dailyLimitMinutes}m',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () => _showLimitDialog(app),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              Icons.timer_outlined,
                                              size: 18,
                                              color: Colors.grey[800],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const Divider(height: 32),
                  ],
                );
              },
            ),
    );
  }
}

