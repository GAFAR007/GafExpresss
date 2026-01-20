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
  final UserAddress? homeAddress;
  final String? companyName;
  final String? companyEmail;
  final String? companyPhone;
  final UserAddress? companyAddress;
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
    this.homeAddress,
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
      homeAddress: UserAddress.fromJson(json['homeAddress']),
      companyName: _nullIfEmpty(json['companyName']),
      companyEmail: _nullIfEmpty(json['companyEmail']),
      companyPhone: _nullIfEmpty(json['companyPhone']),
      companyAddress: UserAddress.fromJson(json['companyAddress']),
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
      "homeAddress": homeAddress?.toUpdateJson(),
      "accountType": accountType,
      "companyName": companyName,
      "companyEmail": companyEmail,
      "companyPhone": companyPhone,
      "companyAddress": companyAddress?.toUpdateJson(),
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
    UserAddress? homeAddress,
    String? accountType,
    bool? isEmailVerified,
    bool? isPhoneVerified,
    bool? isNinVerified,
    String? ninLast4,
    String? companyName,
    String? companyEmail,
    String? companyPhone,
    UserAddress? companyAddress,
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
      homeAddress: homeAddress ?? this.homeAddress,
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

/// ------------------------------------------------------
/// USER ADDRESS MODEL
/// ------------------------------------------------------
/// WHAT:
/// - Structured address used for home/company delivery verification.
///
/// WHY:
/// - Required fields (house/street/city/state) must be validated.
/// - Keeps verification metadata next to the saved address.
///
/// HOW:
/// - fromJson parses backend objects.
/// - toUpdateJson only sends editable fields back to backend.
class UserAddress {
  final String? houseNumber;
  final String? street;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? lga;
  final String? country;
  final String? landmark;
  final bool isVerified;
  final String? verifiedAt;
  final String? verificationSource;
  final String? formattedAddress;
  final String? placeId;
  final double? lat;
  final double? lng;

  const UserAddress({
    this.houseNumber,
    this.street,
    this.city,
    this.state,
    this.postalCode,
    this.lga,
    this.country,
    this.landmark,
    required this.isVerified,
    this.verifiedAt,
    this.verificationSource,
    this.formattedAddress,
    this.placeId,
    this.lat,
    this.lng,
  });

  factory UserAddress.fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return const UserAddress(isVerified: false);
    }

    return UserAddress(
      houseNumber: _nullIfEmpty(value['houseNumber']),
      street: _nullIfEmpty(value['street']),
      city: _nullIfEmpty(value['city']),
      state: _nullIfEmpty(value['state']),
      postalCode: _nullIfEmpty(value['postalCode']),
      lga: _nullIfEmpty(value['lga']),
      country: _nullIfEmpty(value['country']),
      landmark: _nullIfEmpty(value['landmark']),
      isVerified: value['isVerified'] == true,
      verifiedAt: _nullIfEmpty(value['verifiedAt']),
      verificationSource: _nullIfEmpty(value['verificationSource']),
      formattedAddress: _nullIfEmpty(value['formattedAddress']),
      placeId: _nullIfEmpty(value['placeId']),
      lat: value['lat'] is num ? (value['lat'] as num).toDouble() : null,
      lng: value['lng'] is num ? (value['lng'] as num).toDouble() : null,
    );
  }

  /// WHY: Only send editable fields (backend controls verification metadata).
  Map<String, dynamic> toUpdateJson() {
    return {
      "houseNumber": houseNumber,
      "street": street,
      "city": city,
      "state": state,
      "postalCode": postalCode,
      "lga": lga,
      "country": country,
      "landmark": landmark,
    };
  }

  /// WHY: Keep optional string handling consistent and clean.
  static String? _nullIfEmpty(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
