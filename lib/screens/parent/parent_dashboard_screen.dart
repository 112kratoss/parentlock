/// Parent Dashboard Screen
///
/// Main dashboard for parents showing children's statistics
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/child_activity.dart';
import '../../models/device_health.dart';
import '../../models/parent_link_code.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
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
  Map<String, DeviceHealthStatus> _deviceHealthByChildId = {};
  Map<String, List<DeviceHealthEvent>> _deviceHealthEventsByChildId = {};
  bool _isLoading = true;
  ParentLinkCode? _linkingCode;

  // Real-time subscriptions
  RealtimeChannel? _sosSubscription;
  final Map<String, RealtimeChannel> _geofenceSubscriptions = {};
  final Map<String, RealtimeChannel> _activitySubscriptions = {};
  final Map<String, RealtimeChannel> _healthSubscriptions = {};
  final Map<String, RealtimeChannel> _healthEventSubscriptions = {};

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
    for (final sub in _healthSubscriptions.values) {
      sub.unsubscribe();
    }
    for (final sub in _healthEventSubscriptions.values) {
      sub.unsubscribe();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final userId = _authService.currentUser?.id;
      if (userId != null) {
        try {
          await _databaseService.reconcileDeviceHealthStates();
        } catch (_) {}

        final children = await _databaseService.getLinkedChildren(userId);
        final activities = await _databaseService.getParentChildrenActivities(
          userId,
        );
        final childIds = children.map((child) => child.id).toList();
        final healthByChild = await _databaseService.getDeviceHealthForChildren(
          childIds,
        );
        final healthEventsByChild = await _databaseService
            .getDeviceHealthEventsForChildren(childIds);

        setState(() {
          _children = children;
          _activities = activities;
          _deviceHealthByChildId = healthByChild;
          _deviceHealthEventsByChildId = healthEventsByChild;
        });

        // Set up real-time subscriptions for SOS and geofence
        _setupSosSubscription(userId);
        _setupGeofenceSubscriptions(children);
        _setupActivitySubscriptions(children);
        _setupHealthSubscriptions(children);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
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
        final childName = _childDisplayName(alert.childId);

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
      _activitySubscriptions[child.id] = _databaseService
          .subscribeToChildActivities(
            childId: child.id,
            onUpdate: (updatedActivity) {
              if (mounted) {
                setState(() {
                  final index = _activities.indexWhere(
                    (a) => a.id == updatedActivity.id,
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

  void _setupHealthSubscriptions(List<UserProfile> children) {
    for (final sub in _healthSubscriptions.values) {
      sub.unsubscribe();
    }
    for (final sub in _healthEventSubscriptions.values) {
      sub.unsubscribe();
    }
    _healthSubscriptions.clear();
    _healthEventSubscriptions.clear();

    for (final child in children) {
      _healthSubscriptions[child.id] = _databaseService.subscribeToDeviceHealth(
        childId: child.id,
        onUpdate: (healthStatus) {
          if (!mounted) {
            return;
          }

          setState(() {
            _deviceHealthByChildId[child.id] = healthStatus;
          });
        },
      );

      _healthEventSubscriptions[child.id] = _databaseService
          .subscribeToDeviceHealthEvents(
            childId: child.id,
            onEvent: (event) async {
              final childName = _childDisplayName(child.id);

              if (mounted) {
                setState(() {
                  final existingEvents =
                      _deviceHealthEventsByChildId[child.id] ?? [];
                  _deviceHealthEventsByChildId[child.id] = [
                    event,
                    ...existingEvents,
                  ].take(3).toList();
                });
              }

              if (!event.isReminder &&
                  (event.tamperState == DeviceTamperState.tampered ||
                      event.tamperState == DeviceTamperState.offline)) {
                await _notificationService.showDeviceHealthAlert(
                  childName: childName,
                  stateLabel: event.tamperState.name,
                  reason: event.tamperReason,
                );
              }
            },
          );
    }
  }

  String _childDisplayName(String childId) {
    final index = _children.indexWhere((child) => child.id == childId);
    if (index == -1) {
      return 'Child device';
    }
    return 'Child ${index + 1}';
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
            onPressed: () async {
              await _loadData();
              await _generateLinkingCode();
            },
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
                    _LinkingCodeCard(linkCode: _linkingCode),
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
                      ..._children.map(
                        (child) => _ChildCard(
                          child: child,
                          activities: _activities
                              .where((a) => a.childId == child.id)
                              .toList(),
                          deviceHealth: _deviceHealthByChildId[child.id],
                          healthEvents:
                              _deviceHealthEventsByChildId[child.id] ??
                              const [],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Quick Stats
                    Text(
                      'Today\'s Overview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _StatsGrid(activities: _activities, children: _children),
                  ],
                ),
              ),
            ),
      // floatingActionButton removed
    );
  }
}

class _LinkingCodeCard extends StatelessWidget {
  final ParentLinkCode? linkCode;

  const _LinkingCodeCard({required this.linkCode});

  String _formatExpiry(DateTime expiresAt) {
    final local = expiresAt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final code = linkCode?.code ?? 'Loading...';
    final expiryText = linkCode == null
        ? 'Generating a temporary link code...'
        : linkCode!.isExpired
        ? 'This code has expired. Refresh to generate a new one.'
        : 'Valid until ${_formatExpiry(linkCode!.expiresAt)}.';

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, color: Theme.of(context).colorScheme.primary),
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
              'Share this temporary code with your child to link their device. $expiryText',
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
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
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
  final DeviceHealthStatus? deviceHealth;
  final List<DeviceHealthEvent> healthEvents;

  const _ChildCard({
    required this.child,
    required this.activities,
    required this.deviceHealth,
    required this.healthEvents,
  });

  int get totalMinutesUsed =>
      activities.fold(0, (sum, a) => sum + a.minutesUsed);

  int get blockedAppsCount =>
      activities.where((a) => a.isEffectivelyBlocked).length;

  Color _healthColor(BuildContext context) {
    final effectiveState = deviceHealth?.effectiveStateAt(DateTime.now());
    switch (effectiveState) {
      case DeviceTamperState.healthy:
        return deviceHealth?.enrollmentMode == DeviceEnrollmentMode.managedDevice
            ? Colors.green
            : Colors.blue;
      case DeviceTamperState.degraded:
        return Colors.orange;
      case DeviceTamperState.tampered:
        return Colors.red;
      case DeviceTamperState.offline:
        return Colors.grey.shade700;
      case null:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _healthSubtitle() {
    final health = deviceHealth;
    if (health == null) {
      return '${activities.length} apps tracked';
    }

    final label = health.stateLabelAt(DateTime.now());
    return '${activities.length} apps tracked • $label';
  }

  String _heartbeatText() {
    final health = deviceHealth;
    if (health == null) {
      return 'No heartbeat received yet';
    }

    final secondsAgo = DateTime.now().toUtc().difference(
      health.lastHeartbeatAt.toUtc(),
    );
    if (secondsAgo.inMinutes >= 1) {
      return 'Last heartbeat ${secondsAgo.inMinutes}m ago';
    }
    return 'Last heartbeat ${secondsAgo.inSeconds}s ago';
  }

  @override
  Widget build(BuildContext context) {
    final healthColor = _healthColor(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: healthColor.withValues(alpha: 0.14),
          child: Icon(Icons.child_care, color: healthColor),
        ),
        title: Text('Child Device'),
        subtitle: Text(_healthSubtitle()),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (deviceHealth != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: healthColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.health_and_safety, color: healthColor),
                            const SizedBox(width: 8),
                            Text(
                              deviceHealth!.stateLabelAt(DateTime.now()),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: healthColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _heartbeatText(),
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        if (deviceHealth!.tamperReason != null &&
                            deviceHealth!.tamperReason!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            deviceHealth!.tamperReason!,
                            style: TextStyle(color: Colors.grey[800]),
                          ),
                        ],
                      ],
                    ),
                  ),
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
                  ...activities
                      .take(3)
                      .map(
                        (a) => ListTile(
                          dense: true,
                          leading: Icon(
                            a.isEffectivelyBlocked
                                ? Icons.block
                                : Icons.check_circle,
                            color: a.isEffectivelyBlocked
                                ? Colors.red
                                : Colors.green,
                          ),
                          title: Text(a.appDisplayName),
                          trailing: Text(
                            '${a.minutesUsed}/${a.dailyLimitMinutes}m',
                            style: TextStyle(
                              color: a.isEffectivelyBlocked
                                  ? Colors.red
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),

                if (healthEvents.isNotEmpty) ...[
                  const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Recent protection events',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...healthEvents.map(
                    (event) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        switch (event.tamperState) {
                          DeviceTamperState.healthy => Icons.check_circle,
                          DeviceTamperState.degraded =>
                            Icons.warning_amber_rounded,
                          DeviceTamperState.tampered => Icons.gpp_bad,
                          DeviceTamperState.offline => Icons.cloud_off,
                        },
                        color: switch (event.tamperState) {
                          DeviceTamperState.healthy => Colors.green,
                          DeviceTamperState.degraded => Colors.orange,
                          DeviceTamperState.tampered => Colors.red,
                          DeviceTamperState.offline => Colors.grey,
                        },
                      ),
                      title: Text(
                        event.isReminder
                            ? 'Reminder: ${event.tamperState.name}'
                            : event.tamperState.name,
                      ),
                      subtitle: Text(
                        event.tamperReason?.trim().isNotEmpty == true
                            ? event.tamperReason!
                            : 'Protection state changed.',
                      ),
                      trailing: Text(
                        '${event.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${event.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                ],

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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
  int get blockedCount =>
      activities.where((a) => a.isEffectivelyBlocked).length;
  int get activeCount =>
      activities.where((a) => !a.isEffectivelyBlocked).length;

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
                final parentState = context
                    .findAncestorStateOfType<_ParentDashboardScreenState>();
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
                final parentState = context
                    .findAncestorStateOfType<_ParentDashboardScreenState>();
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
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
