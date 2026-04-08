/// lib/app/features/home/presentation/business_team_screen.dart
/// ------------------------------------------------------------
/// WHAT:
/// - Business team roles screen for staff/tenant assignments.
///
/// WHY:
/// - Lets owners promote NIN-verified customers to staff or tenants.
/// - Supports estate-scoped roles for property operations.
///
/// HOW:
/// - Looks up a user by email/phone.
/// - Assigns role via /business/users/:id/role.
/// - Fetches estate assets for scoped assignments.
/// ------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_bottom_nav.dart';
import 'package:frontend/app/features/home/presentation/business_profile_action.dart';
import 'package:frontend/app/features/home/presentation/business_staff_compensation_section.dart';
import 'package:frontend/app/features/home/presentation/business_staff_routes.dart';
import 'package:frontend/app/features/home/presentation/business_team_lookup_invite_cards.dart';
import 'package:frontend/app/features/home/presentation/business_team_providers.dart';
import 'package:frontend/app/features/home/presentation/business_team_user.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/theme/app_spacing.dart';

// WHY: Centralize staff directory copy to avoid inline strings.
const String _staffDirectoryLabel = "Open staff directory";
const String _staffDirectoryTap = "staff_directory_open";

class BusinessTeamScreen extends ConsumerStatefulWidget {
  const BusinessTeamScreen({super.key});

  @override
  ConsumerState<BusinessTeamScreen> createState() => _BusinessTeamScreenState();
}

class _BusinessTeamScreenState extends ConsumerState<BusinessTeamScreen> {
  BusinessTeamUser? _foundUser;
  String? _roleError;

  String _selectedRole = "staff";
  bool _scopeToEstate = false;
  String? _selectedEstateId;
  bool _isRoleUpdating = false;

  @override
  void dispose() {
    super.dispose();
  }

  void _logTap(String action, {Map<String, dynamic>? extra}) {
    AppDebug.log("BUSINESS_TEAM", "Tap", extra: {"action": action, ...?extra});
  }

  Future<void> _assignRole() async {
    if (_foundUser == null) return;

    _logTap(
      "role_assign_start",
      extra: {"role": _selectedRole, "hasEstate": _selectedEstateId != null},
    );

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      setState(() => _roleError = "Session expired. Please sign in again.");
      return;
    }

    if (_selectedRole == "tenant" && _selectedEstateId == null) {
      setState(() => _roleError = "Select an estate asset for tenants.");
      return;
    }

    if (_selectedRole == "staff" &&
        _scopeToEstate &&
        _selectedEstateId == null) {
      setState(() => _roleError = "Select an estate asset for scoped staff.");
      return;
    }

    setState(() {
      _roleError = null;
      _isRoleUpdating = true;
    });

