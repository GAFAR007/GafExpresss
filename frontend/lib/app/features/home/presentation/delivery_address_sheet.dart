/// lib/app/features/home/presentation/delivery_address_sheet.dart
/// -----------------------------------------------------------------
/// WHAT:
/// - Bottom sheet UI to choose a delivery address for checkout.
///
/// WHY:
/// - Checkout requires a verified delivery address.
/// - Keeps cart/product screens smaller and consistent.
///
/// HOW:
/// - Shows Home/Company options with verification status.
/// - Allows a one-time custom address with structured fields.
/// - Returns a payload-ready selection to the caller.
/// -----------------------------------------------------------------
library;

import 'package:flutter/material.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/settings/widgets/address_autocomplete_field.dart';
import 'package:frontend/app/features/home/presentation/settings/settings_address_helpers.dart';

enum DeliveryAddressSource { home, company, custom }

class DeliveryAddressSelection {
  final DeliveryAddressSource source;
  final UserAddress? customAddress;
  final String? placeId;

  const DeliveryAddressSelection({
    required this.source,
    this.customAddress,
    this.placeId,
  });

  /// WHY: Payload matches backend deliveryAddress schema.
  Map<String, dynamic> toPayload() {
    final payload = <String, dynamic>{
      "source": source.name,
    };

    if (source == DeliveryAddressSource.custom && customAddress != null) {
      payload.addAll(customAddress!.toUpdateJson());
      if (placeId != null && placeId!.isNotEmpty) {
        payload["placeId"] = placeId;
      }
    }

    return payload;
  }
}

class DeliveryAddressSheet extends StatefulWidget {
  final UserProfile profile;

  const DeliveryAddressSheet({
    super.key,
    required this.profile,
  });

  static Future<DeliveryAddressSelection?> open({
    required BuildContext context,
    required UserProfile profile,
  }) {
    AppDebug.log("DELIVERY_ADDRESS", "Open delivery address sheet");

    return showModalBottomSheet<DeliveryAddressSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DeliveryAddressSheet(profile: profile),
    );
  }

  @override
  State<DeliveryAddressSheet> createState() => _DeliveryAddressSheetState();
}

class _DeliveryAddressSheetState extends State<DeliveryAddressSheet> {
  // WHY: Custom address inputs are managed locally inside the sheet.
  final _houseNumberCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _lgaCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  String? _customPlaceId;

  late DeliveryAddressSource _selected;

  @override
  void initState() {
    super.initState();
    _selected = _defaultSource();
  }

  @override
  void dispose() {
    _houseNumberCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _postalCtrl.dispose();
    _lgaCtrl.dispose();
    _landmarkCtrl.dispose();
    super.dispose();
  }

  DeliveryAddressSource _defaultSource() {
    // WHY: Prefer verified saved addresses before forcing custom input.
    if (widget.profile.homeAddress?.isVerified == true) {
      return DeliveryAddressSource.home;
    }
    if (widget.profile.companyAddress?.isVerified == true) {
      return DeliveryAddressSource.company;
    }
    return DeliveryAddressSource.custom;
  }

  bool _isVerified(DeliveryAddressSource source) {
    if (source == DeliveryAddressSource.home) {
      return widget.profile.homeAddress?.isVerified == true;
    }
    if (source == DeliveryAddressSource.company) {
      return widget.profile.companyAddress?.isVerified == true;
    }
    return true;
  }

  void _submit() {
    AppDebug.log(
      "DELIVERY_ADDRESS",
      "Submit tapped",
      extra: {"source": _selected.name},
    );

    if (_selected == DeliveryAddressSource.home ||
        _selected == DeliveryAddressSource.company) {
      if (!_isVerified(_selected)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Verify this address in Settings first"),
          ),
        );
        return;
      }

