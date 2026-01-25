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
import 'package:frontend/app/features/home/presentation/business_team_providers.dart';
import 'package:frontend/app/features/home/presentation/business_team_user.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';

class BusinessTeamScreen extends ConsumerStatefulWidget {
  const BusinessTeamScreen({super.key});

  @override
  ConsumerState<BusinessTeamScreen> createState() =>
      _BusinessTeamScreenState();
}

class _BusinessTeamScreenState extends ConsumerState<BusinessTeamScreen> {
  final _lookupCtrl = TextEditingController();
  String _lookupMode = "email";
  bool _isLookupLoading = false;
  BusinessTeamUser? _foundUser;
  String? _lookupError;

  String _selectedRole = "staff";
  bool _scopeToEstate = false;
  String? _selectedEstateId;
  bool _isRoleUpdating = false;
  bool _isInviteSending = false;

  @override
  void dispose() {
    _lookupCtrl.dispose();
    super.dispose();
  }

  void _logTap(String action, {Map<String, dynamic>? extra}) {
    AppDebug.log("BUSINESS_TEAM", "Tap", extra: {
      "action": action,
      ...?extra,
    });
  }

  Future<void> _lookupUser() async {
    final query = _lookupCtrl.text.trim();
    _logTap("lookup_start", extra: {"mode": _lookupMode});

    if (query.isEmpty) {
      setState(
        () => _lookupError = "Enter a user ID, email, or phone number.",
      );
      return;
    }

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      setState(() => _lookupError = "Session expired. Please sign in again.");
      return;
    }

    setState(() {
      _lookupError = null;
      _isLookupLoading = true;
    });

