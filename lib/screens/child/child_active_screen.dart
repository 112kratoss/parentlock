/// Child Active Screen
/// 
/// Main screen for child devices showing monitoring status
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/native_service.dart';

class ChildActiveScreen extends StatefulWidget {
  const ChildActiveScreen({super.key});

  @override
  State<ChildActiveScreen> createState() => _ChildActiveScreenState();
}

class _ChildActiveScreenState extends State<ChildActiveScreen> {
  final _authService = AuthService();
  final _nativeService = NativeService();
  final _databaseService = DatabaseService();
  bool _isMonitoring = false;
  String _status = 'Initializing...';
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _startMonitoring();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _startMonitoring() async {
    setState(() => _status = 'Starting monitoring service...');

    try {
      // Check and request permissions
      final hasPermissions = await _nativeService.checkPermissions();
      
      if (!hasPermissions) {
        setState(() => _status = 'Requesting permissions...');
        await _nativeService.requestPermissions();
      }

      // Start the native monitoring service
      await _nativeService.startMonitoringService([]);
      
      setState(() {
        _isMonitoring = true;
        _status = 'Monitoring active';
      });

      // Start periodic sync to Supabase (every 60 seconds)
      _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        _syncUsageToDatabase();
      });
      
      // Initial sync
      await _syncUsageToDatabase();
    } catch (e) {
      setState(() {
        _status = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _syncUsageToDatabase() async {
    try {
      final userId = _authService.currentUser?.id;
      if (userId == null) return;

      // Get full usage stats from native service (includes display names)
      final fullUsageStats = await _nativeService.getFullUsageStats();
      
      // Sync ALL apps to database (creates entries for new apps too)
      await _databaseService.syncAllUsageStats(
        childId: userId,
        fullUsageStats: fullUsageStats,
      );
      
      debugPrint('Usage synced to database: ${fullUsageStats.length} apps');
    } catch (e) {
      debugPrint('Failed to sync usage: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _isMonitoring ? Colors.green : Colors.orange,
              _isMonitoring ? Colors.green.shade700 : Colors.orange.shade700,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ParentLock',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await _authService.logout();
                        if (context.mounted) context.go('/login');
                      },
                      icon: const Icon(Icons.logout, color: Colors.white),
                    ),
                  ],
                ),
                
                const Spacer(),
                
                // Status Icon
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMonitoring 
                        ? Icons.shield_outlined 
                        : Icons.hourglass_empty,
                    size: 80,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Status Text
                Text(
                  _isMonitoring ? 'Protection Active' : 'Setting Up...',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Info Cards
                if (_isMonitoring) ...[
                  _InfoCard(
                    icon: Icons.visibility,
                    title: 'Usage Tracked',
                    subtitle: 'Your screen time is being monitored',
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.timer,
                    title: 'Limits Applied',
                    subtitle: 'App limits set by parent are active',
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.notifications_active,
                    title: 'Alerts Enabled',
                    subtitle: 'You\'ll be notified before limits are reached',
                  ),
                ],
                
                const Spacer(),
                
                // Note
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Keep this app running in the background for monitoring to work properly.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
