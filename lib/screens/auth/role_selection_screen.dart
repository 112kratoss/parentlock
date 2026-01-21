/// Role Selection Screen
/// 
/// Allows users to choose between Parent and Child roles
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final _authService = AuthService();
  bool _isLoading = false;

  Future<void> _selectRole(String role) async {
    setState(() => _isLoading = true);

    try {
      await _authService.updateRole(role);
      
      if (mounted) {
        if (role == 'parent') {
          context.go('/parent/dashboard');
        } else {
          context.go('/child/link');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              Theme.of(context).colorScheme.primary.withOpacity(0.8),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                
                // Title
                Text(
                  'Choose Your Role',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you setting up this device as a parent or child?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                
                const SizedBox(height: 48),
                
                // Role Cards
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      // Parent Card
                      Expanded(
                        child: _RoleCard(
                          title: 'Parent',
                          description: 'Monitor children\'s screen time, set limits, and receive notifications.',
                          icon: Icons.admin_panel_settings,
                          color: Colors.blue,
                          isLoading: _isLoading,
                          onTap: () => _selectRole('parent'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Child Card
                      Expanded(
                        child: _RoleCard(
                          title: 'Child',
                          description: 'This device will be monitored. Apps may be limited based on parent settings.',
                          icon: Icons.child_care,
                          color: Colors.green,
                          isLoading: _isLoading,
                          onTap: () => _selectRole('child'),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Spacer(),
                
                // Logout option
                TextButton.icon(
                  onPressed: () async {
                    await _authService.logout();
                    if (context.mounted) context.go('/login');
                  },
                  icon: const Icon(Icons.logout, color: Colors.white70),
                  label: const Text(
                    'Sign out',
                    style: TextStyle(color: Colors.white70),
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

class _RoleCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool isLoading;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: isLoading ? null : onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(title),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
