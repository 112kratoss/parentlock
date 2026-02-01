/// Geofence Model
/// 
/// Represents a geographic safe zone with radius and notification settings.
library;

class Geofence {
  final String id;
  final String parentId;
  final String childId;
  final String name;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final bool notifyOnEnter;
  final bool notifyOnExit;
  final bool isActive;
  final DateTime createdAt;

  Geofence({
    required this.id,
    required this.parentId,
    required this.childId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 100,
    this.notifyOnEnter = true,
    this.notifyOnExit = true,
    this.isActive = true,
    required this.createdAt,
  });

  /// Create from Supabase JSON response
  factory Geofence.fromJson(Map<String, dynamic> json) {
    return Geofence(
      id: json['id'] as String,
      parentId: json['parent_id'] as String,
      childId: json['child_id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: json['radius_meters'] as int? ?? 100,
      notifyOnEnter: json['notify_on_enter'] as bool? ?? true,
      notifyOnExit: json['notify_on_exit'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'parent_id': parentId,
      'child_id': childId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'notify_on_enter': notifyOnEnter,
      'notify_on_exit': notifyOnExit,
      'is_active': isActive,
    };
  }

  /// Create a copy with updated fields
  Geofence copyWith({
    String? id,
    String? parentId,
    String? childId,
    String? name,
    double? latitude,
    double? longitude,
    int? radiusMeters,
    bool? notifyOnEnter,
    bool? notifyOnExit,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Geofence(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      childId: childId ?? this.childId,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      notifyOnEnter: notifyOnEnter ?? this.notifyOnEnter,
      notifyOnExit: notifyOnExit ?? this.notifyOnExit,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'Geofence(name: $name, lat: $latitude, lng: $longitude, radius: ${radiusMeters}m)';
  }
}

/// Geofence Event Types
enum GeofenceEventType {
  enter,
  exit;

  String toJson() => name;

  static GeofenceEventType fromJson(String json) {
    return GeofenceEventType.values.firstWhere((e) => e.name == json);
  }
}

/// Geofence Event Model
class GeofenceEvent {
  final String id;
  final String geofenceId;
  final String childId;
  final GeofenceEventType eventType;
  final DateTime recordedAt;

  GeofenceEvent({
    required this.id,
    required this.geofenceId,
    required this.childId,
    required this.eventType,
    required this.recordedAt,
  });

  factory GeofenceEvent.fromJson(Map<String, dynamic> json) {
    return GeofenceEvent(
      id: json['id'] as String,
      geofenceId: json['geofence_id'] as String,
      childId: json['child_id'] as String,
      eventType: GeofenceEventType.fromJson(json['event_type'] as String),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'geofence_id': geofenceId,
      'child_id': childId,
      'event_type': eventType.toJson(),
    };
  }
}

/// SOS Alert Model
class SosAlert {
  final String id;
  final String childId;
  final double? latitude;
  final double? longitude;
  final String? message;
  final bool isAcknowledged;
  final DateTime createdAt;

  SosAlert({
    required this.id,
    required this.childId,
    this.latitude,
    this.longitude,
    this.message,
    this.isAcknowledged = false,
    required this.createdAt,
  });

  factory SosAlert.fromJson(Map<String, dynamic> json) {
    return SosAlert(
      id: json['id'] as String,
      childId: json['child_id'] as String,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      message: json['message'] as String?,
      isAcknowledged: json['is_acknowledged'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'child_id': childId,
      'latitude': latitude,
      'longitude': longitude,
      'message': message,
    };
  }
}
