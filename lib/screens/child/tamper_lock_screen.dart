library;

import 'package:flutter/material.dart';

class TamperLockScreen extends StatelessWidget {
  final String tamperReason;
  final bool isManagedDevice;
  final Future<void> Function() onReviewProtection;

  const TamperLockScreen({
    super.key,
    required this.tamperReason,
    required this.isManagedDevice,
    required this.onReviewProtection,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF4A0E0E), Color(0xFF921515), Color(0xFF2B0A0A)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 72,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Protection Interrupted',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tamperReason,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      isManagedDevice
                          ? 'This child device is enrolled for managed protection. ParentLock will keep trying to recover and the parent is being alerted now.'
                          : 'This device is in standard monitoring mode. ParentLock has alerted the parent and needs its protection settings restored before normal use resumes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () async {
                      await onReviewProtection();
                    },
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Review Protection Settings'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF7A1212),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
