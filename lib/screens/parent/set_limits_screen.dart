/// Set Limits Screen
/// 
/// Screen for parents to set app time limits for children
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';

class SetLimitsScreen extends StatefulWidget {
  const SetLimitsScreen({super.key});

  @override
  State<SetLimitsScreen> createState() => _SetLimitsScreenState();
}

class _SetLimitsScreenState extends State<SetLimitsScreen> {
  final _authService = AuthService();
  final _databaseService = DatabaseService();
  
  final _appNameController = TextEditingController();
  final _packageNameController = TextEditingController();
  
  List<UserProfile> _children = [];
  UserProfile? _selectedChild;
  int _limitMinutes = 30;
  bool _isLoading = false;

  // Common apps list
  final List<Map<String, String>> _commonApps = [
    {'name': 'YouTube', 'package': 'com.google.android.youtube'},
    {'name': 'Instagram', 'package': 'com.instagram.android'},
    {'name': 'TikTok', 'package': 'com.zhiliaoapp.musically'},
    {'name': 'Snapchat', 'package': 'com.snapchat.android'},
    {'name': 'Facebook', 'package': 'com.facebook.katana'},
    {'name': 'Twitter/X', 'package': 'com.twitter.android'},
    {'name': 'WhatsApp', 'package': 'com.whatsapp'},
    {'name': 'Netflix', 'package': 'com.netflix.mediaclient'},
    {'name': 'Roblox', 'package': 'com.roblox.client'},
    {'name': 'Minecraft', 'package': 'com.mojang.minecraftpe'},
  ];

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  @override
  void dispose() {
    _appNameController.dispose();
    _packageNameController.dispose();
    super.dispose();
  }

  Future<void> _loadChildren() async {
    final userId = _authService.currentUser?.id;
    if (userId != null) {
      final children = await _databaseService.getLinkedChildren(userId);
      setState(() {
        _children = children;
        if (children.isNotEmpty) {
          _selectedChild = children.first;
        }
      });
    }
  }

  Future<void> _setLimit() async {
    if (_selectedChild == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a child first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_appNameController.text.isEmpty || _packageNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter app name and package'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _databaseService.setAppLimit(
        childId: _selectedChild!.id,
        appPackageName: _packageNameController.text.trim(),
        appDisplayName: _appNameController.text.trim(),
        dailyLimitMinutes: _limitMinutes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Limit set successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _selectCommonApp(Map<String, String> app) {
    setState(() {
      _appNameController.text = app['name']!;
      _packageNameController.text = app['package']!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set App Limit'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Select Child
            Text(
              'Select Child',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            if (_children.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No children linked. Please link a child device first.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButton<UserProfile>(
                    value: _selectedChild,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _children.map((child) {
                      return DropdownMenuItem(
                        value: child,
                        child: Text('Child: ${child.id.substring(0, 8)}'),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedChild = value),
                  ),
                ),
              ),
            
            const SizedBox(height: 24),

            // Common Apps
            Text(
              'Quick Select',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _commonApps.map((app) {
                final isSelected = _appNameController.text == app['name'];
                return ChoiceChip(
                  label: Text(app['name']!),
                  selected: isSelected,
                  onSelected: (_) => _selectCommonApp(app),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // App Name Input
            TextField(
              controller: _appNameController,
              decoration: InputDecoration(
                labelText: 'App Name',
                hintText: 'e.g., YouTube',
                prefixIcon: const Icon(Icons.apps),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Package Name Input
            TextField(
              controller: _packageNameController,
              decoration: InputDecoration(
                labelText: 'Package Name',
                hintText: 'e.g., com.google.android.youtube',
                prefixIcon: const Icon(Icons.code),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Time Limit
            Text(
              'Daily Time Limit',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      '$_limitMinutes minutes',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      '(${(_limitMinutes / 60).toStringAsFixed(1)} hours)',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: _limitMinutes.toDouble(),
                      min: 5,
                      max: 240,
                      divisions: 47,
                      label: '$_limitMinutes min',
                      onChanged: (value) {
                        setState(() => _limitMinutes = value.round());
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('5 min'),
                        const Text('4 hours'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Set Limit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _setLimit,
                icon: _isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Set Limit'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
