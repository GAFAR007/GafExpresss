/// lib/app/features/home/presentation/business_staff_directory_screen.dart
/// -------------------------------------------------------------------
/// WHAT:
/// - Business staff directory scaffold screen.
///
/// WHY:
/// - Provides a single place to list, filter, and open staff profiles.
/// - Keeps staff management visible from dashboard and team tools.
///
/// HOW:
/// - Renders header + KPI, filter, and list sections wired to providers.
/// - Logs build, navigation, and user actions for diagnostics.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/features/home/presentation/app_refresh.dart';
import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_constants.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_filters_section.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_kpi_section.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_list_section.dart';
import 'package:frontend/app/features/home/presentation/business_staff_directory_state.dart';
import 'package:frontend/app/theme/app_spacing.dart';
import 'package:frontend/app/features/home/presentation/production/production_providers.dart';

class BusinessStaffDirectoryScreen extends ConsumerWidget {
  const BusinessStaffDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // WHY: Track screen renders to debug layout and routing issues.
    AppDebug.log(staffDirectoryLogTag, staffDirectoryLogBuild);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final staffAsync = ref.watch(productionStaffProvider);
    final assetsAsync = ref.watch(
      businessAssetsProvider(staffDirectoryAssetsQuery),
    );
    final filters = ref.watch(staffDirectoryFiltersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(staffDirectoryTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // WHY: Log navigation intent so route issues are traceable.
            final canPop = context.canPop();
            AppDebug.log(
              staffDirectoryLogTag,
              staffDirectoryLogBackTap,
              extra: {staffDirectoryLogCanPopKey: canPop},
            );
            if (canPop) {
              AppDebug.log(staffDirectoryLogTag, staffDirectoryLogBackPop);
              context.pop();
              return;
            }
            AppDebug.log(staffDirectoryLogTag, staffDirectoryLogBackFallback);
            context.go(staffDirectoryDashboardRoute);
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          AppDebug.log(staffDirectoryLogTag, staffDirectoryLogRefresh);
          await AppRefresh.refreshApp(
            ref: ref,
            source: staffDirectoryRefreshSource,
          );
          // WHY: Refresh staff and estate data for this screen.
          final _ = ref.refresh(productionStaffProvider);
          final _ = ref.refresh(
            businessAssetsProvider(staffDirectoryAssetsQuery),
          );
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // WHY: Provide clear page hierarchy before modules.
            Text(
              staffDirectoryTitle,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              staffDirectoryHelper,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            StaffDirectoryKpiSection(
              staffAsync: staffAsync,
              onRetry: () {
                AppDebug.log(staffDirectoryLogTag, staffDirectoryLogRetryStaff);
                final _ = ref.refresh(productionStaffProvider);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            StaffDirectoryFiltersSection(
              filters: filters,
              assetsAsync: assetsAsync,
              onFiltersChanged: (next) {
                AppDebug.log(
                  staffDirectoryLogTag,
                  staffDirectoryLogFilterChange,
                  extra: {
                    staffDirectoryLogRoleKey:
                        next.role ?? staffDirectoryLogAllValue,
                    staffDirectoryLogStatusKey:
                        next.status ?? staffDirectoryLogAllValue,
                    staffDirectoryLogEstateKey:
                        next.estateAssetId ?? staffDirectoryLogAllValue,
                  },
                );
                ref.read(staffDirectoryFiltersProvider.notifier).state = next;
              },
              onRetryAssets: () {
                AppDebug.log(
                  staffDirectoryLogTag,
                  staffDirectoryLogRetryAssets,
                );
                final _ = ref.refresh(
                  businessAssetsProvider(staffDirectoryAssetsQuery),
                );
              },
              onClearFilters: () {
                AppDebug.log(
                  staffDirectoryLogTag,
                  staffDirectoryLogFilterClear,
                );
                ref.read(staffDirectoryFiltersProvider.notifier).state =
                    const StaffDirectoryFilters();
              },
            ),
            const SizedBox(height: AppSpacing.md),
            StaffDirectoryListSection(
              staffAsync: staffAsync,
              assetsAsync: assetsAsync,
              filters: filters,
              onRetry: () {
                AppDebug.log(staffDirectoryLogTag, staffDirectoryLogRetryStaff);
                final _ = ref.refresh(productionStaffProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}
