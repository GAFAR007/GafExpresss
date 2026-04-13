/// lib/app/features/home/presentation/business_tenant_model.dart
/// ----------------------------------------------------------------
/// WHAT:
/// - Models for tenant applications tied to estate assets.
///
/// WHY:
/// - Keeps tenant review parsing in one place for list + detail screens.
/// - Avoids UI widgets parsing raw JSON directly.
///
/// HOW:
/// - Maps /business/tenant/applications JSON into typed objects.
/// - Logs safe identifiers to help debug data mismatches.
/// ----------------------------------------------------------------
library;

import 'package:frontend/app/core/debug/app_debug.dart';

// WHY: Keep JSON keys centralized for tenant summary parsing.
const String _summaryRemainingPeriodsKey = "remainingPeriods";
const String _summaryTermTotalPeriodsKey = "termTotalPeriods";
const String _summaryTermPaidPeriodsKey = "termPaidPeriodsYtd";
const String _summaryTermRemainingPeriodsKey = "termRemainingPeriodsYtd";
const String _summaryIsFinalPaymentKey = "isFinalPayment";
const String _summaryIsYearCompleteKey = "isYearComplete";
const String _summaryIsOverdueKey = "isOverdue";

class TenantContact {
  final String name;
  // WHY: Store split names for clearer review displays.
  final String firstName;
  // WHY: Middle name is optional for legacy records.
  final String? middleName;
  // WHY: Last name is required for identity checks.
  final String lastName;
  // WHY: Email is required for verification contact details.
  final String email;
  // WHY: Phone is required for verification contact details.
  final String phone;
  // WHY: Optional supporting document URL for audits.
  final String? documentUrl;
  // WHY: Cloudinary id for future document cleanup.
  final String? documentPublicId;
  final String status;
  final bool isVerified;
  final DateTime? verifiedAt;
  final String? note;

  const TenantContact({
    required this.name,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.documentUrl,
    required this.documentPublicId,
    required this.status,
    required this.isVerified,
    required this.verifiedAt,
    required this.note,
  });

