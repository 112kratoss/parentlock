/// ParentLock - Main Entry Point
/// 
/// A cross-platform parental control application for iOS and Android.
/// 
/// Features:
/// - Parent Mode: Dashboard to view stats, set limits, receive notifications
/// - Child Mode: Background tracking and app blocking when limits are reached
library;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'config/supabase_config.dart';
import 'services/notification_service.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  // Initialize Notifications
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Run the app
  runApp(const ParentLockApp());
}
