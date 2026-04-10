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
  return _ownerEquivalentStaffRoles.contains(
    (staffRole ?? "").trim().toLowerCase(),
  );
}

bool canManageSellerRequests({required String? role, String? staffRole}) {
  final normalizedRole = (role ?? "").trim().toLowerCase();
  if (normalizedRole == "business_owner") {
    return true;
  }
  if (normalizedRole != "staff") {
    return false;
  }
  return _sellerRequestStaffRoles.contains(
    (staffRole ?? "").trim().toLowerCase(),
  );
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
    (staffRole ?? "").trim().toLowerCase(),
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
    (staffRole ?? "").trim().toLowerCase(),
  );
}
