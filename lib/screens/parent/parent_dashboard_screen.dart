/// Parent Dashboard Screen
/// 
/// Main dashboard for parents showing children's statistics
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/child_activity.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _authService = AuthService();
  final _databaseService = DatabaseService();
  
  List<UserProfile> _children = [];
  List<ChildActivity> _activities = [];
  bool _isLoading = true;
  String? _linkingCode;

  @override
  void initState() {
    super.initState();
    _loadData();
    _generateLinkingCode();
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
                    _StatsGrid(activities: _activities),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/parent/set-limits'),
        icon: const Icon(Icons.add),
        label: const Text('Set Limits'),
      ),
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
      activities.where((a) => a.isBlocked).length;

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
                      a.isBlocked ? Icons.block : Icons.check_circle,
                      color: a.isBlocked ? Colors.red : Colors.green,
                    ),
                    title: Text(a.appDisplayName),
                    trailing: Text(
                      '${a.minutesUsed}/${a.dailyLimitMinutes}m',
                      style: TextStyle(
                        color: a.isBlocked ? Colors.red : Colors.grey,
                      ),
                    ),
                  )),
              ],
            ),
          ),
        ],
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

  const _StatsGrid({required this.activities});

  int get totalMinutes => activities.fold(0, (sum, a) => sum + a.minutesUsed);
  int get blockedCount => activities.where((a) => a.isBlocked).length;
  int get activeCount => activities.where((a) => !a.isBlocked).length;

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
          child: _QuickStatCard(
            icon: Icons.apps,
            label: 'Active Apps',
            value: '$activeCount',
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickStatCard(
            icon: Icons.block,
            label: 'Blocked',
            value: '$blockedCount',
            color: Colors.red,
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
