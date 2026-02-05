/// lib/app/features/home/presentation/business_staff_directory_constants.dart
/// -----------------------------------------------------------------------
/// WHAT:
/// - Shared constants for the staff directory screen.
///
/// WHY:
/// - Keeps screen files short and consistent.
/// - Avoids inline strings and magic numbers.
///
/// HOW:
/// - Exposes copy, log keys, and shared query config.
library;

import 'package:frontend/app/features/home/presentation/business_asset_providers.dart';

const String staffDirectoryLogTag = "STAFF_DIRECTORY";
const String staffDirectoryLogBuild = "build()";
const String staffDirectoryLogBackTap = "back_tap";
const String staffDirectoryLogBackPop = "back_pop";
const String staffDirectoryLogBackFallback = "back_fallback";
const String staffDirectoryLogFilterChange = "filter_change";
const String staffDirectoryLogFilterClear = "filter_clear";
const String staffDirectoryLogRetryStaff = "retry_staff";
const String staffDirectoryLogRetryAssets = "retry_assets";
const String staffDirectoryLogRefresh = "refresh";
const String staffDirectoryLogAllValue = "all";
const String staffDirectoryLogCanPopKey = "canPop";
const String staffDirectoryLogRoleKey = "role";
const String staffDirectoryLogStatusKey = "status";
const String staffDirectoryLogEstateKey = "estate";

const String staffDirectoryTitle = "Staff directory";
const String staffDirectoryHelper =
    "View and manage your staff by estate, role, and status.";
const String staffDirectoryDashboardRoute = "/business-dashboard";
const String staffDirectoryRefreshSource = "staff_directory_refresh";

const int staffDirectoryAssetsPage = 1;
const int staffDirectoryAssetsLimit = 100;
const BusinessAssetsQuery staffDirectoryAssetsQuery = BusinessAssetsQuery(
  page: staffDirectoryAssetsPage,
  limit: staffDirectoryAssetsLimit,
);
