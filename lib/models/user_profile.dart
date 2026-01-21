/// User Profile Model
/// 
/// Represents a user in the ParentLock system.
/// Can be either a 'parent' or 'child' role.
library;

class UserProfile {
  final String id;
  final String role; // 'parent' or 'child'
  final String? fcmToken;
  final String? linkedTo; // For children: links to parent's profile ID
  final DateTime createdAt;

  UserProfile({
    required this.id,
    required this.role,
    this.fcmToken,
    this.linkedTo,
    required this.createdAt,
  });

  /// Create from Supabase JSON response
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      role: json['role'] as String,
      fcmToken: json['fcm_token'] as String?,
      linkedTo: json['linked_to'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'fcm_token': fcmToken,
      'linked_to': linkedTo,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  UserProfile copyWith({
    String? id,
    String? role,
    String? fcmToken,
    String? linkedTo,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      role: role ?? this.role,
      fcmToken: fcmToken ?? this.fcmToken,
      linkedTo: linkedTo ?? this.linkedTo,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isParent => role == 'parent';
  bool get isChild => role == 'child';
}
