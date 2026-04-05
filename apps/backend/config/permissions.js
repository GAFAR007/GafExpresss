/**
 * apps/backend/config/permissions.js
 * ---------------------------------
 * WHAT:
 * - Central permission map for staff roles and business modules.
 *
 * WHY:
 * - Enforces a single source of truth for role → module → capability rules.
 * - Prevents permission drift across routes/controllers.
 *
 * HOW:
 * - Defines modules + capabilities as constants.
 * - Maps each staffRole to allowed capabilities per module.
 * - Exposes helpers to evaluate access checks.
 */

// WHY: Keep module names consistent across middleware + routes.
const PERMISSION_MODULES = {
  ASSETS: 'assets',
  TENANTS: 'tenants',
  PAYMENTS: 'payments',
  REPORTS: 'reports',
  PAYROLL: 'payroll',
};

// WHY: Capabilities map directly to the staff matrix.
const PERMISSION_CAPABILITIES = {
  VIEW: 'view',
  MANAGE: 'manage',
  APPROVE: 'approve',
  VERIFY: 'verify',
};

// WHY: Centralize staff role names to avoid typos.
const STAFF_ROLES = {
  ASSET_MANAGER: 'asset_manager',
  FARM_MANAGER: 'farm_manager',
  ESTATE_MANAGER: 'estate_manager',
  ACCOUNTANT: 'accountant',
  FIELD_AGENT: 'field_agent',
  CLEANER: 'cleaner',
  FARMER: 'farmer',
  INVENTORY_KEEPER: 'inventory_keeper',
  AUDITOR: 'auditor',
  SECURITY: 'security',
  MAINTENANCE_TECHNICIAN: 'maintenance_technician',
  LOGISTICS_DRIVER: 'logistics_driver',
};

// WHY: Keep user role values centralized for access checks.
const USER_ROLES = {
  OWNER: 'business_owner',
  STAFF: 'staff',
};

// WHY: Keep arrays small and readable for auditability.
const ROLE_PERMISSIONS = {
  [STAFF_ROLES.ASSET_MANAGER]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.MANAGE,
      PERMISSION_CAPABILITIES.VIEW,
      PERMISSION_CAPABILITIES.APPROVE,
    ],
    [PERMISSION_MODULES.TENANTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.PAYMENTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.REPORTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.FARM_MANAGER]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.MANAGE,
      PERMISSION_CAPABILITIES.VIEW,
      PERMISSION_CAPABILITIES.APPROVE,
    ],
    [PERMISSION_MODULES.TENANTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.REPORTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.ESTATE_MANAGER]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.MANAGE,
      PERMISSION_CAPABILITIES.VIEW,
      PERMISSION_CAPABILITIES.APPROVE,
    ],
    [PERMISSION_MODULES.TENANTS]: [
      PERMISSION_CAPABILITIES.VIEW,
      PERMISSION_CAPABILITIES.APPROVE,
      PERMISSION_CAPABILITIES.VERIFY,
    ],
    [PERMISSION_MODULES.PAYMENTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.REPORTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.PAYROLL]: [
      PERMISSION_CAPABILITIES.MANAGE,
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.ACCOUNTANT]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.TENANTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.PAYMENTS]: [
      PERMISSION_CAPABILITIES.MANAGE,
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.REPORTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.PAYROLL]: [
      PERMISSION_CAPABILITIES.MANAGE,
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.FIELD_AGENT]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.TENANTS]: [
      PERMISSION_CAPABILITIES.VERIFY,
    ],
  },
  [STAFF_ROLES.CLEANER]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.FARMER]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.REPORTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.INVENTORY_KEEPER]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.MANAGE,
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.REPORTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.AUDITOR]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.TENANTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.PAYMENTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.REPORTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.SECURITY]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.TENANTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.MAINTENANCE_TECHNICIAN]: {
    // WHY: Repairs are treated as manage access to assets.
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.MANAGE,
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
  [STAFF_ROLES.LOGISTICS_DRIVER]: {
    [PERMISSION_MODULES.ASSETS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
    [PERMISSION_MODULES.REPORTS]: [
      PERMISSION_CAPABILITIES.VIEW,
    ],
  },
};

// WHY: Business owners should never be blocked by staff role rules.
function isOwnerRole(role) {
  return role === USER_ROLES.OWNER;
}

// WHY: Resolve allowed capabilities for a given staff role.
function getRolePermissions(staffRole) {
  return ROLE_PERMISSIONS[staffRole] || {};
}

// WHY: Central access check so middleware stays simple.
function hasPermission({ actorRole, staffRole, module, capability }) {
  if (isOwnerRole(actorRole)) {
    return true;
  }

  if (actorRole !== USER_ROLES.STAFF) {
    return false;
  }

  const permissions = getRolePermissions(staffRole);
  const allowed = permissions[module] || [];
  return allowed.includes(capability);
}

module.exports = {
  PERMISSION_MODULES,
  PERMISSION_CAPABILITIES,
  STAFF_ROLES,
  ROLE_PERMISSIONS,
  USER_ROLES,
  hasPermission,
  getRolePermissions,
  isOwnerRole,
};
