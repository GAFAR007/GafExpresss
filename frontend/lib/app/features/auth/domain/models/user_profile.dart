/// lib/app/features/auth/domain/models/user_profile.dart
/// ------------------------------------------------------
/// WHAT:
/// - UserProfile model for the settings/profile form.
///
/// WHY:
/// - Keeps profile fields typed and consistent across API/UI.
/// - Prevents ad-hoc map parsing in widgets.
///
/// HOW:
/// - fromJson parses backend payload into a Dart model.
/// - toUpdateJson builds a safe payload for profile updates.
/// ------------------------------------------------------
library;

class UserProfile {
  final String id;
  final String name;
  final String? firstName;
  final String? lastName;
  final String? middleName;
  final String? dob;
  final String email;
  final String role;
  final String accountType;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final bool isNinVerified;
  final String? ninLast4;
  final String? phone;
  final String? profileImageUrl;
  final String? companyName;
  final String? companyEmail;
  final String? companyPhone;
  final String? companyAddress;
  final String? companyWebsite;
  final String? companyRegistration;

  const UserProfile({
    required this.id,
    required this.name,
    this.firstName,
    this.lastName,
    this.middleName,
    this.dob,
    required this.email,
    required this.role,
    required this.accountType,
    required this.isEmailVerified,
    required this.isPhoneVerified,
    required this.isNinVerified,
    this.ninLast4,
    this.phone,
    this.profileImageUrl,
    this.companyName,
    this.companyEmail,
    this.companyPhone,
    this.companyAddress,
    this.companyWebsite,
    this.companyRegistration,
  });

  /// ------------------------------------------------------
  /// FROM JSON
  /// ------------------------------------------------------
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    // WHY: Accept either `id` or Mongo `_id` without breaking.
    final rawId = json['id'] ?? json['_id'] ?? '';

    // WHY: Account type may be missing on older records.
    final rawAccountType = (json['accountType'] ?? 'personal').toString();

    return UserProfile(
      id: rawId.toString(),
      name: (json['name'] ?? '').toString(),
      firstName: _nullIfEmpty(json['firstName']),
      lastName: _nullIfEmpty(json['lastName']),
      middleName: _nullIfEmpty(json['middleName']),
      dob: _nullIfEmpty(json['dob']),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? 'customer').toString(),
      accountType: rawAccountType,
      isEmailVerified: json['isEmailVerified'] == true,
      isPhoneVerified: json['isPhoneVerified'] == true,
      isNinVerified: json['isNinVerified'] == true,
      ninLast4: _nullIfEmpty(json['ninLast4']),
      phone: _nullIfEmpty(json['phone']),
      profileImageUrl: _nullIfEmpty(json['profileImageUrl']),
      companyName: _nullIfEmpty(json['companyName']),
      companyEmail: _nullIfEmpty(json['companyEmail']),
      companyPhone: _nullIfEmpty(json['companyPhone']),
      companyAddress: _nullIfEmpty(json['companyAddress']),
      companyWebsite: _nullIfEmpty(json['companyWebsite']),
      companyRegistration: _nullIfEmpty(json['companyRegistration']),
    );
  }

  /// ------------------------------------------------------
  /// UPDATE JSON
  /// ------------------------------------------------------
  Map<String, dynamic> toUpdateJson() {
    return {
      "name": name,
      "firstName": firstName,
      "lastName": lastName,
      // WHY: Allow backend to update email while unverified.
      "email": email,
      "phone": phone,
      "profileImageUrl": profileImageUrl,
      "accountType": accountType,
      "companyName": companyName,
      "companyEmail": companyEmail,
      "companyPhone": companyPhone,
      "companyAddress": companyAddress,
      "companyWebsite": companyWebsite,
      "companyRegistration": companyRegistration,
    };
  }

  /// ------------------------------------------------------
  /// COPY WITH
  /// ------------------------------------------------------
  UserProfile copyWith({
    String? name,
    String? firstName,
    String? lastName,
    String? middleName,
    String? dob,
    String? phone,
    String? profileImageUrl,
    String? accountType,
    bool? isEmailVerified,
    bool? isPhoneVerified,
    bool? isNinVerified,
    String? ninLast4,
    String? companyName,
    String? companyEmail,
    String? companyPhone,
    String? companyAddress,
    String? companyWebsite,
    String? companyRegistration,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleName: middleName ?? this.middleName,
      dob: dob ?? this.dob,
      email: email,
      role: role,
      accountType: accountType ?? this.accountType,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
      isNinVerified: isNinVerified ?? this.isNinVerified,
      ninLast4: ninLast4 ?? this.ninLast4,
      phone: phone ?? this.phone,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      companyName: companyName ?? this.companyName,
      companyEmail: companyEmail ?? this.companyEmail,
      companyPhone: companyPhone ?? this.companyPhone,
      companyAddress: companyAddress ?? this.companyAddress,
      companyWebsite: companyWebsite ?? this.companyWebsite,
      companyRegistration: companyRegistration ?? this.companyRegistration,
    );
  }

  /// WHY: Keep optional string handling consistent and clean.
  static String? _nullIfEmpty(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
