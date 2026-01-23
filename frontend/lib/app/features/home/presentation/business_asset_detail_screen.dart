/// lib/app/features/home/presentation/business_asset_detail_screen.dart
/// ------------------------------------------------------------------
/// WHAT:
/// - Detail + edit screen for a single business asset.
///
/// WHY:
/// - Lets owners/staff update asset fields with full context.
/// - Keeps audits readable by surfacing immutable metadata.
///
/// HOW:
/// - Receives BusinessAsset via route `extra`.
/// - Prefills form controllers and updates via BusinessAssetApi.
/// - Logs build, taps, and API flow for traceability.
/// ------------------------------------------------------------------
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/business_asset_model.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/theme/app_theme.dart';

class BusinessAssetDetailScreen extends ConsumerStatefulWidget {
  final BusinessAsset asset;

  const BusinessAssetDetailScreen({super.key, required this.asset});

  @override
  ConsumerState<BusinessAssetDetailScreen> createState() =>
      _BusinessAssetDetailScreenState();
}

class _BusinessAssetDetailScreenState
    extends ConsumerState<BusinessAssetDetailScreen> {
  // WHY: Controllers keep user input stable across rebuilds.
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  // WHY: Track dropdown values separately for controlled updates.
  String _assetType = 'equipment';
  String _status = 'active';

  bool _isSaving = false;

  // WHY: Map API enum values to friendly labels.
  static const List<Map<String, String>> _assetTypeOptions = [
    {"value": "vehicle", "label": "Vehicle"},
    {"value": "equipment", "label": "Equipment"},
    {"value": "warehouse", "label": "Warehouse"},
    {"value": "other", "label": "Other"},
  ];

  static const List<Map<String, String>> _statusOptions = [
    {"value": "active", "label": "Active"},
    {"value": "maintenance", "label": "Maintenance"},
    {"value": "inactive", "label": "Inactive"},
  ];

  void _logFlow(String step, String message, {Map<String, dynamic>? extra}) {
    AppDebug.log(
      "BUSINESS_ASSET_DETAIL",
      "$step | $message",
      extra: extra,
    );
  }

  @override
  void initState() {
    super.initState();
    _applyAsset(widget.asset);
  }

  @override
  void dispose() {
    // WHY: Dispose controllers to prevent memory leaks.
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _serialCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _applyAsset(BusinessAsset asset) {
    // WHY: Prefill fields so the edit form starts with known values.
    _nameCtrl.text = asset.name;
    _descriptionCtrl.text = asset.description ?? '';
    _serialCtrl.text = asset.serialNumber ?? '';
    _locationCtrl.text = asset.location ?? '';
    _assetType = asset.assetType;
    _status = asset.status;
  }

  Future<void> _saveChanges() async {
    if (_isSaving) {
      _logFlow("SAVE_BLOCK", "Save ignored (already saving)");
      return;
    }

    _logFlow("SAVE_TAP", "Save tapped", extra: {"assetId": widget.asset.id});

    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid) {
      _logFlow("SAVE_BLOCK", "Missing session");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session expired. Please sign in again.")),
      );
      return;
    }

    final trimmedName = _nameCtrl.text.trim();
    if (trimmedName.isEmpty) {
      _logFlow("SAVE_BLOCK", "Missing asset name");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Asset name is required")),
      );
      return;
    }

    setState(() => _isSaving = true);

    final payload = {
      "name": trimmedName,
      "assetType": _assetType,
      "status": _status,
      "serialNumber": _serialCtrl.text.trim(),
      "location": _locationCtrl.text.trim(),
      "description": _descriptionCtrl.text.trim(),
    };

    try {
      final api = ref.read(businessAssetApiProvider);
      _logFlow("SAVE_REQUEST", "Updating asset", extra: {"assetId": widget.asset.id});
      await api.updateAsset(
        token: session.token,
        id: widget.asset.id,
        payload: payload,
      );

      // WHY: Refresh list + summary so analytics stay in sync.
      ref.invalidate(businessAssetsProvider);
      ref.invalidate(businessAssetSummaryProvider);

      if (!mounted) return;
      _logFlow("SAVE_OK", "Asset updated", extra: {"assetId": widget.asset.id});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Asset updated successfully")),
      );
    } catch (e) {
      _logFlow("SAVE_FAIL", "Asset update failed", extra: {"error": e.toString()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unable to update asset")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppDebug.log(
      "BUSINESS_ASSET_DETAIL",
      "build()",
      extra: {"assetId": widget.asset.id},
    );

    final theme = Theme.of(context);
    final statusColors = AppStatusBadgeColors.fromTheme(
      theme: theme,
      tone: _status == "active"
          ? AppStatusTone.success
          : _status == "maintenance"
          ? AppStatusTone.warning
          : AppStatusTone.neutral,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Asset details"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _logFlow("BACK_TAP", "Back tapped");
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/business-assets');
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.asset.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColors.background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _status.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColors.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Editable fields",
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: "Asset name"),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _assetType,
            decoration: const InputDecoration(labelText: "Asset type"),
            items: _assetTypeOptions
                .map(
                  (option) => DropdownMenuItem(
                    value: option["value"],
                    child: Text(option["label"] ?? ''),
                  ),
                )
                .toList(),
            onChanged: _isSaving
                ? null
                : (value) {
                    if (value == null) return;
                    _logFlow("TYPE_CHANGE", "Asset type changed", extra: {"type": value});
                    setState(() => _assetType = value);
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: "Status"),
            items: _statusOptions
                .map(
                  (option) => DropdownMenuItem(
                    value: option["value"],
                    child: Text(option["label"] ?? ''),
                  ),
                )
                .toList(),
            onChanged: _isSaving
                ? null
                : (value) {
                    if (value == null) return;
                    _logFlow("STATUS_CHANGE", "Status changed", extra: {"status": value});
                    setState(() => _status = value);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _serialCtrl,
            decoration: const InputDecoration(labelText: "Serial number"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationCtrl,
            decoration: const InputDecoration(labelText: "Location"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "Description"),
          ),
          const SizedBox(height: 20),
          Text(
            "Audit info",
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _ReadOnlyRow(label: "Created", value: _formatDate(widget.asset.createdAt)),
          const SizedBox(height: 8),
          _ReadOnlyRow(label: "Updated", value: _formatDate(widget.asset.updatedAt)),
          const SizedBox(height: 8),
          _ReadOnlyRow(
            label: "Updated by",
            value: widget.asset.updatedBy ?? "System",
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: Text(_isSaving ? "Saving..." : "Save changes"),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return "Not available";
    final date = value.toIso8601String().split('T').first;
    return date;
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
