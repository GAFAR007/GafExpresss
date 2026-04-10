library;

const Set<String> _buyerRoles = {"customer", "tenant", "business_owner"};
const Set<String> _ownerEquivalentStaffRoles = {"shareholder"};
const Set<String> _sellerRequestStaffRoles = {
  "farm_manager",
  "estate_manager",
  "customer_care",
};
const Set<String> _sellerRequestInvoiceStaffRoles = {
  "farm_manager",
  "estate_manager",
  "customer_care",
};
const Set<String> _sellerRequestFulfillmentStaffRoles = {
  "farm_manager",
  "estate_manager",
};
const Set<String> _tenantInviteStaffRoles = {"shareholder", "estate_manager"};

String _normalizeStaffRole(String? staffRole) {
  return (staffRole ?? "").trim().toLowerCase().replaceAll(
    RegExp(r"[-\s]+"),
    "_",
  );
}

bool isBuyerRole(String? role) {
  return _buyerRoles.contains((role ?? "").trim().toLowerCase());
}

bool isStaffRole(String? role) {
  return (role ?? "").trim().toLowerCase() == "staff";
}

bool canUseBusinessOwnerEquivalentAccess({
  required String? role,
  String? staffRole,
}) {
  final normalizedRole = (role ?? "").trim().toLowerCase();
  if (normalizedRole == "business_owner") {
    return true;
  }
  if (normalizedRole != "staff") {
    return false;
  }
  return _ownerEquivalentStaffRoles.contains(_normalizeStaffRole(staffRole));
}

bool canSendTenantInvites({required String? role, String? staffRole}) {
  final normalizedRole = (role ?? "").trim().toLowerCase();
  if (normalizedRole == "business_owner") {
    return true;
  }
  if (normalizedRole != "staff") {
    return false;
  }
  return _tenantInviteStaffRoles.contains(_normalizeStaffRole(staffRole));
}

bool canManageSellerRequests({required String? role, String? staffRole}) {
  final normalizedRole = (role ?? "").trim().toLowerCase();
  if (normalizedRole == "business_owner") {
    return true;
  }
  if (normalizedRole != "staff") {
    return false;
  }
  return _sellerRequestStaffRoles.contains(_normalizeStaffRole(staffRole));
}

bool canSendSellerRequestInvoice({required String? role, String? staffRole}) {
  final normalizedRole = (role ?? "").trim().toLowerCase();
  if (normalizedRole == "business_owner") {
    return true;
  }
  if (normalizedRole != "staff") {
    return false;
  }
  return _sellerRequestInvoiceStaffRoles.contains(
    _normalizeStaffRole(staffRole),
  );
}

bool canManageSellerRequestFulfillment({
  required String? role,
  String? staffRole,
}) {
  final normalizedRole = (role ?? "").trim().toLowerCase();
  if (normalizedRole == "business_owner") {
    return true;
  }
  if (normalizedRole != "staff") {
    return false;
  }
  return _sellerRequestFulfillmentStaffRoles.contains(
    _normalizeStaffRole(staffRole),
  );
}
