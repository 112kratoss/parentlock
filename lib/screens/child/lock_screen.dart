/// Lock Screen
/// 
/// Full-screen overlay shown when a schedule is blocking device usage.
library;

import 'package:flutter/material.dart';
import '../../models/schedule.dart';
import '../../services/schedule_service.dart';
import '../../services/location_service.dart';

class LockScreen extends StatelessWidget {
  final LockScreenInfo info;
  final VoidCallback? onEmergencyCall;

  const LockScreen({
    super.key,
    required this.info,
    this.onEmergencyCall,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _getGradientColors(),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Text(
                info.icon,
                style: const TextStyle(fontSize: 80),
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                _getTitle(),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              // Message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  info.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // Unlock time
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Resumes at ${info.unlockTimeDisplay}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 80),

              // Emergency Call Button
              if (onEmergencyCall != null)
                TextButton.icon(
                  onPressed: onEmergencyCall,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  icon: const Icon(Icons.phone),
                  label: const Text('Emergency Call'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTitle() {
    switch (info.scheduleType) {
      case ScheduleType.bedtime:
        return "It's Bedtime!";
      case ScheduleType.homework:
        return "Focus Time";
      case ScheduleType.allowedHours:
        return "Screen Time Paused";
    }
  }

  List<Color> _getGradientColors() {
    switch (info.scheduleType) {
      case ScheduleType.bedtime:
        return [
          const Color(0xFF1a1a2e),
          const Color(0xFF16213e),
          const Color(0xFF0f3460),
        ];
      case ScheduleType.homework:
        return [
          const Color(0xFF134e5e),
          const Color(0xFF71b280),
        ];
      case ScheduleType.allowedHours:
        return [
          const Color(0xFF2c3e50),
          const Color(0xFF4ca1af),
        ];
    }
  }
}

/// SOS Button Widget for child device
class SosButtonWidget extends StatefulWidget {
  final String childId;
  final VoidCallback? onSosSent;

  const SosButtonWidget({
    super.key,
    required this.childId,
    this.onSosSent,
  });

  @override
  State<SosButtonWidget> createState() => _SosButtonWidgetState();
}

class _SosButtonWidgetState extends State<SosButtonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isPressed = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _sendSos();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown() {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _onTapUp() {
    if (!_controller.isCompleted) {
      _controller.reset();
    }
    setState(() => _isPressed = false);
  }

  Future<void> _sendSos() async {
    if (_isSending) return;

    setState(() => _isSending = true);

    try {
      final locationService = LocationService();
      await locationService.sendSosAlert(widget.childId, message: 'Emergency!');

      widget.onSosSent?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🆘 SOS sent to parent!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send SOS: $e')),
        );
      }
    } finally {
      setState(() {
        _isSending = false;
        _controller.reset();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _onTapDown(),
      onTapUp: (_) => _onTapUp(),
      onTapCancel: _onTapUp,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
              border: Border.all(
                color: Colors.white,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(_isPressed ? 0.6 : 0.3),
                  blurRadius: _isPressed ? 20 : 10,
                  spreadRadius: _isPressed ? 5 : 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Progress indicator
                if (_isPressed)
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      value: _controller.value,
                      strokeWidth: 4,
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),

                // Icon/Text
                _isSending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Hold',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          );
        },
      ),
    );
  }
}
