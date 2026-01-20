/// lib/app/features/home/presentation/settings/widgets/address_autocomplete_field.dart
/// ---------------------------------------------------------------------------
/// WHAT:
/// - Reusable address autocomplete field that fills structured controllers.
///
/// WHY:
/// - Provides Google-powered suggestions without exposing API keys.
/// - Helps users fill addresses faster and with fewer errors.
///
/// HOW:
/// - Calls backend autocomplete + place details endpoints.
/// - Applies selected address to the provided controllers.
/// - Debounces input to reduce API calls.
/// ---------------------------------------------------------------------------
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/auth/domain/models/user_profile.dart';
import 'package:frontend/app/features/home/presentation/address_autocomplete_api.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/settings/settings_address_helpers.dart';

class AddressAutocompleteField extends ConsumerStatefulWidget {
  final String label;
  final String hint;
  final String sourceTag;
  final TextEditingController houseNumberCtrl;
  final TextEditingController streetCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController stateCtrl;
  final TextEditingController postalCtrl;
  final TextEditingController lgaCtrl;
  final TextEditingController landmarkCtrl;
  final void Function(String placeId, UserAddress address)? onPlaceSelected;

  const AddressAutocompleteField({
    super.key,
    required this.label,
    required this.hint,
    required this.sourceTag,
    required this.houseNumberCtrl,
    required this.streetCtrl,
    required this.cityCtrl,
    required this.stateCtrl,
    required this.postalCtrl,
    required this.lgaCtrl,
    required this.landmarkCtrl,
    this.onPlaceSelected,
  });

  @override
  ConsumerState<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState
    extends ConsumerState<AddressAutocompleteField> {
  final _searchCtrl = TextEditingController();
  final _debounce = Duration(milliseconds: 350);
  Timer? _debounceTimer;
  bool _isLoading = false;
  List<AddressSuggestion> _suggestions = [];

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    _debounceTimer?.cancel();

    if (query.length < 3) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }

    _debounceTimer = Timer(_debounce, () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log(
        "ADDRESS_AUTOCOMPLETE",
        "Missing session",
        extra: {"source": widget.sourceTag},
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final api = ref.read(addressAutocompleteApiProvider);
      AppDebug.log(
        "ADDRESS_AUTOCOMPLETE",
        "Suggestions request",
        extra: {"length": query.length, "source": widget.sourceTag},
      );
      final suggestions = await api.fetchSuggestions(
        token: session.token,
        query: query,
      );

      if (!mounted) return;
      setState(() => _suggestions = suggestions);
    } catch (e) {
      AppDebug.log(
        "ADDRESS_AUTOCOMPLETE",
        "Suggestions failed",
        extra: {"error": e.toString(), "source": widget.sourceTag},
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectSuggestion(AddressSuggestion suggestion) async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      AppDebug.log(
        "ADDRESS_AUTOCOMPLETE",
        "Select blocked (missing session)",
        extra: {"source": widget.sourceTag},
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = ref.read(addressAutocompleteApiProvider);
      AppDebug.log(
        "ADDRESS_AUTOCOMPLETE",
        "Place details request",
        extra: {"source": widget.sourceTag},
      );
      final address = await api.fetchPlaceDetails(
        token: session.token,
        placeId: suggestion.placeId,
      );

      _applyAddress(address);
      widget.onPlaceSelected?.call(suggestion.placeId, address);

      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _searchCtrl.text = suggestion.description;
      });
    } catch (e) {
      AppDebug.log(
        "ADDRESS_AUTOCOMPLETE",
        "Place details failed",
        extra: {"error": e.toString(), "source": widget.sourceTag},
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyAddress(UserAddress address) {
    // WHY: Fill structured inputs with the selected place details.
    applyAddressToControllers(
      address: address,
      houseNumberCtrl: widget.houseNumberCtrl,
      streetCtrl: widget.streetCtrl,
      cityCtrl: widget.cityCtrl,
      stateCtrl: widget.stateCtrl,
      postalCtrl: widget.postalCtrl,
      lgaCtrl: widget.lgaCtrl,
      landmarkCtrl: widget.landmarkCtrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search),
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: Colors.grey.shade200,
              ),
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                return ListTile(
                  title: Text(suggestion.mainText),
                  subtitle: Text(suggestion.secondaryText),
                  onTap: () => _selectSuggestion(suggestion),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