  factory TenantContact.fromJson(Map<String, dynamic> json) {
    return TenantContact(
      name: (json['name'] ?? '').toString(),
      firstName: (json['firstName'] ?? '').toString(),
      middleName: _optionalString(json['middleName']),
      lastName: (json['lastName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      documentUrl: _optionalString(json['documentUrl']),
      documentPublicId: _optionalString(json['documentPublicId']),
      status: (json['status'] ?? 'pending').toString(),
      isVerified: (json['isVerified'] ?? false) as bool,
      verifiedAt: _toDate(json['verifiedAt']),
      note: (json['note'] ?? '').toString(),
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static String? _optionalString(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class TenantRulesSnapshot {
  final int referencesMin;
  final int referencesMax;
  final int guarantorsMin;
  final int guarantorsMax;
  final bool requiresAgreementSigned;

  const TenantRulesSnapshot({
    required this.referencesMin,
    required this.referencesMax,
    required this.guarantorsMin,
    required this.guarantorsMax,
    required this.requiresAgreementSigned,
  });

  factory TenantRulesSnapshot.fromJson(Map<String, dynamic> json) {
    return TenantRulesSnapshot(
      referencesMin: _toInt(json['referencesMin'], fallback: 1),
      referencesMax: _toInt(json['referencesMax'], fallback: 2),
      guarantorsMin: _toInt(json['guarantorsMin'], fallback: 1),
      guarantorsMax: _toInt(json['guarantorsMax'], fallback: 2),
      requiresAgreementSigned:
          (json['requiresAgreementSigned'] ?? true) as bool,
    );
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value == null) return fallback;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? fallback;
  }
}

class TenantSnapshot {
  final String name;
  final String email;
  final String phone;
  final String ninLast4;

  const TenantSnapshot({
    required this.name,
    required this.email,
    required this.phone,
    required this.ninLast4,
  });

  factory TenantSnapshot.fromJson(Map<String, dynamic> json) {
    return TenantSnapshot(
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      ninLast4: (json['ninLast4'] ?? '').toString(),
    );
  }
}

class TenantUserStatus {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final bool isNinVerified;

  const TenantUserStatus({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.isEmailVerified,
    required this.isPhoneVerified,
    required this.isNinVerified,
  });

  factory TenantUserStatus.fromJson(Map<String, dynamic> json) {
    return TenantUserStatus(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      isEmailVerified: (json['isEmailVerified'] ?? false) as bool,
      isPhoneVerified: (json['isPhoneVerified'] ?? false) as bool,
      isNinVerified: (json['isNinVerified'] ?? false) as bool,
    );
  }
}

class TenantSummary {
  final String applicationId;
  final String status;
  final String paymentStatus;
  final String agreementStatus;
  final bool agreementSigned;
  final String agreementText;
  final DateTime? agreementAcceptedAt;
  final DateTime? paidThroughDate;
  final DateTime? nextDueDate;
  final DateTime? lastRentPaymentAt;
  final DateTime? moveInDate;
  final double rentAmount;
  final String rentPeriod;
  final String unitType;
  final int unitCount;
  final String estateAssetId;
  final TenantPaymentsSummary? paymentsSummary;
  // WHY: Allow UI to clamp payment options when backend supplies remaining span.
  final int? remainingPeriods;
  // WHY: Yearly term totals drive the "paid vs left" tenant UX.
  final int? termTotalPeriods;
  // WHY: Track how many periods have been paid this calendar year.
  final int? termPaidPeriodsYtd;
  // WHY: Remaining periods in the current calendar year.
  final int? termRemainingPeriodsYtd;
  // WHY: Identify when the last payment must complete the year.
  final bool isFinalPayment;
  // WHY: Flag when the current calendar year is fully paid.
  final bool isYearComplete;
  // WHY: Overdue status should be visible in tenant UI.
  final bool isOverdue;

  const TenantSummary({
    required this.applicationId,
    required this.status,
    required this.paymentStatus,
    required this.agreementStatus,
    required this.agreementSigned,
    required this.agreementText,
    required this.agreementAcceptedAt,
    required this.paidThroughDate,
    required this.nextDueDate,
    required this.lastRentPaymentAt,
    required this.moveInDate,
    required this.rentAmount,
    required this.rentPeriod,
    required this.unitType,
    required this.unitCount,
    required this.estateAssetId,
    required this.paymentsSummary,
    required this.remainingPeriods,
    required this.termTotalPeriods,
    required this.termPaidPeriodsYtd,
    required this.termRemainingPeriodsYtd,
    required this.isFinalPayment,
    required this.isYearComplete,
    required this.isOverdue,
  });

  factory TenantSummary.fromJson(Map<String, dynamic> json) {
    DateTime? toDate(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString());
    double toDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    int? toOptionalInt(dynamic value) {
      // WHY: Support nullable counters without throwing on missing fields.
      if (value == null) return null;
      if (value is int) return value;
      return int.tryParse(value.toString());
    }

    bool toBool(dynamic value) {
      // WHY: Default to false when flags are missing from legacy payloads.
      if (value == null) return false;
      if (value is bool) return value;
      return value.toString().toLowerCase() == "true";
    }

    return TenantSummary(
      applicationId: (json['applicationId'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      paymentStatus: (json['paymentStatus'] ?? '').toString(),
      agreementStatus: (json['agreementStatus'] ?? '').toString(),
      agreementSigned: (json['agreementSigned'] ?? false) as bool,
      agreementText: (json['agreementText'] ?? '').toString(),
      agreementAcceptedAt: toDate(json['agreementAcceptedAt']),
      paidThroughDate: toDate(json['paidThroughDate']),
      nextDueDate: toDate(json['nextDueDate']),
      lastRentPaymentAt: toDate(json['lastRentPaymentAt']),
      moveInDate: toDate(json['moveInDate']),
      rentAmount: toDouble(json['rentAmount']),
      rentPeriod: (json['rentPeriod'] ?? '').toString(),
      unitType: (json['unitType'] ?? '').toString(),
      unitCount: (json['unitCount'] is int)
          ? json['unitCount'] as int
          : int.tryParse(json['unitCount']?.toString() ?? '') ?? 0,
      estateAssetId: (json['estateAssetId'] ?? '').toString(),
      paymentsSummary: json['paymentsSummary'] == null
          ? null
          : TenantPaymentsSummary.fromJson(
              json['paymentsSummary'] as Map<String, dynamic>,
            ),
      remainingPeriods: toOptionalInt(json[_summaryRemainingPeriodsKey]),
      termTotalPeriods: toOptionalInt(json[_summaryTermTotalPeriodsKey]),
      termPaidPeriodsYtd: toOptionalInt(json[_summaryTermPaidPeriodsKey]),
      termRemainingPeriodsYtd: toOptionalInt(
        json[_summaryTermRemainingPeriodsKey],
      ),
      isFinalPayment: toBool(json[_summaryIsFinalPaymentKey]),
      isYearComplete: toBool(json[_summaryIsYearCompleteKey]),
      isOverdue: toBool(json[_summaryIsOverdueKey]),
    );
  }
}

class TenantPaymentsSummary {
  final int totalPaidKoboYtd;
  final int totalPaidKoboAllTime;
  final int paymentsThisYear;
  final DateTime? lastPaidAt;

  const TenantPaymentsSummary({
    required this.totalPaidKoboYtd,
    required this.totalPaidKoboAllTime,
    required this.paymentsThisYear,
    required this.lastPaidAt,
  });

  factory TenantPaymentsSummary.fromJson(Map<String, dynamic> json) {
    DateTime? toDate(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString());
    int toInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? 0;
    }

    return TenantPaymentsSummary(
      totalPaidKoboYtd: toInt(json['totalPaidKoboYtd']),
      totalPaidKoboAllTime: toInt(json['totalPaidKoboAllTime']),
      paymentsThisYear: toInt(json['paymentsThisYear']),
      lastPaidAt: toDate(json['lastPaidAt']),
    );
  }
}

class EstateUnitMix {
  final String unitType;
  final int count;
  final double rentAmount;
  final String rentPeriod;

  const EstateUnitMix({
    required this.unitType,
    required this.count,
    required this.rentAmount,
    required this.rentPeriod,
  });

  factory EstateUnitMix.fromJson(Map<String, dynamic> json) {
    return EstateUnitMix(
      unitType: (json['unitType'] ?? '').toString(),
      count: _toInt(json['count'], fallback: 0),
      rentAmount: _toDouble(json['rentAmount']),
      rentPeriod: (json['rentPeriod'] ?? 'monthly').toString(),
    );
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value == null) return fallback;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? fallback;
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}

class EstateAnalytics {
  final EstateAnalyticsEstate estate;
  final EstateAnalyticsTenants tenants;
  final EstateAnalyticsCollections collections;

  const EstateAnalytics({
    required this.estate,
    required this.tenants,
    required this.collections,
  });

  factory EstateAnalytics.fromJson(Map<String, dynamic> json) {
    return EstateAnalytics(
      estate: EstateAnalyticsEstate.fromJson(
        (json['estate'] ?? {}) as Map<String, dynamic>,
      ),
      tenants: EstateAnalyticsTenants.fromJson(
        (json['tenants'] ?? {}) as Map<String, dynamic>,
      ),
      collections: EstateAnalyticsCollections.fromJson(
        (json['collections'] ?? {}) as Map<String, dynamic>,
      ),
    );
  }
}

class EstateAnalyticsEstate {
  final String id;
  final String name;
  final int totalUnits;
  final int potentialAnnualKobo;

  const EstateAnalyticsEstate({
    required this.id,
    required this.name,
    required this.totalUnits,
    required this.potentialAnnualKobo,
  });

  factory EstateAnalyticsEstate.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? 0;
    }

    return EstateAnalyticsEstate(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      totalUnits: toInt(json['totalUnits']),
      potentialAnnualKobo: toInt(json['potentialAnnualKobo']),
    );
  }
}

class EstateAnalyticsTenants {
  final int active;
  final int approved;
  final int pending;
  final int dueSoon;
  final int overdue;

  const EstateAnalyticsTenants({
    required this.active,
    required this.approved,
    required this.pending,
    required this.dueSoon,
    required this.overdue,
  });

  factory EstateAnalyticsTenants.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? 0;
    }

    return EstateAnalyticsTenants(
      active: toInt(json['active']),
      approved: toInt(json['approved']),
      pending: toInt(json['pending']),
      dueSoon: toInt(json['dueSoon']),
      overdue: toInt(json['overdue']),
    );
  }
}

class EstateAnalyticsCollections {
  final int monthKobo;
  final int ytdKobo;
  final int allTimeKobo;

  const EstateAnalyticsCollections({
    required this.monthKobo,
    required this.ytdKobo,
    required this.allTimeKobo,
  });

  factory EstateAnalyticsCollections.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      return int.tryParse(value.toString()) ?? 0;
    }

    return EstateAnalyticsCollections(
      monthKobo: toInt(json['monthKobo']),
      ytdKobo: toInt(json['ytdKobo']),
      allTimeKobo: toInt(json['allTimeKobo']),
    );
  }
}

