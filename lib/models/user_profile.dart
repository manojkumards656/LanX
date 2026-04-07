class UserProfile {
  final String name;
  final String note;

  const UserProfile({
    required this.name,
    required this.note,
  });

  factory UserProfile.empty(String defaultName) {
    return UserProfile(
      name: defaultName,
      note: 'Secure local node',
    );
  }

  UserProfile copyWith({
    String? name,
    String? note,
  }) {
    return UserProfile(
      name: name ?? this.name,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'note': note,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json, String defaultName) {
    return UserProfile(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : defaultName,
      note: (json['note'] as String?) ?? '',
    );
  }
}