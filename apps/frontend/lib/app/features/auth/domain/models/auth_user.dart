/// WHAT:
/// - AuthUser model returned by backend.
///
/// WHY:
/// - Keeps user data structured and type-safe across the app.
///
/// HOW:
/// - fromJson parses server payload into a Dart model.
///
/// DEBUGGING:
/// - fromJson prints when parsing (safe, no secrets).
library;

import 'package:flutter/foundation.dart';

// WHY: Centralize JSON keys to avoid inline magic strings.
const String _keyId = "id";
const String _keyName = "name";
const String _keyEmail = "email";
const String _keyRole = "role";
const String _keyBusinessId = "businessId";

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? businessId;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.businessId,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    debugPrint("AUTH: AuthUser.fromJson() called");
    // WHY: Business scoping is required for chat + business resources.
    final String? businessId = json[_keyBusinessId]?.toString();
    return AuthUser(
      id: (json[_keyId] ?? "").toString(),
      name: (json[_keyName] ?? "").toString(),
      email: (json[_keyEmail] ?? "").toString(),
      role: (json[_keyRole] ?? "").toString(),
      businessId: businessId,
    );
  }

  /// ------------------------------------------------------
  /// WHAT:
  /// - Converts AuthUser into JSON for local storage.
  ///
  /// WHY:
  /// - We persist session to restore logged-in state.
  ///
  /// SAFETY:
  /// - Never store passwords or tokens here.
  /// ------------------------------------------------------
  Map<String, dynamic> toJson() {
    // WHY: Persist businessId so scoped requests survive app restarts.
    return {
      _keyId: id,
      _keyName: name,
      _keyEmail: email,
      _keyRole: role,
      _keyBusinessId: businessId,
    };
  }
}
