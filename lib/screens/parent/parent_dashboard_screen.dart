/// Parent Dashboard Screen
/// 
/// Main dashboard for parents showing children's statistics
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/child_activity.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/notification_service.dart';
import '../../models/geofence.dart';
import 'child_apps_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _authService = AuthService();
  final _databaseService = DatabaseService();
  final _locationService = LocationService();
  final _notificationService = NotificationService();
  
  List<UserProfile> _children = [];
  List<ChildActivity> _activities = [];
  bool _isLoading = true;
  String? _linkingCode;
  
  // Real-time subscriptions
  RealtimeChannel? _sosSubscription;
  final Map<String, RealtimeChannel> _geofenceSubscriptions = {};
  final Map<String, RealtimeChannel> _activitySubscriptions = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _generateLinkingCode();
  }

  @override
  void dispose() {
    // Clean up subscriptions
    _sosSubscription?.unsubscribe();
    for (final sub in _geofenceSubscriptions.values) {
      sub.unsubscribe();
    }
    for (final sub in _activitySubscriptions.values) {
      sub.unsubscribe();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final userId = _authService.currentUser?.id;
      if (userId != null) {
        final children = await _databaseService.getLinkedChildren(userId);
        final activities = await _databaseService.getParentChildrenActivities(userId);
        
        setState(() {
          _children = children;
          _activities = activities;
        });
        
        // Set up real-time subscriptions for SOS and geofence
        _setupSosSubscription(userId);
        // Set up real-time subscriptions for SOS and geofence
        _setupSosSubscription(userId);
        _setupGeofenceSubscriptions(children);
        _setupActivitySubscriptions(children);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Subscribe to SOS alerts from children
  void _setupSosSubscription(String parentId) {
    _sosSubscription?.unsubscribe();
    _sosSubscription = _locationService.subscribeToSosAlerts(
      parentId: parentId,
      onAlert: (alert) async {
        // Find child name
        final child = _children.where((c) => c.id == alert.childId).firstOrNull;
        final childName = child != null ? 'Child' : 'Your child';
        
        // Show high-priority notification
        await _notificationService.showSosAlert(
          childName: childName,
          message: alert.message,
          latitude: alert.latitude,
          longitude: alert.longitude,
        );
        
        // Show dialog if app is open
        if (mounted) {
          _showSosAlertDialog(childName, alert);
        }
      },
    );
  }

  /// Subscribe to geofence events for all children
  void _setupGeofenceSubscriptions(List<UserProfile> children) {
    // Clear existing subscriptions
    for (final sub in _geofenceSubscriptions.values) {
      sub.unsubscribe();
    }
    _geofenceSubscriptions.clear();
    
    // Subscribe to each child's geofence events
    for (final child in children) {
      _geofenceSubscriptions[child.id] = Supabase.instance.client
          .channel('geofence_events_${child.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'geofence_events',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'child_id',
              value: child.id,
            ),
            callback: (payload) async {
              if (payload.newRecord.isNotEmpty) {
                final eventType = payload.newRecord['event_type'] as String?;
                final geofenceId = payload.newRecord['geofence_id'] as String?;
                
                // Fetch geofence name
                String zoneName = 'Safe Zone';
                if (geofenceId != null) {
                  try {
                    final geoResponse = await Supabase.instance.client
                        .from('geofences')
                        .select('name')
                        .eq('id', geofenceId)
                        .maybeSingle();
                    zoneName = geoResponse?['name'] ?? 'Safe Zone';
                  } catch (_) {}
                }
                
                // Show notification
                await _notificationService.showGeofenceAlert(
                  childName: 'Child',
                  zoneName: zoneName,
                  isEntering: eventType == 'enter',
                );
              }
            },
          )
          .subscribe();
    }
  }

  /// Subscribe to activity changes for all children
  void _setupActivitySubscriptions(List<UserProfile> children) {
    // Clear existing subscriptions
    for (final sub in _activitySubscriptions.values) {
      sub.unsubscribe();
    }
    _activitySubscriptions.clear();
    
    for (final child in children) {
      _activitySubscriptions[child.id] = _databaseService.subscribeToChildActivities(
        childId: child.id,
        onUpdate: (updatedActivity) {
          if (mounted) {
            setState(() {
              final index = _activities.indexWhere(
                (a) => a.id == updatedActivity.id
              );
              if (index != -1) {
                _activities[index] = updatedActivity;
              } else {
                _activities.add(updatedActivity);
              }
            });
          }
        },
      );
    }
  }

  /// Show SOS alert dialog when app is in foreground
  void _showSosAlertDialog(String childName, SosAlert alert) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: Row(
          children: [
            const Text('🆘', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Text('SOS from $childName!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(alert.message ?? '$childName needs help!'),
            if (alert.latitude != null && alert.longitude != null) ...[
              const SizedBox(height: 12),
              Text(
                '📍 Location: ${alert.latitude?.toStringAsFixed(4)}, ${alert.longitude?.toStringAsFixed(4)}',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to location screen
              if (alert.childId.isNotEmpty) {
                context.push('/parent/location/${alert.childId}');
              }
            },
            child: const Text('View Location'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Acknowledge the alert
              _locationService.acknowledgeSosAlert(alert.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateLinkingCode() async {
    try {
      final code = await _authService.generateLinkingCode();
      setState(() => _linkingCode = code);
    } catch (e) {
      // Ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Linking Code Card
                    _LinkingCodeCard(code: _linkingCode ?? 'Loading...'),
                    const SizedBox(height: 24),

                    // Children Section
                    Text(
                      'Linked Children',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    if (_children.isEmpty)
                      _EmptyChildrenCard()
                    else
                      ..._children.map((child) => _ChildCard(
                        child: child,
                        activities: _activities.where(
                          (a) => a.childId == child.id
                        ).toList(),
                      )),

                    const SizedBox(height: 24),

                    // Quick Stats
                    Text(
                      'Today\'s Overview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _StatsGrid(
                      activities: _activities,
                      children: _children,
                    ),
                  ],
                ),
              ),
            ),
      // floatingActionButton removed
    );
  }
}

class _LinkingCodeCard extends StatelessWidget {
  final String code;

  const _LinkingCodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.link,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Your Linking Code',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this code with your child to link their device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChildrenCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No children linked yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Share your linking code above with your child to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final UserProfile child;
  final List<ChildActivity> activities;

  const _ChildCard({
    required this.child,
    required this.activities,
  });

  int get totalMinutesUsed => 
      activities.fold(0, (sum, a) => sum + a.minutesUsed);
  
  int get blockedAppsCount => 
      activities.where((a) => a.isEffectivelyBlocked).length;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: const Icon(Icons.child_care, color: Colors.green),
        ),
        title: Text('Child Device'),
        subtitle: Text('${activities.length} apps tracked'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        icon: Icons.timer,
                        label: 'Time Today',
                        value: '${totalMinutesUsed}m',
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.block,
                        label: 'Blocked',
                        value: '$blockedAppsCount apps',
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (activities.isNotEmpty)
                  ...activities.take(3).map((a) => ListTile(
                    dense: true,
                    leading: Icon(
                      a.isEffectivelyBlocked ? Icons.block : Icons.check_circle,
                      color: a.isEffectivelyBlocked ? Colors.red : Colors.green,
                    ),
                    title: Text(a.appDisplayName),
                    trailing: Text(
                      '${a.minutesUsed}/${a.dailyLimitMinutes}m',
                      style: TextStyle(
                        color: a.isEffectivelyBlocked ? Colors.red : Colors.grey,
                      ),
                    ),
                  )),
                
                // Action Buttons
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.location_on,
                      label: 'Location',
                      color: Colors.blue,
                      onTap: () => context.push('/parent/location/${child.id}'),
                    ),
                    _ActionButton(
                      icon: Icons.schedule,
                      label: 'Schedule',
                      color: Colors.orange,
                      onTap: () => context.push('/parent/schedule/${child.id}'),
                    ),
                    _ActionButton(
                      icon: Icons.bar_chart,
                      label: 'Reports',
                      color: Colors.purple,
                      onTap: () => context.push('/parent/reports/${child.id}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final List<ChildActivity> activities;
  final List<UserProfile> _children; // We need children for the next screen

  const _StatsGrid({
    required this.activities,
    required List<UserProfile> children,
  }) : _children = children;

  int get totalMinutes => activities.fold(0, (sum, a) => sum + a.minutesUsed);
  int get blockedCount => activities.where((a) => a.isEffectivelyBlocked).length;
  int get activeCount => activities.where((a) => !a.isEffectivelyBlocked).length;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickStatCard(
            icon: Icons.access_time,
            label: 'Total Time',
            value: '${(totalMinutes / 60).toStringAsFixed(1)}h',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChildAppsScreen(
                    children: _children,
                    activities: activities,
                  ),
                ),
              );
              // Explicitly refresh data when returning
              // This handles cases where real-time might be delayed
              // or connection dropped during the child screen session.
              if (context.mounted) {
                 // Trigger parent refresh
                 final parentState = context.findAncestorStateOfType<_ParentDashboardScreenState>();
                 parentState?._loadData();
              }
            },
            child: _QuickStatCard(
              icon: Icons.apps,
              label: 'Manage Apps',
              value: '${activities.length} Apps',
              color: Colors.blue,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChildAppsScreen(
                    children: _children,
                    activities: activities,
                    showBlockedOnly: true,
                  ),
                ),
              );
              // Explicitly refresh data when returning
              if (context.mounted) {
                 final parentState = context.findAncestorStateOfType<_ParentDashboardScreenState>();
                 parentState?._loadData();
              }
            },
            child: _QuickStatCard(
              icon: Icons.block,
              label: 'Blocked',
              value: '$blockedCount',
              color: Colors.red,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _QuickStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