      Navigator.of(context).pop(
        DeliveryAddressSelection(source: _selected),
      );
      return;
    }

    if (!canVerifyAddress(
      houseNumberCtrl: _houseNumberCtrl,
      streetCtrl: _streetCtrl,
      cityCtrl: _cityCtrl,
      stateCtrl: _stateCtrl,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter house number, street, city, and state"),
        ),
      );
      return;
    }

    final address = buildAddressFromControllers(
      houseNumberCtrl: _houseNumberCtrl,
      streetCtrl: _streetCtrl,
      cityCtrl: _cityCtrl,
      stateCtrl: _stateCtrl,
      postalCtrl: _postalCtrl,
      lgaCtrl: _lgaCtrl,
      landmarkCtrl: _landmarkCtrl,
    );

    if (address == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a delivery address first")),
      );
      return;
    }

    Navigator.of(context).pop(
      DeliveryAddressSelection(
        source: DeliveryAddressSource.custom,
        customAddress: address,
        placeId: _customPlaceId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final homeVerified = widget.profile.homeAddress?.isVerified == true;
    final companyVerified = widget.profile.companyAddress?.isVerified == true;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Delivery address",
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              RadioListTile<DeliveryAddressSource>(
                value: DeliveryAddressSource.home,
                groupValue: _selected,
                onChanged: homeVerified
                    ? (value) {
                        if (value == null) return;
                        setState(() => _selected = value);
                      }
                    : null,
                title: const Text("Home address"),
                subtitle: Text(
                  homeVerified
                      ? "Verified and ready for checkout"
                      : "Verify your home address in Settings",
                ),
              ),
              RadioListTile<DeliveryAddressSource>(
                value: DeliveryAddressSource.company,
                groupValue: _selected,
                onChanged: companyVerified
                    ? (value) {
                        if (value == null) return;
                        setState(() => _selected = value);
                      }
                    : null,
                title: const Text("Company address"),
                subtitle: Text(
                  companyVerified
                      ? "Verified and ready for checkout"
                      : "Verify your company address in Settings",
                ),
              ),
              RadioListTile<DeliveryAddressSource>(
                value: DeliveryAddressSource.custom,
                groupValue: _selected,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selected = value);
                },
                title: const Text("One-time address"),
                subtitle: const Text("Use a delivery address for this order"),
              ),
              if (_selected == DeliveryAddressSource.custom) ...[
                const SizedBox(height: 12),
                AddressAutocompleteField(
                  label: "Search address",
                  hint: "Start typing to autofill",
                  sourceTag: "custom",
                  houseNumberCtrl: _houseNumberCtrl,
                  streetCtrl: _streetCtrl,
                  cityCtrl: _cityCtrl,
                  stateCtrl: _stateCtrl,
                  postalCtrl: _postalCtrl,
                  lgaCtrl: _lgaCtrl,
                  landmarkCtrl: _landmarkCtrl,
                  onPlaceSelected: (placeId, _) {
                    AppDebug.log(
                      "DELIVERY_ADDRESS",
                      "Custom address selected",
                      extra: {"placeId": placeId},
                    );
                    _customPlaceId = placeId;
                  },
                ),
                const SizedBox(height: 12),
                _AddressField(
                  controller: _houseNumberCtrl,
                  label: "House number",
                ),
                const SizedBox(height: 10),
                _AddressField(
                  controller: _streetCtrl,
                  label: "Street",
                ),
                const SizedBox(height: 10),
                _AddressField(
                  controller: _cityCtrl,
                  label: "City",
                ),
                const SizedBox(height: 10),
                _AddressField(
                  controller: _stateCtrl,
                  label: "State",
                ),
                const SizedBox(height: 10),
                _AddressField(
                  controller: _postalCtrl,
                  label: "Postal code (optional)",
                ),
                const SizedBox(height: 10),
                _AddressField(
                  controller: _lgaCtrl,
                  label: "LGA (optional)",
                ),
                const SizedBox(height: 10),
                _AddressField(
                  controller: _landmarkCtrl,
                  label: "Landmark (optional)",
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        AppDebug.log(
                          "DELIVERY_ADDRESS",
                          "Cancel tapped",
                        );
                        Navigator.of(context).pop();
                      },
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: const Text("Continue"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _AddressField({
    required this.controller,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
    );
  }
}
