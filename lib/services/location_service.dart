/// Location Service
///
/// Handles GPS tracking, geofence management, and SOS alerts.
/// Uses geolocator for cross-platform location access.
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/location_record.dart';
import '../models/geofence.dart';

class LocationService {
  static const Duration _periodicFlushInterval = Duration(minutes: 5);
  static const int _maxPendingLocations = 10;

  static final LocationService _instance = LocationService._internal();

  factory LocationService() {
    return _instance;
  }

  LocationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Batching state
  final List<Map<String, dynamic>> _pendingLocations = [];
  DateTime? _oldestPendingLocationAt;

  // Tracking state
  String? _currentChildId;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _uploadTimer;
  final Map<String, bool> _insideGeofence = {};

  /// Start continuous location tracking (for child device)
  Future<void> startTracking(String childId) async {
    // Stop any existing tracking
    await stopTracking();

    _currentChildId = childId;

    // Configure location settings
    LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 10),
        // Foreground notification config
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "ParentLock Active",
          notificationText: "Monitoring child location for safety",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    // Start listening to position stream
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            _onLocationUpdate(position);
          },
          onError: (e) {
            debugPrint('LocationService stream error: $e');
          },
        );

    // Also upload/flush periodically (every 5 minutes)
    _uploadTimer = Timer.periodic(
      _periodicFlushInterval,
      (_) => _uploadCurrentLocation(),
    );

    // Upload initial location immediately
    await _uploadCurrentLocation();
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;

    // Flux remaining locations
    await _flushLocations();

    _currentChildId = null;
  }

  Future<void> handleLocationUpdate(Position position) async {
    _onLocationUpdate(position);
  }

  void _onLocationUpdate(Position position) async {
    if (_currentChildId == null) return;

    // Save to local batch
    await _saveLocation(
      childId: _currentChildId!,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );

    // Check geofences (Immediate check still required for safety)
    await _checkGeofences(position);
  }

  Future<void> _uploadCurrentLocation() async {
    if (_currentChildId == null) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await _saveLocation(
        childId: _currentChildId!,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );

      // Force flush on periodic timer
      await _flushLocations();
    } catch (e) {
      debugPrint('LocationService upload error: $e');
    }
  }

  Future<void> _saveLocation({
    required String childId,
    required double latitude,
    required double longitude,
    double? accuracy,
    int? batteryLevel,
  }) async {
    final record = {
      'child_id': childId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'battery_level': batteryLevel,
      'recorded_at': DateTime.now().toIso8601String(),
    };

    if (_pendingLocations.isEmpty) {
      _oldestPendingLocationAt = DateTime.now();
    }
    _pendingLocations.add(record);

    final oldestPendingLocationAt = _oldestPendingLocationAt;
    final hasPendingForTooLong =
        oldestPendingLocationAt != null &&
        DateTime.now().difference(oldestPendingLocationAt) >=
            _periodicFlushInterval;

    if (_pendingLocations.length >= _maxPendingLocations ||
        hasPendingForTooLong) {
      await _flushLocations();
    }
  }

  /// Flush pending locations to Supabase
  Future<void> _flushLocations() async {
    if (_pendingLocations.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_pendingLocations);
    _pendingLocations.clear();
    _oldestPendingLocationAt = null;

    try {
      await _supabase.from('location_records').insert(batch);
    } catch (e) {
      _pendingLocations.insertAll(0, batch);
      _oldestPendingLocationAt ??= _extractRecordedAt(batch.first);
      debugPrint('Failed to flush locations: $e');
      if (e is PostgrestException) {
        debugPrint('Postgrest error: ${e.message} - ${e.details} - ${e.hint}');
      }
    }
  }

  DateTime? _extractRecordedAt(Map<String, dynamic> record) {
    final recordedAt = record['recorded_at'];
    if (recordedAt is String) {
      return DateTime.tryParse(recordedAt);
    }
    return null;
  }

  // ==================== LOCATION HISTORY ====================

  /// Get location history for a child
  Future<List<LocationRecord>> getLocationHistory(
    String childId, {
    int hours = 24,
  }) async {
    final since = DateTime.now().subtract(Duration(hours: hours));

    final response = await _supabase
        .from('location_records')
        .select()
        .eq('child_id', childId)
        .gte('recorded_at', since.toIso8601String())
        .order('recorded_at', ascending: false)
        .limit(100);

    return (response as List)
        .map((json) => LocationRecord.fromJson(json))
        .toList();
  }

  /// Get the most recent location for a child
  Future<LocationRecord?> getLatestLocation(String childId) async {
    try {
      final response = await _supabase
          .from('location_records')
          .select()
          .eq('child_id', childId)
          .order('recorded_at', ascending: false)
          .limit(1)
          .single();

      return LocationRecord.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  // ==================== GEOFENCES ====================

  /// Create a new geofence
  Future<Geofence> createGeofence(Geofence geofence) async {
    final response = await _supabase
        .from('geofences')
        .insert(geofence.toJson())
        .select()
        .single();

    return Geofence.fromJson(response);
  }

  /// Get all geofences for a child
  Future<List<Geofence>> getGeofences(String childId) async {
    final response = await _supabase
        .from('geofences')
        .select()
        .eq('child_id', childId)
        .eq('is_active', true);

    return (response as List).map((json) => Geofence.fromJson(json)).toList();
  }

  /// Update a geofence
  Future<void> updateGeofence(Geofence geofence) async {
    await _supabase
        .from('geofences')
        .update(geofence.toJson())
        .eq('id', geofence.id);
  }

  /// Delete a geofence
  Future<void> deleteGeofence(String id) async {
    await _supabase.from('geofences').delete().eq('id', id);
  }

  /// Check if position is inside a geofence
  bool isInsideGeofence(double lat, double lng, Geofence geofence) {
    final distance = _calculateDistance(
      lat,
      lng,
      geofence.latitude,
      geofence.longitude,
    );
    return distance <= geofence.radiusMeters;
  }

  /// Check all geofences and trigger events
  Future<void> _checkGeofences(Position position) async {
    if (_currentChildId == null) return;

    final geofences = await getGeofences(_currentChildId!);

    for (final geofence in geofences) {
      final isInside = isInsideGeofence(
        position.latitude,
        position.longitude,
        geofence,
      );

      final wasInside = _insideGeofence[geofence.id] ?? false;

      if (isInside && !wasInside) {
        // Entered geofence
        _insideGeofence[geofence.id] = true;
        if (geofence.notifyOnEnter) {
          await _recordGeofenceEvent(geofence.id, _currentChildId!, 'enter');
        }
      } else if (!isInside && wasInside) {
        // Exited geofence
        _insideGeofence[geofence.id] = false;
        if (geofence.notifyOnExit) {
          await _recordGeofenceEvent(geofence.id, _currentChildId!, 'exit');
        }
      }
    }
  }

  Future<void> _recordGeofenceEvent(
    String geofenceId,
    String childId,
    String eventType,
  ) async {
    await _supabase.from('geofence_events').insert({
      'geofence_id': geofenceId,
      'child_id': childId,
      'event_type': eventType,
    });
  }

  /// Get recent geofence events
  Future<List<GeofenceEvent>> getGeofenceEvents(
    String childId, {
    int hours = 24,
  }) async {
    final since = DateTime.now().subtract(Duration(hours: hours));

    final response = await _supabase
        .from('geofence_events')
        .select()
        .eq('child_id', childId)
        .gte('recorded_at', since.toIso8601String())
        .order('recorded_at', ascending: false);

    return (response as List)
        .map((json) => GeofenceEvent.fromJson(json))
        .toList();
  }

  // ==================== SOS ALERTS ====================

  /// Send SOS alert from child device
  Future<void> sendSosAlert(String childId, {String? message}) async {
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('LocationService SOS location error: $e');
      // Continue without location if unable to get it
    }

    await _supabase.from('sos_alerts').insert({
      'child_id': childId,
      'latitude': position?.latitude,
      'longitude': position?.longitude,
      'message': message,
    });
  }

  /// Get SOS alerts for parent's children
  Future<List<SosAlert>> getSosAlerts(String parentId) async {
    final response = await _supabase
        .from('sos_alerts')
        .select('*, profiles!child_id(linked_to)')
        .order('created_at', ascending: false)
        .limit(50);

    // Filter to only this parent's children
    return (response as List)
        .where((json) => json['profiles']?['linked_to'] == parentId)
        .map((json) => SosAlert.fromJson(json))
        .toList();
  }

  /// Acknowledge an SOS alert
  Future<void> acknowledgeSosAlert(String alertId) async {
    await _supabase
        .from('sos_alerts')
        .update({'is_acknowledged': true})
        .eq('id', alertId);
  }

  // ==================== UTILITIES ====================

  /// Calculate distance between two points in meters (Haversine formula)
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // meters

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  /// Subscribe to real-time location updates (for parent dashboard)
  RealtimeChannel subscribeToLocationUpdates({
    required String childId,
    required void Function(LocationRecord) onUpdate,
  }) {
    return _supabase
        .channel('location_$childId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'location_records',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'child_id',
            value: childId,
          ),
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              onUpdate(LocationRecord.fromJson(payload.newRecord));
            }
          },
        )
        .subscribe();
  }

  /// Subscribe to SOS alerts (for parent)
  RealtimeChannel subscribeToSosAlerts({
    required String parentId,
    required void Function(SosAlert) onAlert,
  }) {
    return _supabase
        .channel('sos_alerts_$parentId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sos_alerts',
          callback: (payload) async {
            if (payload.newRecord.isNotEmpty) {
              // Verify this is for one of parent's children
              final alert = SosAlert.fromJson(payload.newRecord);
              // For now, pass all alerts - parent dashboard will filter
              onAlert(alert);
            }
          },
        )
        .subscribe();
  }
}
