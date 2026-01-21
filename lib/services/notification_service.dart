/// Notification Service
/// 
/// Handles Firebase Cloud Messaging (FCM) for push notifications.
/// - Initializes FCM
/// - Handles foreground/background messages
/// - Manages notification permissions
library;

import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'auth_service.dart';

/// Handle background messages (must be top-level function)
@pragma('vm:entry-point')
Future<void> handleBackgroundMessage(RemoteMessage message) async {
  // Handle background message
  print('Background message: ${message.notification?.title}');
}

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();
  final AuthService _authService = AuthService();

  /// Android notification channel for high importance notifications
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'parentlock_channel',
    'ParentLock Notifications',
    description: 'Notifications for app blocking and usage alerts',
    importance: Importance.high,
  );

  /// Initialize the notification service
  Future<void> initialize() async {
    // Request permission
    await _requestPermission();
    
    // Set up local notifications
    await _setupLocalNotifications();
    
    // Get FCM token and save to profile
    await _getFcmToken();
    
    // Set up message handlers
    _setupMessageHandlers();
  }

  /// Request notification permissions
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    print('Notification permission status: ${settings.authorizationStatus}');
  }

  /// Set up local notifications for foreground display
  Future<void> _setupLocalNotifications() async {
    // Android initialization
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS initialization
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create Android notification channel
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }
  }

  /// Handle notification tap
  void _onNotificationTap(NotificationResponse response) {
    // Handle notification tap - navigate to relevant screen
    print('Notification tapped: ${response.payload}');
  }

  /// Get FCM token and save to user profile
  Future<String?> _getFcmToken() async {
    try {
      final token = await _messaging.getToken();
      
      if (token != null) {
        await _authService.updateFcmToken(token);
        print('FCM Token: $token');
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _authService.updateFcmToken(newToken);
      });

      return token;
    } catch (e) {
      print('Failed to get FCM token: $e');
      return null;
    }
  }

  /// Set up message handlers for foreground and background
  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);
  }

  /// Handle foreground message - show local notification
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    
    if (notification == null) return;

    // Show local notification
    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data.toString(),
    );
  }

  /// Handle when app is opened from notification
  void _handleNotificationOpen(RemoteMessage message) {
    print('App opened from notification: ${message.data}');
    // Navigate based on message data
  }

  /// Show a custom local notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  /// Subscribe to a topic for group notifications
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
  }
}