class TenantEstateSummary {
  final String id;
  final String name;
  final List<EstateUnitMix> unitMix;
  final TenantRulesSnapshot? tenantRules;

  const TenantEstateSummary({
    required this.id,
    required this.name,
    required this.unitMix,
    required this.tenantRules,
  });

  factory TenantEstateSummary.fromJson(Map<String, dynamic> json) {
    final rawUnitMix =
        (json['estate']?['unitMix'] ?? json['unitMix'] ?? []) as List<dynamic>;
    final unitMix = rawUnitMix
        .whereType<Map<String, dynamic>>()
        .map(EstateUnitMix.fromJson)
        .toList();

    final tenantRulesMap = json['estate']?['tenantRules'];
    final tenantRules = tenantRulesMap is Map<String, dynamic>
        ? TenantRulesSnapshot.fromJson(tenantRulesMap)
        : null;

    return TenantEstateSummary(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      unitMix: unitMix,
      tenantRules: tenantRules,
    );
  }
}

class BusinessTenantApplication {
  final String id;
  final String status;
  final TenantSnapshot tenantSnapshot;
  final TenantUserStatus? tenantUserStatus;
  final TenantEstateSummary? estate;
  final String requestSource;
  final String applicantFirstName;
  final String? applicantMiddleName;
  final String applicantLastName;
  final DateTime? applicantDob;
  final String applicantNinLast4;
  final String? identityDocumentUrl;
  final String? requestLinkId;
  final String unitType;
  final int unitCount;
  final double rentAmount;
  final String rentPeriod;
  final DateTime? moveInDate;
  final List<TenantContact> references;
  final List<TenantContact> guarantors;
  final String agreementStatus;
  final bool agreementSigned;
  final String agreementText;
  final DateTime? agreementAcceptedAt;
  final TenantRulesSnapshot tenantRulesSnapshot;
  final String paymentStatus;
  final DateTime? paidAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? reviewNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BusinessTenantApplication({
    required this.id,
    required this.status,
    required this.tenantSnapshot,
    required this.tenantUserStatus,
    required this.estate,
    required this.requestSource,
    required this.applicantFirstName,
    required this.applicantMiddleName,
    required this.applicantLastName,
    required this.applicantDob,
    required this.applicantNinLast4,
    required this.identityDocumentUrl,
    required this.requestLinkId,
    required this.unitType,
    required this.unitCount,
    required this.rentAmount,
    required this.rentPeriod,
    required this.moveInDate,
    required this.references,
    required this.guarantors,
    required this.agreementStatus,
    required this.agreementSigned,
    required this.agreementText,
    required this.agreementAcceptedAt,
    required this.tenantRulesSnapshot,
    required this.paymentStatus,
    required this.paidAt,
    required this.reviewedAt,
    required this.reviewedBy,
    required this.reviewNotes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BusinessTenantApplication.fromJson(Map<String, dynamic> json) {
    final id = (json['_id'] ?? json['id'] ?? '').toString();
    AppDebug.log('BUSINESS_TENANT_MODEL', 'fromJson()', extra: {'id': id});

    final rawReferences = (json['references'] ?? []) as List<dynamic>;
    final references = rawReferences
        .whereType<Map<String, dynamic>>()
        .map(TenantContact.fromJson)
        .toList();

    final rawGuarantors = (json['guarantors'] ?? []) as List<dynamic>;
    final guarantors = rawGuarantors
        .whereType<Map<String, dynamic>>()
        .map(TenantContact.fromJson)
        .toList();

    final tenantSnapshotMap = json['tenantSnapshot'];
    final tenantSnapshot = tenantSnapshotMap is Map<String, dynamic>
        ? TenantSnapshot.fromJson(tenantSnapshotMap)
        : const TenantSnapshot(name: '', email: '', phone: '', ninLast4: '');

    final tenantUserMap = json['tenantUserId'];
    final tenantUserStatus = tenantUserMap is Map<String, dynamic>
        ? TenantUserStatus.fromJson(tenantUserMap)
        : null;

    final estateMap = json['estateAssetId'];
    final estate = estateMap is Map<String, dynamic>
        ? TenantEstateSummary.fromJson(estateMap)
        : null;

    final applicantDob = _parseDate(json['applicantDob']);
    final rulesMap = json['tenantRulesSnapshot'];
    final tenantRulesSnapshot = rulesMap is Map<String, dynamic>
        ? TenantRulesSnapshot.fromJson(rulesMap)
        : const TenantRulesSnapshot(
            referencesMin: 1,
            referencesMax: 2,
            guarantorsMin: 1,
            guarantorsMax: 2,
            requiresAgreementSigned: true,
          );

    return BusinessTenantApplication(
      id: id,
      status: (json['status'] ?? '').toString(),
      tenantSnapshot: tenantSnapshot,
      tenantUserStatus: tenantUserStatus,
      estate: estate,
      requestSource: (json['requestSource'] ?? 'tenant_verification')
          .toString(),
      applicantFirstName: (json['applicantFirstName'] ?? '').toString(),
      applicantMiddleName: _optionalString(json['applicantMiddleName']),
      applicantLastName: (json['applicantLastName'] ?? '').toString(),
      applicantDob: applicantDob,
      applicantNinLast4: (json['applicantNinLast4'] ?? '').toString(),
      identityDocumentUrl: _optionalString(json['identityDocumentUrl']),
      requestLinkId: _optionalString(json['requestLinkId']),
      unitType: (json['unitType'] ?? '').toString(),
      unitCount: _toInt(json['unitCount'], fallback: 1),
      rentAmount: _toDouble(json['rentAmount']),
      rentPeriod: (json['rentPeriod'] ?? 'monthly').toString(),
      moveInDate: _parseDate(json['moveInDate']),
      references: references,
      guarantors: guarantors,
      agreementStatus: (json['agreementStatus'] ?? '').toString(),
      agreementSigned: (json['agreementSigned'] ?? false) as bool,
      agreementText: (json['agreementText'] ?? '').toString(),
      agreementAcceptedAt: _parseDate(json['agreementAcceptedAt']),
      tenantRulesSnapshot: tenantRulesSnapshot,
      paymentStatus: (json['paymentStatus'] ?? 'unpaid').toString(),
      paidAt: _parseDate(json['paidAt']),
      reviewedAt: _parseDate(json['reviewedAt']),
      reviewedBy: (json['reviewedBy'] ?? '').toString(),
      reviewNotes: (json['reviewNotes'] ?? '').toString(),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value == null) return fallback;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? fallback;
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static String? _optionalString(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
