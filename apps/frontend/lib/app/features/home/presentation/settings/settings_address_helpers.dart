/// lib/app/features/home/presentation/settings/settings_address_helpers.dart
/// -------------------------------------------------------------------------
/// WHAT:
/// - Helper functions for building structured addresses from controllers.
///
/// WHY:
/// - Keeps SettingsScreen slim and focused on orchestration.
/// - Centralizes address normalization for reuse.
///
/// HOW:
/// - Reads controller values.
/// - Returns a UserAddress or null if empty.
/// - Provides a required-fields check for verification.
/// -------------------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/features/auth/domain/models/user_profile.dart';

UserAddress? buildAddressFromControllers({
  required TextEditingController houseNumberCtrl,
  required TextEditingController streetCtrl,
  required TextEditingController cityCtrl,
  required TextEditingController stateCtrl,
  required TextEditingController postalCtrl,
  required TextEditingController lgaCtrl,
  required TextEditingController landmarkCtrl,
  UserAddress? existing,
}) {
  // WHY: Convert UI text input into a structured address payload.
  final houseNumber = houseNumberCtrl.text.trim();
  final street = streetCtrl.text.trim();
  final city = cityCtrl.text.trim();
  final state = stateCtrl.text.trim();
  final postalCode = postalCtrl.text.trim();
  final lga = lgaCtrl.text.trim();
  final landmark = landmarkCtrl.text.trim();

  final hasAny = [
    houseNumber,
    street,
    city,
    state,
    postalCode,
    lga,
    landmark,
  ].any((value) => value.isNotEmpty);

  if (!hasAny) {
    return null;
  }

  return UserAddress(
    houseNumber: houseNumber.isEmpty ? null : houseNumber,
    street: street.isEmpty ? null : street,
    city: city.isEmpty ? null : city,
    state: state.isEmpty ? null : state,
    postalCode: postalCode.isEmpty ? null : postalCode,
    lga: lga.isEmpty ? null : lga,
    country: existing?.country ?? 'NG',
    landmark: landmark.isEmpty ? null : landmark,
    // WHY: Preserve verification metadata until backend decides otherwise.
    isVerified: existing?.isVerified ?? false,
    verifiedAt: existing?.verifiedAt,
    verificationSource: existing?.verificationSource,
    formattedAddress: existing?.formattedAddress,
    placeId: existing?.placeId,
    lat: existing?.lat,
    lng: existing?.lng,
  );
}

void applyAddressToControllers({
  required UserAddress? address,
  required TextEditingController houseNumberCtrl,
  required TextEditingController streetCtrl,
  required TextEditingController cityCtrl,
  required TextEditingController stateCtrl,
  required TextEditingController postalCtrl,
  required TextEditingController lgaCtrl,
  required TextEditingController landmarkCtrl,
}) {
  // WHY: Keep controllers in sync with profile data from backend.
  houseNumberCtrl.text = address?.houseNumber ?? '';
  streetCtrl.text = address?.street ?? '';
  cityCtrl.text = address?.city ?? '';
  stateCtrl.text = address?.state ?? '';
  postalCtrl.text = address?.postalCode ?? '';
  lgaCtrl.text = address?.lga ?? '';
  landmarkCtrl.text = address?.landmark ?? '';
}

bool addressChanged(UserAddress? next, UserAddress? current) {
  // WHY: Avoid clobbering user edits unless backend address data changed.
  if (next == null && current == null) return false;
  if (next == null || current == null) return true;

  return next.houseNumber != current.houseNumber ||
      next.street != current.street ||
      next.city != current.city ||
      next.state != current.state ||
      next.postalCode != current.postalCode ||
      next.lga != current.lga ||
      next.landmark != current.landmark ||
      next.country != current.country ||
      next.isVerified != current.isVerified;
}

bool canVerifyAddress({
  required TextEditingController houseNumberCtrl,
  required TextEditingController streetCtrl,
  required TextEditingController cityCtrl,
  required TextEditingController stateCtrl,
}) {
  // WHY: Block verification unless required fields are present.
  return houseNumberCtrl.text.trim().isNotEmpty &&
      streetCtrl.text.trim().isNotEmpty &&
      cityCtrl.text.trim().isNotEmpty &&
      stateCtrl.text.trim().isNotEmpty;
}
