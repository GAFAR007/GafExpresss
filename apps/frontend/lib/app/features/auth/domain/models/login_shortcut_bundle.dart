library;

class LoginShortcutAccount {
  final String id;
  final String fullName;
  final String email;
  final String role;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final bool isNinVerified;
  final String? staffRole;
  final String? subtitle;
  final String? addressLabel;

  const LoginShortcutAccount({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isEmailVerified,
    required this.isPhoneVerified,
    required this.isNinVerified,
    this.staffRole,
    this.subtitle,
    this.addressLabel,
  });

  bool get isFullyVerified =>
      isEmailVerified && isPhoneVerified && isNinVerified;

  factory LoginShortcutAccount.fromJson(Map<String, dynamic> json) {
    return LoginShortcutAccount(
      id: (json['id'] ?? '').toString(),
      fullName: (json['fullName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      isEmailVerified: json['isEmailVerified'] == true,
      isPhoneVerified: json['isPhoneVerified'] == true,
      isNinVerified: json['isNinVerified'] == true,
      staffRole: _readOptionalString(json['staffRole']),
      subtitle: _readOptionalString(json['subtitle']),
      addressLabel: _readOptionalString(json['addressLabel']),
    );
  }
}

class LoginShortcutBundle {
  final String role;
  final List<LoginShortcutAccount> accounts;

  const LoginShortcutBundle({required this.role, required this.accounts});

  factory LoginShortcutBundle.fromJson(Map<String, dynamic> json) {
    final rawAccounts = json['accounts'] as List<dynamic>? ?? const [];

    return LoginShortcutBundle(
      role: (json['role'] ?? '').toString(),
      accounts: rawAccounts
          .whereType<Map>()
          .map(
            (account) => LoginShortcutAccount.fromJson(
              Map<String, dynamic>.from(account),
            ),
          )
          .toList(),
    );
  }
}

String? _readOptionalString(dynamic value) {
  final trimmed = value?.toString().trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
