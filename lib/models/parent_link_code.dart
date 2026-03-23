/// Parent link code model
///
/// Represents a short-lived linking code generated for a parent account.
library;

class ParentLinkCode {
  final String code;
  final DateTime expiresAt;

  ParentLinkCode({required this.code, required this.expiresAt});

  factory ParentLinkCode.fromJson(Map<String, dynamic> json) {
    return ParentLinkCode(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
