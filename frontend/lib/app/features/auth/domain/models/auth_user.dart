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

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String role;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    debugPrint("AUTH: AuthUser.fromJson() called");
    return AuthUser(
      id: (json["id"] ?? "").toString(),
      name: (json["name"] ?? "").toString(),
      email: (json["email"] ?? "").toString(),
      role: (json["role"] ?? "").toString(),
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
    return {"id": id, "name": name, "email": email, "role": role};
  }
}