    try {
      final api = ref.read(businessTeamApiProvider);
      final user = await api.lookupUser(
        token: session.token,
        userId: _lookupMode == "id" ? query : null,
        email: _lookupMode == "email" ? query : null,
        phone: _lookupMode == "phone" ? query : null,
      );

      setState(() {
        _foundUser = user;
        _selectedRole = "staff";
        _scopeToEstate = false;
        _selectedEstateId = null;
      });
    } catch (e) {
      setState(() {
        _foundUser = null;
        _lookupError = _extractError(e);
      });
    } finally {
      if (mounted) {
        setState(() => _isLookupLoading = false);
      }
    }
  }

  Future<void> _assignRole() async {
    if (_foundUser == null) return;

    _logTap("role_assign_start", extra: {
      "role": _selectedRole,
      "hasEstate": _selectedEstateId != null,
    });

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      setState(() => _lookupError = "Session expired. Please sign in again.");
      return;
    }

    if (_selectedRole == "tenant" && _selectedEstateId == null) {
      setState(() => _lookupError = "Select an estate asset for tenants.");
      return;
    }

    if (_selectedRole == "staff" && _scopeToEstate && _selectedEstateId == null) {
      setState(() => _lookupError = "Select an estate asset for scoped staff.");
      return;
    }

    setState(() {
      _lookupError = null;
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
      setState(() => _lookupError = _extractError(e));
    } finally {
      if (mounted) {
        setState(() => _isRoleUpdating = false);
      }
    }
  }

  Future<void> _openInviteSheet({
    required List<BusinessAsset> estateAssets,
  }) async {
    _logTap("invite_sheet_open");

    final emailCtrl = TextEditingController();
    String role = "staff";
    String? estateAssetId;
    String? localError;
    bool isSending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final viewInsets = MediaQuery.of(context).viewInsets;
            return Padding(
              padding: EdgeInsets.only(bottom: viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Send invite link",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Invite a customer by email to join your team.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "Invitee email",
                        hintText: "user@email.com",
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: role,
                      decoration: const InputDecoration(
                        labelText: "Role",
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: "staff",
                          child: Text("Staff"),
                        ),
                        DropdownMenuItem(
                          value: "tenant",
                          child: Text("Tenant"),
                        ),
                      ],
                      onChanged: isSending
                          ? null
                          : (value) {
                              if (value == null) return;
                              setSheetState(() {
                                role = value;
                                if (role != "tenant") {
                                  estateAssetId = null;
                                }
                              });
                            },
                    ),
                    if (role == "tenant") ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: estateAssetId,
                        decoration: const InputDecoration(
                          labelText: "Estate asset",
                        ),
                        items: estateAssets
                            .map(
                              (asset) => DropdownMenuItem(
                                value: asset.id,
                                child: Text(asset.name),
                              ),
                            )
                            .toList(),
                        onChanged: isSending
                            ? null
                            : (value) {
                                setSheetState(() => estateAssetId = value);
                              },
                      ),
                    ],
                    if (localError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        localError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSending
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                  },
                            child: const Text("Cancel"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSending
                                ? null
                                : () async {
                                    final email =
                                        emailCtrl.text.trim().toLowerCase();
                                    if (email.isEmpty) {
                                      setSheetState(() {
                                        localError =
                                            "Enter an email address.";
                                      });
                                      return;
                                    }
                                    if (role == "tenant" &&
                                        estateAssetId == null) {
                                      setSheetState(() {
                                        localError =
                                            "Select an estate for tenant invites.";
                                      });
                                      return;
                                    }

                                    setSheetState(() {
                                      localError = null;
                                      isSending = true;
                                    });

                                    _logTap(
                                      "invite_send_start",
                                      extra: {
                                        "role": role,
                                        "hasEstate": estateAssetId != null,
                                      },
                                    );

                                    try {
                                      final session =
                                          ref.read(authSessionProvider);
                                      if (session == null ||
                                          !session.isTokenValid) {
                                        throw Exception(
                                          "Session expired. Please sign in again.",
                                        );
                                      }

                                      final api =
                                          ref.read(businessTeamApiProvider);
                                      await api.createInvite(
                                        token: session.token,
                                        email: email,
                                        role: role,
                                        estateAssetId: estateAssetId,
                                      );

                                      if (!mounted) return;
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "Invite sent to $email",
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      setSheetState(() {
                                        localError = _extractError(e);
                                        isSending = false;
                                      });
                                    }
                                  },
                            child: isSending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text("Send invite"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    emailCtrl.dispose();
  }

  String _extractError(Object error) {
    final raw = error.toString();
    if (raw.contains("User must be NIN verified")) {
      return "User must be NIN verified before role upgrade.";
    }
    if (raw.contains("User belongs to a different business")) {
      return "User already belongs to another business.";
    }
    if (raw.contains("User not found")) {
      return "No user found for that lookup.";
    }
    if (raw.contains("Invalid user id")) {
      return "Invalid user ID. Check and try again.";
    }
    if (raw.contains("Invite has expired")) {
      return "Invite link has expired. Send a new invite.";
    }
    if (raw.contains("Invite email does not match")) {
      return "Invite email does not match your account.";
    }
    if (raw.contains("Invite email is required")) {
      return "Invite email is required.";
    }
    return raw.replaceAll("Exception:", "").trim();
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
      data: (result) => result.assets
          .where((asset) => asset.assetType == "estate")
          .toList(),
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
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Assign team roles",
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Find a customer by user ID, email, or phone, then assign staff or tenant access.",
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lookupCtrl,
                  keyboardType: _lookupMode == "phone"
                      ? TextInputType.phone
                      : (_lookupMode == "email"
                          ? TextInputType.emailAddress
                          : TextInputType.text),
                  decoration: InputDecoration(
                    labelText: _lookupMode == "phone"
                        ? "Phone number"
                        : (_lookupMode == "email" ? "Email" : "User ID"),
                    hintText: _lookupMode == "phone"
                        ? "e.g. +2348012345678"
                        : (_lookupMode == "email"
                            ? "e.g. user@email.com"
                            : "e.g. 64f0c2..."),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _lookupMode,
                onChanged: _isLookupLoading
                    ? null
                    : (value) {
                        if (value == null) return;
                        _logTap("lookup_mode_change", extra: {"mode": value});
                        setState(() => _lookupMode = value);
                      },
                items: const [
                  DropdownMenuItem(
                    value: "id",
                    child: Text("User ID"),
                  ),
                  DropdownMenuItem(
                    value: "email",
                    child: Text("Email"),
                  ),
                  DropdownMenuItem(
                    value: "phone",
                    child: Text("Phone"),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLookupLoading ? null : _lookupUser,
              icon: _isLookupLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_isLookupLoading ? "Searching..." : "Find user"),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isInviteSending
                  ? null
                  : () async {
                      if (estateAssetsAsync.isLoading) {
                        setState(() {
                          _lookupError =
                              "Estate assets still loading. Try again.";
                        });
                        return;
                      }
                      setState(() => _isInviteSending = true);
                      await _openInviteSheet(estateAssets: estateAssets);
                      if (mounted) {
                        setState(() => _isInviteSending = false);
                      }
                    },
              icon: const Icon(Icons.mail_outline),
              label: const Text("Send invite link"),
            ),
          ),
          if (_lookupError != null) ...[
            const SizedBox(height: 12),
            Text(
              _lookupError!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_foundUser != null) ...[
            _UserSummaryCard(user: _foundUser!),
            const SizedBox(height: 16),
            _buildRoleSection(
              estateAssets: estateAssets,
              colorScheme: colorScheme,
            ),
          ],
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
        Text(
          "Assign role",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        if (!user.isNinVerified)
          Text(
            "User must be NIN verified before role upgrade.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
          )
        else if (user.role != "customer")
          Text(
            "Only customers can be upgraded. Current role: ${user.role}.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
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
            value: _selectedEstateId,
            decoration: const InputDecoration(
              labelText: "Estate asset",
            ),
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
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (!_isRoleUpdating &&
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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

  const _RoleBadge({
    required this.role,
    required this.isVerified,
  });

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
