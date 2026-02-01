/// Location Record Model
/// 
/// Represents a single GPS location point recorded from a child's device.
library;

class LocationRecord {
  final String id;
  final String childId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final int? batteryLevel;
  final DateTime recordedAt;

  LocationRecord({
    required this.id,
    required this.childId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.batteryLevel,
    required this.recordedAt,
  });

  /// Create from Supabase JSON response
  factory LocationRecord.fromJson(Map<String, dynamic> json) {
    return LocationRecord(
      id: json['id'] as String,
      childId: json['child_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: json['accuracy'] != null ? (json['accuracy'] as num).toDouble() : null,
      batteryLevel: json['battery_level'] as int?,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert
  Map<String, dynamic> toJson() {
    return {
      'child_id': childId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'battery_level': batteryLevel,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  LocationRecord copyWith({
    String? id,
    String? childId,
    double? latitude,
    double? longitude,
    double? accuracy,
    int? batteryLevel,
    DateTime? recordedAt,
  }) {
    return LocationRecord(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  @override
  String toString() {
    return 'LocationRecord(lat: $latitude, lng: $longitude, recorded: $recordedAt)';
  }
}