    try {
      final api = ref.read(businessTeamApiProvider);
      final updated = await api.updateUserRole(
        token: session.token,
        userId: _foundUser!.id,
        role: _selectedRole,
        estateAssetId: (_selectedRole == "tenant" || _scopeToEstate)
            ? _selectedEstateId
            : null,
      );

      setState(() {
        _foundUser = updated;
        _scopeToEstate = updated.estateAssetId != null;
        _selectedEstateId = updated.estateAssetId;
      });
    } catch (e) {
      logBusinessTeamApiFailure(
        source: "BUSINESS_TEAM",
        operation: "updateUserRole",
        requestIntent: businessTeamUpdateRoleIntent,
        requestContext: {
          "role": _selectedRole,
          "hasEstate": _selectedEstateId != null,
          "scopeToEstate": _scopeToEstate,
        },
        error: e,
      );
      setState(() => _roleError = businessTeamErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isRoleUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log("BUSINESS_TEAM", "build()");
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final estateAssetsAsync = ref.watch(
      businessAssetsProvider(
        const BusinessAssetsQuery(status: "active", page: 1, limit: 50),
      ),
    );

    final estateAssets = estateAssetsAsync.maybeWhen(
      data: (result) =>
          result.assets.where((asset) => asset.assetType == "estate").toList(),
      orElse: () => <BusinessAsset>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Team roles"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            AppDebug.log("BUSINESS_TEAM", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-dashboard');
          },
        ),
        actions: const [BusinessProfileAction(logTag: "BUSINESS_TEAM")],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Assign team roles",
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            "Find a customer by user ID, email, or phone, then assign staff or tenant access.",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                _logTap(_staffDirectoryTap);
                context.go(businessStaffDirectoryRoute);
              },
              child: const Text(_staffDirectoryLabel),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // WHY: Reuse shared lookup card to keep search behavior consistent.
          BusinessUserLookupCard(
            source: "BUSINESS_TEAM",
            showSummary: false,
            onUserChanged: (user) {
              // WHY: Keep role assignment in sync with lookup results.
              setState(() {
                _foundUser = user;
                _roleError = null;
                _selectedRole = "staff";
                _scopeToEstate = false;
                _selectedEstateId = null;
              });
            },
          ),
          const SizedBox(height: 16),
          // WHY: Inline invite form keeps staff onboarding quick.
          BusinessInviteFormCard(
            source: "BUSINESS_TEAM",
            estateAssets: estateAssets,
            estateAssetsLoading: estateAssetsAsync.isLoading,
          ),
          const SizedBox(height: 20),
          if (_foundUser != null) ...[
            _UserSummaryCard(user: _foundUser!),
            const SizedBox(height: 16),
            _buildRoleSection(
              estateAssets: estateAssets,
              colorScheme: colorScheme,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          // WHY: Keep compensation edits accessible without expanding the role form.
          const BusinessStaffCompensationSection(),
        ],
      ),
      bottomNavigationBar: BusinessBottomNav(
        currentIndex: 2,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  Widget _buildRoleSection({
    required List<BusinessAsset> estateAssets,
    required ColorScheme colorScheme,
  }) {
    final user = _foundUser!;
    final isEligible = user.isNinVerified && user.role == "customer";
    final hasEstateSelection = _selectedEstateId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Assign role", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (!user.isNinVerified)
          Text(
            "User must be NIN verified before role upgrade.",
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          )
        else if (user.role != "customer")
          Text(
            "Only customers can be upgraded. Current role: ${user.role}.",
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        const SizedBox(height: 12),
        RadioListTile<String>(
          value: "staff",
          groupValue: _selectedRole,
          onChanged: !_isRoleUpdating && isEligible
              ? (value) {
                  if (value == null) return;
                  _logTap("role_select", extra: {"role": value});
                  setState(() => _selectedRole = value);
                }
              : null,
          title: const Text("Staff (business-wide)"),
          subtitle: const Text("Manage products, orders, and assets."),
        ),
        RadioListTile<String>(
          value: "tenant",
          groupValue: _selectedRole,
          onChanged: !_isRoleUpdating && isEligible
              ? (value) {
                  if (value == null) return;
                  _logTap("role_select", extra: {"role": value});
                  setState(() => _selectedRole = value);
                }
              : null,
          title: const Text("Tenant (estate-specific)"),
          subtitle: const Text("Access only the selected estate."),
        ),
        const SizedBox(height: 12),
        if (_selectedRole == "staff") ...[
          SwitchListTile(
            value: _scopeToEstate,
            onChanged: !_isRoleUpdating && isEligible
                ? (value) {
                    _logTap("estate_scope_toggle", extra: {"enabled": value});
                    setState(() => _scopeToEstate = value);
                  }
                : null,
            title: const Text("Limit staff to an estate"),
            subtitle: const Text("Optional for estate operations."),
          ),
        ],
        if (_selectedRole == "tenant" || _scopeToEstate) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedEstateId,
            decoration: const InputDecoration(labelText: "Estate asset"),
            items: estateAssets
                .map(
                  (asset) => DropdownMenuItem(
                    value: asset.id,
                    child: Text(asset.name),
                  ),
                )
                .toList(),
            onChanged: !_isRoleUpdating && isEligible
                ? (value) {
                    _logTap("estate_select", extra: {"assetId": value});
                    setState(() => _selectedEstateId = value);
                  }
                : null,
          ),
          const SizedBox(height: 8),
          if (estateAssets.isEmpty)
            Text(
              "No estate assets available. Create an estate asset first.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
        if (_roleError != null) ...[
          const SizedBox(height: 8),
          // WHY: Surface role assignment errors close to the action button.
          Text(
            _roleError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed:
                (!_isRoleUpdating &&
                    isEligible &&
                    (_selectedRole != "tenant" || hasEstateSelection) &&
                    (!_scopeToEstate || hasEstateSelection))
                ? _assignRole
                : null,
            child: Text(_isRoleUpdating ? "Updating..." : "Assign role"),
          ),
        ),
      ],
    );
  }

  void _handleNavTap(BuildContext context, int index) {
    AppDebug.log("BUSINESS_TEAM", "Bottom nav tapped", extra: {"index": index});
    switch (index) {
      case 0:
        context.go('/home');
        return;
      case 1:
        context.go('/business-products');
        return;
      case 2:
        context.go('/business-dashboard');
        return;
      case 3:
        context.go('/business-orders');
        return;
      case 4:
        context.go('/chat');
        return;
      case 5:
        context.go('/settings');
        return;
    }
  }
}

class _UserSummaryCard extends StatelessWidget {
  final BusinessTeamUser user;

  const _UserSummaryCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(
              Icons.person_outline,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (user.phone != null && user.phone!.isNotEmpty)
                  Text(
                    user.phone!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          _RoleBadge(role: user.role, isVerified: user.isNinVerified),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  final bool isVerified;

  const _RoleBadge({required this.role, required this.isVerified});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final roleLabel = role.replaceAll("_", " ");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            roleLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified,
              size: 16,
              color: isVerified ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              isVerified ? "NIN verified" : "NIN required",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isVerified
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
