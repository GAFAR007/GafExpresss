/**
 * scripts/reset-razak-business-state.js
 * -------------------------------------
 * WHAT:
 * - Resets MongoDB business/user state to a clean baseline for Razak's account.
 *
 * HOW:
 * - Preserves only Razak's owner account and his core business assets/products.
 * - Deletes every other user plus chat/order/payment/history records.
 * - Removes all current staff/tenant records and production draft data.
 * - Renames Razak's estate/farm label with corrected spelling.
 * - Seeds real staff accounts from PDF notes plus added management staff.
 * - Seeds a new verified business owner (Olabode Adams) plus farm estate/assets.
 *
 * SAFETY:
 * - Dry-run by default. Pass --execute to apply changes.
 */

require("dotenv").config({ quiet: true });

const fs = require("fs");
const path = require("path");
const bcrypt = require("bcryptjs");
const mongoose = require("mongoose");

const connectDB = require("../config/db");

const User = require("../models/User");
const Product = require("../models/Product");
const AuditLog = require("../models/AuditLog");
const InventoryEvent = require("../models/InventoryEvent");
const Order = require("../models/Order");
const Payment = require("../models/Payment");
const BusinessAsset = require("../models/BusinessAsset");
const BusinessAnalyticsEvent = require("../models/BusinessAnalyticsEvent");
const BusinessTenantApplication = require("../models/BusinessTenantApplication");
const BusinessInvite = require("../models/BusinessInvite");
const PreorderReservation = require("../models/PreorderReservation");
const BusinessStaffProfile = require("../models/BusinessStaffProfile");
const { PurchaseRequest } = require("../models/PurchaseRequest");
const ProductionPlan = require("../models/ProductionPlan");
const ProductionPhase = require("../models/ProductionPhase");
const ProductionTask = require("../models/ProductionTask");
const ProductionOutput = require("../models/ProductionOutput");
const PlanUnit = require("../models/PlanUnit");
const ProductionPhaseUnitCompletion = require("../models/ProductionPhaseUnitCompletion");
const LifecycleDeviationAlert = require("../models/LifecycleDeviationAlert");
const TaskProgress = require("../models/TaskProgress");
const ProductionDeviationGovernanceConfig = require("../models/ProductionDeviationGovernanceConfig");
const ProductionUnitTaskSchedule = require("../models/ProductionUnitTaskSchedule");
const ProductionUnitScheduleWarning = require("../models/ProductionUnitScheduleWarning");
const StaffAttendance = require("../models/StaffAttendance");
const StaffCompensation = require("../models/StaffCompensation");
const ChatConversation = require("../models/ChatConversation");
const ChatParticipant = require("../models/ChatParticipant");
const ChatMessage = require("../models/ChatMessage");
const ChatAttachment = require("../models/ChatAttachment");
const ChatReadReceipt = require("../models/ChatReadReceipt");

const PRESERVED_EMAIL = "razakgafar98@outlook.com";
const PRESERVED_BUSINESS_NAME = "Gafars eXpress";
const PRESERVED_ESTATE_NAME = "Gafar Estate";
const DEFAULT_SEEDED_PASSWORD = "Test1234!";
const ADMIN_EMAIL = "razakgafar1998@outlook.com";
const ADMIN_PHONE = "08000000501";
const ADMIN_COMPANY_NAME = "Gafars eXpress Platform Admin";

const STAFF_EMAIL_DOMAIN = "gafarhydroponyfarmfarm.com";
const OLABODE_EMAIL = "olabodeadams@gafarhydroponyfarmfarm.com";
const OLABODE_PHONE = "+2348000000200";
const OLABODE_COMPANY_NAME = "Olabode's Estate";
const OLABODE_FARM_LABEL = "Olabode's Estate";
const OLABODE_VERIFICATION_REF = "SEEDED-OLABODE-ADAMS-001";

const STAFF_SEEDS = [
  {
    firstName: "Odey",
    middleName: "Muses",
    lastName: "Ipo",
    phone: "08028859764",
    staffRole: "farmer",
    note: "Handles the greenhouse. Seeded from Notes_260401_195317 (2).pdf.",
  },
  {
    firstName: "Yauba",
    lastName: "Adamu",
    phone: "07036739876",
    staffRole: "security",
    note: "Security staff. Seeded from Notes_260401_195317 (2).pdf.",
  },
  {
    firstName: "Muhammad",
    middleName: "Umar",
    lastName: "Ribadu",
    phone: "08061417170",
    staffRole: "security",
    note: "Second security staff. Seeded from Notes_260401_195317 (2).pdf.",
  },
  {
    firstName: "Munirudeen",
    lastName: "Abdulrafeu",
    phone: "09165495739",
    staffRole: "logistics_driver",
    note: "Driver for the farm. Seeded from Notes_260401_195317 (2).pdf.",
  },
  {
    firstName: "Dr",
    middleName: "Akin",
    lastName: "Akinleye",
    phone: "08000000301",
    staffRole: "farm_manager",
    note: "Farm manager added by request.",
  },
  {
    firstName: "Gafar",
    middleName: "Temitayo",
    lastName: "Razak",
    email: "temitayogafar@gmail.com",
    phone: "08000000302",
    staffRole: "estate_manager",
    note: "Estate manager added by request.",
  },
  {
    firstName: "Kudirat",
    lastName: "Gafar",
    email: "kudirat.gafar@gafarhydroponyfarmfarm.com",
    phone: "08000000303",
    staffRole: "lawyer",
    note: "Lawyer and shareholder added by request.",
  },
  {
    firstName: "Sherifat",
    lastName: "Gafar",
    email: "sherifat.gafar@gafarhydroponyfarmfarm.com",
    phone: "08000000304",
    staffRole: "shareholder",
    note: "Shareholder added by request.",
  },
  {
    firstName: "Kemi",
    lastName: "Gafar",
    email: "kemi.gafar@gafarhydroponyfarmfarm.com",
    phone: "08000000305",
    staffRole: "quality_control_manager",
    note: "Shareholder and quality control manager added by request.",
  },
  {
    firstName: "Abdulateef",
    middleName: "Femi",
    lastName: "Gafar",
    email: "abdulateef.femi.gafar@gafarhydroponyfarmfarm.com",
    phone: "08000000306",
    staffRole: "shareholder",
    note: "Shareholder added by request.",
  },
];

const ESTATE_LINKED_STAFF_ROLES = new Set([
  "estate_manager",
  "security",
  "maintenance_technician",
  "field_agent",
  "farm_manager",
  "farmer",
  "cleaner",
  "logistics_driver",
  "quality_control_manager",
]);

const CUSTOMER_SEEDS = [
  {
    firstName: "Amina",
    lastName: "Bello",
    email: "amina.bello@gafarsexpress.example",
    phone: "08000000401",
    verificationState: "verified",
    address: {
      houseNumber: "14",
      street: "Adetokunbo Ademola Crescent",
      city: "Wuse",
      state: "FCT",
      postalCode: "900288",
      formattedAddress:
        "14 Adetokunbo Ademola Crescent, Wuse, FCT, Nigeria",
    },
  },
  {
    firstName: "Chinedu",
    lastName: "Okafor",
    email: "chinedu.okafor@gafarsexpress.example",
    phone: "08000000402",
    verificationState: "verified",
    address: {
      houseNumber: "7",
      street: "Allen Avenue",
      city: "Ikeja",
      state: "Lagos",
      postalCode: "100271",
      formattedAddress: "7 Allen Avenue, Ikeja, Lagos, Nigeria",
    },
  },
  {
    firstName: "Esther",
    lastName: "Adeyemi",
    email: "esther.adeyemi@gafarsexpress.example",
    phone: "08000000403",
    verificationState: "verified",
    address: {
      houseNumber: "22",
      street: "Olusegun Obasanjo Way",
      city: "Abeokuta",
      state: "Ogun",
      postalCode: "110101",
      formattedAddress:
        "22 Olusegun Obasanjo Way, Abeokuta, Ogun, Nigeria",
    },
  },
  {
    firstName: "Kemi",
    lastName: "Lawson",
    email: "kemi.lawson@gafarsexpress.example",
    phone: "08000000404",
    verificationState: "nin_pending",
    address: {
      houseNumber: "5",
      street: "Bodija Close",
      city: "Ibadan",
      state: "Oyo",
      postalCode: "200221",
      formattedAddress: "5 Bodija Close, Ibadan, Oyo, Nigeria",
    },
  },
  {
    firstName: "Ibrahim",
    lastName: "Musa",
    email: "ibrahim.musa@gafarsexpress.example",
    phone: "08000000405",
    verificationState: "nin_pending",
    address: {
      houseNumber: "9",
      street: "Sani Abacha Road",
      city: "Kano",
      state: "Kano",
      postalCode: "700211",
      formattedAddress: "9 Sani Abacha Road, Kano, Kano, Nigeria",
    },
  },
  {
    firstName: "Zainab",
    lastName: "Salisu",
    email: "zainab.salisu@gafarsexpress.example",
    phone: "08000000406",
    verificationState: "phone_pending",
    address: {
      houseNumber: "18",
      street: "Rumuola Road",
      city: "Port Harcourt",
      state: "Rivers",
      postalCode: "500272",
      formattedAddress:
        "18 Rumuola Road, Port Harcourt, Rivers, Nigeria",
    },
  },
  {
    firstName: "Tunde",
    lastName: "Alao",
    email: "tunde.alao@gafarsexpress.example",
    phone: "08000000407",
    verificationState: "unverified",
    address: {
      houseNumber: "3",
      street: "Unity Estate Road",
      city: "Ilorin",
      state: "Kwara",
      postalCode: "240281",
      formattedAddress: "3 Unity Estate Road, Ilorin, Kwara, Nigeria",
    },
  },
];

const OLABODE_ASSET_SEEDS = [
  { name: "Solar Panels", assetType: "equipment", quantity: 2, unit: "panels", farmCategory: "utilities", farmSubcategory: "solar_panel", farmSection: "Power yard" },
  { name: "Solar Pump", assetType: "equipment", quantity: 1, unit: "unit", farmCategory: "irrigation", farmSubcategory: "solar_pump", farmSection: "Irrigation bay" },
  { name: "Vigilamp Solar Lights", assetType: "equipment", quantity: 2, unit: "lights", farmCategory: "utilities", farmSubcategory: "solar_light", farmSection: "Power yard" },
  { name: "Rain Gun Irrigation Heads", assetType: "equipment", quantity: 2, unit: "heads", farmCategory: "irrigation", farmSubcategory: "rain_gun", farmSection: "Irrigation bay" },
  { name: "Weed Mulch Rolls", assetType: "inventory_asset", quantity: 5, unit: "rolls", farmCategory: "inputs", farmSubcategory: "weed_mulch", farmSection: "Input store" },
  { name: "Knapsack Power Sprayer", assetType: "equipment", quantity: 1, unit: "sprayer", farmCategory: "tools", farmSubcategory: "knapsack_sprayer", farmSection: "Tool room" },
  { name: "Pressure Washer", assetType: "equipment", quantity: 1, unit: "unit", farmCategory: "tools", farmSubcategory: "pressure_washer", farmSection: "Workshop" },
  { name: "Hyundai Wood-Cutting Machines", assetType: "equipment", quantity: 2, unit: "machines", farmCategory: "machinery", farmSubcategory: "wood_cutter", farmSection: "Workshop" },
  { name: "Greenhouse Carpet", assetType: "equipment", quantity: 1, unit: "roll", farmCategory: "tools", farmSubcategory: "greenhouse_carpet", farmSection: "Greenhouse" },
  { name: "Fencing Wire", assetType: "inventory_asset", quantity: 1, unit: "coil", farmCategory: "security", farmSubcategory: "fencing_wire", farmSection: "Perimeter store" },
  { name: "Fencing Net", assetType: "inventory_asset", quantity: 1, unit: "roll", farmCategory: "security", farmSubcategory: "fencing_net", farmSection: "Perimeter store" },
  { name: "Greenhouse Iron Bed Frames", assetType: "equipment", quantity: 7, unit: "frames", farmCategory: "greenhouse", farmSubcategory: "bed_frame", farmSection: "Greenhouse" },
  { name: "CCTV Cameras", assetType: "equipment", quantity: 3, unit: "cameras", farmCategory: "security", farmSubcategory: "cctv", farmSection: "Security control" },
  { name: "Water Pumps", assetType: "equipment", quantity: 2, unit: "pumps", farmCategory: "irrigation", farmSubcategory: "water_pump", farmSection: "Irrigation bay" },
  { name: "Water Pump Hoses", assetType: "equipment", quantity: 2, unit: "hoses", farmCategory: "irrigation", farmSubcategory: "hose", farmSection: "Irrigation bay" },
  { name: "Arisetech Soil Conditioner", assetType: "inventory_asset", quantity: 1, unit: "pack", farmCategory: "inputs", farmSubcategory: "soil_conditioner", farmSection: "Input store" },
  { name: "Maize Seed Stock", assetType: "inventory_asset", quantity: 13, unit: "kg", farmCategory: "inputs", farmSubcategory: "seeds", farmSection: "Input store" },
  { name: "NPK 15-15-15 Fertiliser", assetType: "inventory_asset", quantity: 7, unit: "bags", farmCategory: "inputs", farmSubcategory: "fertiliser", farmSection: "Input store" },
  { name: "NPK 12-12-12 Fertiliser", assetType: "inventory_asset", quantity: 2, unit: "bags", farmCategory: "inputs", farmSubcategory: "fertiliser", farmSection: "Input store" },
  { name: "Indorama Granular Urea", assetType: "inventory_asset", quantity: 5, unit: "bags", farmCategory: "inputs", farmSubcategory: "urea", farmSection: "Input store" },
  { name: "Potassium Nitrate", assetType: "inventory_asset", quantity: 10, unit: "bags", farmCategory: "inputs", farmSubcategory: "fertiliser", farmSection: "Input store" },
  { name: "Magnesium Sulfate", assetType: "inventory_asset", quantity: 6, unit: "bags", farmCategory: "inputs", farmSubcategory: "fertiliser", farmSection: "Input store" },
  { name: "Calcinit Fertiliser", assetType: "inventory_asset", quantity: 2, unit: "bags", farmCategory: "inputs", farmSubcategory: "fertiliser", farmSection: "Input store" },
  { name: "Nitrabor TM Fertiliser", assetType: "inventory_asset", quantity: 4, unit: "bags", farmCategory: "inputs", farmSubcategory: "fertiliser", farmSection: "Input store" },
  { name: "Drip Tape Rolls", assetType: "equipment", quantity: 8, unit: "rolls", farmCategory: "irrigation", farmSubcategory: "drip_tape", farmSection: "Irrigation bay" },
  { name: "Pumping Machines", assetType: "equipment", quantity: 3, unit: "machines", farmCategory: "irrigation", farmSubcategory: "pump", farmSection: "Irrigation bay" },
  { name: "Drip Tape End Caps", assetType: "inventory_asset", quantity: 7, unit: "packs", farmCategory: "irrigation", farmSubcategory: "end_cap", farmSection: "Irrigation bay" },
  { name: "Nursery Plates", assetType: "equipment", quantity: 2, unit: "sets", farmCategory: "greenhouse", farmSubcategory: "nursery_plate", farmSection: "Greenhouse" },
  { name: "Grass Cutting Machines", assetType: "equipment", quantity: 3, unit: "machines", farmCategory: "tools", farmSubcategory: "grass_cutter", farmSection: "Tool room" },
  { name: "Watering Tanks", assetType: "equipment", quantity: 2, unit: "tanks", farmCategory: "irrigation", farmSubcategory: "water_tank", farmSection: "Irrigation bay" },
  { name: "Jacto Sprayers", assetType: "equipment", quantity: 3, unit: "sprayers", farmCategory: "tools", farmSubcategory: "jacto_sprayer", farmSection: "Tool room" },
  { name: "Small Sprayers", assetType: "equipment", quantity: 8, unit: "sprayers", farmCategory: "tools", farmSubcategory: "sprayer", farmSection: "Tool room" },
  { name: "Maize Machine", assetType: "equipment", quantity: 1, unit: "machine", farmCategory: "processing", farmSubcategory: "maize_machine", farmSection: "Processing shed" },
  { name: "Punch Tools", assetType: "equipment", quantity: 3, unit: "tools", farmCategory: "tools", farmSubcategory: "punch", farmSection: "Workshop" },
  { name: "Vanquish Stock", assetType: "inventory_asset", quantity: 26, unit: "litres", farmCategory: "inputs", farmSubcategory: "agrochemical", farmSection: "Input store" },
  { name: "Gaiya Powder Stock", assetType: "inventory_asset", quantity: 79, unit: "packs", farmCategory: "inputs", farmSubcategory: "powder", farmSection: "Input store" },
  { name: "Foliar Plus R Complete", assetType: "inventory_asset", quantity: 1, unit: "litre", farmCategory: "inputs", farmSubcategory: "foliar_feed", farmSection: "Input store" },
  { name: "Nabiotech Nano Biolif", assetType: "inventory_asset", quantity: 16, unit: "litres", farmCategory: "inputs", farmSubcategory: "bio_input", farmSection: "Input store" },
  { name: "Benishi", assetType: "inventory_asset", quantity: 24, unit: "litres", farmCategory: "inputs", farmSubcategory: "agrochemical", farmSection: "Input store" },
  { name: "D I Grow", assetType: "inventory_asset", quantity: 2, unit: "litres", farmCategory: "inputs", farmSubcategory: "growth_booster", farmSection: "Input store" },
  { name: "Tecnocal", assetType: "inventory_asset", quantity: 1, unit: "litre", farmCategory: "inputs", farmSubcategory: "calcium_input", farmSection: "Input store" },
  { name: "Caterpillar Force", assetType: "inventory_asset", quantity: 31, unit: "packs", farmCategory: "inputs", farmSubcategory: "pest_control", farmSection: "Input store" },
  { name: "CDN Thunda", assetType: "inventory_asset", quantity: 21, unit: "packs", farmCategory: "inputs", farmSubcategory: "pest_control", farmSection: "Input store" },
  { name: "Sa'af Powder", assetType: "inventory_asset", quantity: 7, unit: "packs", farmCategory: "inputs", farmSubcategory: "powder", farmSection: "Input store" },
  { name: "Aceta Force Powder", assetType: "inventory_asset", quantity: 37, unit: "packs", farmCategory: "inputs", farmSubcategory: "powder", farmSection: "Input store" },
  { name: "Z-Force Powder", assetType: "inventory_asset", quantity: 4, unit: "packs", farmCategory: "inputs", farmSubcategory: "powder", farmSection: "Input store" },
  { name: "Desen Herbicide", assetType: "inventory_asset", quantity: 16, unit: "packs", farmCategory: "inputs", farmSubcategory: "herbicide", farmSection: "Input store" },
  { name: "Control Boxes", assetType: "equipment", quantity: 3, unit: "boxes", farmCategory: "utilities", farmSubcategory: "control_box", farmSection: "Power yard" },
  { name: "Polytwink", assetType: "inventory_asset", quantity: 2, unit: "bags", farmCategory: "inputs", farmSubcategory: "twine", farmSection: "Input store" },
  { name: "Maverick Stock", assetType: "inventory_asset", quantity: 18, unit: "packs", farmCategory: "inputs", farmSubcategory: "agrochemical", farmSection: "Input store" },
  { name: "Fieldklear", assetType: "inventory_asset", quantity: 7, unit: "litres", farmCategory: "inputs", farmSubcategory: "herbicide", farmSection: "Input store" },
  { name: "Automotive and Tractor Spares", assetType: "inventory_asset", quantity: 2, unit: "sets", farmCategory: "machinery", farmSubcategory: "spares", farmSection: "Workshop" },
  { name: "Changeover Switch", assetType: "equipment", quantity: 1, unit: "switch", farmCategory: "utilities", farmSubcategory: "changeover_switch", farmSection: "Power yard" },
  { name: "Clutch Main Pressure Plates", assetType: "inventory_asset", quantity: 2, unit: "plates", farmCategory: "machinery", farmSubcategory: "tractor_spares", farmSection: "Workshop" },
  { name: "Bosch Tool Units", assetType: "equipment", quantity: 2, unit: "units", farmCategory: "tools", farmSubcategory: "bosch_tools", farmSection: "Workshop" },
  { name: "Flow Max Control Unit", assetType: "equipment", quantity: 1, unit: "unit", farmCategory: "utilities", farmSubcategory: "flow_control", farmSection: "Power yard" },
  { name: "Gardena Units", assetType: "equipment", quantity: 4, unit: "units", farmCategory: "irrigation", farmSubcategory: "gardena", farmSection: "Irrigation bay" },
  { name: "Snake Stopper", assetType: "inventory_asset", quantity: 1, unit: "pack", farmCategory: "security", farmSubcategory: "snake_control", farmSection: "Security control" },
  { name: "Haifa Bonus NPK 20-20-20", assetType: "inventory_asset", quantity: 1, unit: "pack", farmCategory: "inputs", farmSubcategory: "fertiliser", farmSection: "Input store" },
  { name: "Agriful Stock", assetType: "inventory_asset", quantity: 5, unit: "units", farmCategory: "inputs", farmSubcategory: "agrochemical", farmSection: "Input store" },
  { name: "DD Force", assetType: "inventory_asset", quantity: 1, unit: "unit", farmCategory: "inputs", farmSubcategory: "agrochemical", farmSection: "Input store" },
  { name: "Mesh 130 Micron Filter", assetType: "equipment", quantity: 1, unit: "filter", farmCategory: "irrigation", farmSubcategory: "filter_mesh", farmSection: "Irrigation bay" },
  { name: "Imi Force", assetType: "inventory_asset", quantity: 1, unit: "unit", farmCategory: "inputs", farmSubcategory: "agrochemical", farmSection: "Input store" },
  { name: "Horiver Sticky Cards", assetType: "inventory_asset", quantity: 1, unit: "pack", farmCategory: "inputs", farmSubcategory: "sticky_card", farmSection: "Input store" },
  { name: "Sam Sam", assetType: "inventory_asset", quantity: 1, unit: "bag", farmCategory: "inputs", farmSubcategory: "agrochemical", farmSection: "Input store" },
  { name: "Super Chlor", assetType: "inventory_asset", quantity: 1, unit: "pack", farmCategory: "inputs", farmSubcategory: "water_treatment", farmSection: "Input store" },
  { name: "Sharp Shooter", assetType: "inventory_asset", quantity: 1, unit: "litre", farmCategory: "inputs", farmSubcategory: "agrochemical", farmSection: "Input store" },
  { name: "Magic Force", assetType: "inventory_asset", quantity: 1, unit: "litre", farmCategory: "inputs", farmSubcategory: "agrochemical", farmSection: "Input store" },
  { name: "Polly Feed Foliar 20-20-20", assetType: "inventory_asset", quantity: 1, unit: "bag", farmCategory: "inputs", farmSubcategory: "foliar_feed", farmSection: "Input store" },
  { name: "Yoro Live Nitrabor TM", assetType: "inventory_asset", quantity: 1, unit: "bag", farmCategory: "inputs", farmSubcategory: "fertiliser", farmSection: "Input store" },
];

const args = process.argv.slice(2);
const shouldExecute = args.includes("--execute");

function slugify(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/^\.+|\.+$/g, "");
}

function joinNameParts(parts) {
  return parts
    .map((value) => (typeof value === "string" ? value.trim() : ""))
    .filter(Boolean)
    .join(" ");
}

function buildEmail({ firstName, middleName, lastName, domain }) {
  const left = [firstName, middleName, lastName]
    .map((part) => slugify(part))
    .filter(Boolean)
    .join(".");
  return `${left || "user"}@${domain}`;
}

function lastFourDigits(value) {
  const digits = String(value || "").replace(/\D+/g, "");
  return digits.slice(-4) || null;
}

function buildVerifiedAddress({
  houseNumber,
  street,
  city,
  state,
  postalCode = "",
  country = "Nigeria",
  formattedAddress,
}) {
  return {
    houseNumber,
    street,
    city,
    state,
    postalCode,
    country,
    isVerified: true,
    verifiedAt: new Date(),
    verificationSource: "manual_seed",
    formattedAddress,
  };
}

function buildSeedAddress(address, { isVerified }) {
  if (!address || typeof address !== "object") {
    return null;
  }

  return {
    houseNumber: address.houseNumber,
    street: address.street,
    city: address.city,
    state: address.state,
    postalCode: address.postalCode || "",
    country: "Nigeria",
    isVerified,
    verifiedAt: isVerified ? new Date() : null,
    verificationSource: isVerified ? "manual_seed" : "",
    formattedAddress: address.formattedAddress,
  };
}

function buildAssetActorSnapshot(user) {
  return {
    userId: user._id,
    name: user.name,
    actorRole: user.role,
    staffRole: "",
    email: user.email,
  };
}

function buildBackupPath() {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const dir = path.join(__dirname, "..", "tmp");
  fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, `reset-razak-business-state.${timestamp}.json`);
}

function unwrapDeleteResult(result) {
  return result?.deletedCount || 0;
}

async function collectSummary(preservedUserId) {
  const [userCount, productCount, assetCount, staffCount, tenantAppCount] =
    await Promise.all([
      User.countDocuments({}),
      Product.countDocuments({}),
      BusinessAsset.countDocuments({}),
      BusinessStaffProfile.countDocuments({}),
      BusinessTenantApplication.countDocuments({}),
    ]);

  return {
    userCount,
    productCount,
    assetCount,
    staffCount,
    tenantAppCount,
    preservedBusinessProducts: await Product.countDocuments({
      businessId: preservedUserId,
    }),
    preservedBusinessAssets: await BusinessAsset.countDocuments({
      businessId: preservedUserId,
      deletedAt: null,
    }),
    preservedDraftPlans: await ProductionPlan.countDocuments({
      businessId: preservedUserId,
      status: "draft",
    }),
    totalOrders: await Order.countDocuments({}),
    totalPayments: await Payment.countDocuments({}),
    totalChats: await ChatConversation.countDocuments({}),
    totalPurchaseRequests: await PurchaseRequest.countDocuments({}),
  };
}

async function main() {
  await connectDB();

  const preservedUser = await User.findOne({
    email: PRESERVED_EMAIL.toLowerCase(),
  });
  const preservedAdmin = await User.findOne({
    email: ADMIN_EMAIL.toLowerCase(),
  });

  if (!preservedUser) {
    throw new Error(`Preserved user not found for ${PRESERVED_EMAIL}`);
  }

  const preservedEstate = await BusinessAsset.findOne({
    businessId: preservedUser._id,
    assetType: "estate",
    deletedAt: null,
  }).sort({ createdAt: 1 });

  if (!preservedEstate) {
    throw new Error("No estate asset found for preserved business");
  }

  const before = await collectSummary(preservedUser._id);
  const backupPath = buildBackupPath();
  const preview = {
    shouldExecute,
    preservedUser: {
      id: String(preservedUser._id),
      email: preservedUser.email,
      name: preservedUser.name,
      companyName: preservedUser.companyName || null,
    },
    preservedEstate: {
      id: String(preservedEstate._id),
      name: preservedEstate.name,
    },
    adminAccount: {
      id: preservedAdmin ? String(preservedAdmin._id) : null,
      email: ADMIN_EMAIL,
      name: "Razak Temitayo Gafar",
      role: "admin",
    },
    before,
    staffToSeed: STAFF_SEEDS.map((seed) => ({
      name: joinNameParts([seed.firstName, seed.middleName, seed.lastName]),
      staffRole: seed.staffRole,
      phone: seed.phone,
      email: seed.email || buildEmail({ ...seed, domain: STAFF_EMAIL_DOMAIN }),
    })),
    customersToSeed: CUSTOMER_SEEDS.map((seed) => ({
      name: joinNameParts([seed.firstName, seed.lastName]),
      email: seed.email,
      verificationState: seed.verificationState,
    })),
    olabode: {
      email: OLABODE_EMAIL,
      companyName: OLABODE_COMPANY_NAME,
      farmAssetCount: OLABODE_ASSET_SEEDS.length,
    },
  };

  fs.writeFileSync(backupPath, JSON.stringify(preview, null, 2));

  console.log("Reset summary preview:", preview);
  console.log("Preview written to:", backupPath);

  if (!shouldExecute) {
    console.log("Dry run only. Re-run with --execute to apply the reset.");
    return;
  }

  const deleted = {};

  deleted.chatReadReceipts = unwrapDeleteResult(await ChatReadReceipt.deleteMany({}));
  deleted.chatAttachments = unwrapDeleteResult(await ChatAttachment.deleteMany({}));
  deleted.chatMessages = unwrapDeleteResult(await ChatMessage.deleteMany({}));
  deleted.chatParticipants = unwrapDeleteResult(await ChatParticipant.deleteMany({}));
  deleted.chatConversations = unwrapDeleteResult(await ChatConversation.deleteMany({}));

  deleted.purchaseRequests = unwrapDeleteResult(await PurchaseRequest.deleteMany({}));
  deleted.payments = unwrapDeleteResult(await Payment.deleteMany({}));
  deleted.orders = unwrapDeleteResult(await Order.deleteMany({}));
  deleted.preorderReservations = unwrapDeleteResult(await PreorderReservation.deleteMany({}));

  deleted.businessTenantApplications = unwrapDeleteResult(
    await BusinessTenantApplication.deleteMany({})
  );
  deleted.businessInvites = unwrapDeleteResult(await BusinessInvite.deleteMany({}));
  deleted.staffAttendance = unwrapDeleteResult(await StaffAttendance.deleteMany({}));
  deleted.staffCompensation = unwrapDeleteResult(await StaffCompensation.deleteMany({}));

  deleted.inventoryEvents = unwrapDeleteResult(await InventoryEvent.deleteMany({}));
  deleted.auditLogs = unwrapDeleteResult(await AuditLog.deleteMany({}));
  deleted.analyticsEvents = unwrapDeleteResult(
    await BusinessAnalyticsEvent.deleteMany({})
  );

  deleted.productionPhaseUnitCompletions = unwrapDeleteResult(
    await ProductionPhaseUnitCompletion.deleteMany({})
  );
  deleted.planUnits = unwrapDeleteResult(await PlanUnit.deleteMany({}));
  deleted.productionTasks = unwrapDeleteResult(await ProductionTask.deleteMany({}));
  deleted.productionPhases = unwrapDeleteResult(await ProductionPhase.deleteMany({}));
  deleted.productionOutputs = unwrapDeleteResult(await ProductionOutput.deleteMany({}));
  deleted.lifecycleDeviationAlerts = unwrapDeleteResult(
    await LifecycleDeviationAlert.deleteMany({})
  );
  deleted.taskProgress = unwrapDeleteResult(await TaskProgress.deleteMany({}));
  deleted.productionGovernanceConfigs = unwrapDeleteResult(
    await ProductionDeviationGovernanceConfig.deleteMany({})
  );
  deleted.productionUnitSchedules = unwrapDeleteResult(
    await ProductionUnitTaskSchedule.deleteMany({})
  );
  deleted.productionScheduleWarnings = unwrapDeleteResult(
    await ProductionUnitScheduleWarning.deleteMany({})
  );
  deleted.productionPlans = unwrapDeleteResult(await ProductionPlan.deleteMany({}));

  deleted.staffProfiles = unwrapDeleteResult(await BusinessStaffProfile.deleteMany({}));

  deleted.productsOutsidePreservedBusiness = unwrapDeleteResult(
    await Product.deleteMany({ businessId: { $ne: preservedUser._id } })
  );
  deleted.businessAssetsOutsidePreservedBusiness = unwrapDeleteResult(
    await BusinessAsset.deleteMany({ businessId: { $ne: preservedUser._id } })
  );
  deleted.usersOutsidePreservedBusiness = unwrapDeleteResult(
    await User.deleteMany({
      _id: {
        $nin: [
          preservedUser._id,
          ...(preservedAdmin ? [preservedAdmin._id] : []),
        ],
      },
    })
  );

  await User.updateOne(
    { _id: preservedUser._id },
    {
      $set: {
        companyName: PRESERVED_BUSINESS_NAME,
      },
    }
  );

  await BusinessAsset.updateOne(
    { _id: preservedEstate._id },
    { $set: { name: PRESERVED_ESTATE_NAME } }
  );

  await BusinessAsset.updateMany(
    { businessId: preservedUser._id, "farmProfile.attachedFarmLabel": { $exists: true } },
    {
      $set: {
        "farmProfile.attachedFarmLabel": PRESERVED_ESTATE_NAME,
        "farmProfile.pendingAuditRequest": null,
        "farmProfile.productionUsageRequests": [],
      },
    }
  );

  const passwordHash = await bcrypt.hash(DEFAULT_SEEDED_PASSWORD, 10);
  const adminId = preservedAdmin?._id || new mongoose.Types.ObjectId();
  const adminUser = await User.findOneAndUpdate(
    { _id: adminId },
    {
      $set: {
        name: "Razak Temitayo Gafar",
        firstName: "Razak",
        middleName: "Temitayo",
        lastName: "Gafar",
        email: ADMIN_EMAIL,
        phone: ADMIN_PHONE,
        passwordHash,
        role: "admin",
        businessId: null,
        estateAssetId: null,
        accountType: "personal",
        companyName: ADMIN_COMPANY_NAME,
        isActive: true,
        isEmailVerified: true,
        isPhoneVerified: true,
        isNinVerified: true,
        ninLast4: lastFourDigits(ADMIN_PHONE),
      },
      $unset: {
        companyEmail: "",
        companyPhone: "",
        companyAddress: "",
        homeAddress: "",
        businessRegisteredAddress: "",
      },
    },
    {
      new: true,
      upsert: true,
      setDefaultsOnInsert: true,
    }
  );
  const createdStaff = [];
  const createdCustomers = [];
  const now = new Date();

  for (const staffSeed of STAFF_SEEDS) {
    const userId = new mongoose.Types.ObjectId();
    const fullName = joinNameParts([
      staffSeed.firstName,
      staffSeed.middleName,
      staffSeed.lastName,
    ]);
    const email = buildEmail({
      firstName: staffSeed.firstName,
      middleName: staffSeed.middleName,
      lastName: staffSeed.lastName,
      domain: STAFF_EMAIL_DOMAIN,
    });
    const resolvedEmail = staffSeed.email || email;
    const ninLast4 = lastFourDigits(staffSeed.phone);
    const isEstateLinkedStaff = ESTATE_LINKED_STAFF_ROLES.has(
      staffSeed.staffRole,
    );
    const assignedEstateId = isEstateLinkedStaff
      ? preservedEstate._id
      : null;
    const staffCompanyName = isEstateLinkedStaff
      ? PRESERVED_ESTATE_NAME
      : PRESERVED_BUSINESS_NAME;

    await User.create({
      _id: userId,
      name: fullName,
      firstName: staffSeed.firstName,
      middleName: staffSeed.middleName || undefined,
      lastName: staffSeed.lastName,
      email: resolvedEmail,
      phone: staffSeed.phone,
      passwordHash,
      role: "staff",
      businessId: preservedUser._id,
      estateAssetId: assignedEstateId,
      accountType: "personal",
      companyName: staffCompanyName,
      isActive: true,
      isEmailVerified: true,
      isPhoneVerified: true,
      isNinVerified: true,
      ninLast4,
    });

    await BusinessStaffProfile.create({
      userId,
      businessId: preservedUser._id,
      staffRole: staffSeed.staffRole,
      estateAssetId: assignedEstateId,
      status: "active",
      startDate: now,
      notes: staffSeed.note,
    });

    createdStaff.push({
      id: String(userId),
      name: fullName,
      email: resolvedEmail,
      staffRole: staffSeed.staffRole,
    });
  }

  for (const customerSeed of CUSTOMER_SEEDS) {
    const userId = new mongoose.Types.ObjectId();
    const fullName = joinNameParts([
      customerSeed.firstName,
      customerSeed.lastName,
    ]);
    const isFullyVerified = customerSeed.verificationState === "verified";
    const isEmailVerified =
      isFullyVerified ||
      customerSeed.verificationState === "nin_pending" ||
      customerSeed.verificationState === "phone_pending";
    const isPhoneVerified =
      isFullyVerified || customerSeed.verificationState === "nin_pending";
    const isNinVerified = isFullyVerified;

    await User.create({
      _id: userId,
      name: fullName,
      firstName: customerSeed.firstName,
      lastName: customerSeed.lastName,
      email: customerSeed.email,
      phone: customerSeed.phone,
      passwordHash,
      role: "customer",
      accountType: "personal",
      homeAddress: buildSeedAddress(customerSeed.address, {
        isVerified: isFullyVerified,
      }),
      isActive: true,
      isEmailVerified,
      isPhoneVerified,
      isNinVerified,
      ninLast4: isNinVerified ? lastFourDigits(customerSeed.phone) : null,
    });

    createdCustomers.push({
      id: String(userId),
      name: fullName,
      email: customerSeed.email,
      verificationState: customerSeed.verificationState,
    });
  }

  const olabodeId = new mongoose.Types.ObjectId();
  const olabodeAddress = buildVerifiedAddress({
    houseNumber: "1",
    street: "Olabode's Estate Road",
    city: "Abeokuta",
    state: "Ogun",
    postalCode: "110001",
    formattedAddress: "1 Olabode's Estate Road, Abeokuta, Ogun, Nigeria",
  });

  const olabodeUser = await User.create({
    _id: olabodeId,
    name: "Olabode Adams",
    firstName: "Olabode",
    lastName: "Adams",
    email: OLABODE_EMAIL,
    phone: OLABODE_PHONE,
    passwordHash,
    role: "business_owner",
    businessId: olabodeId,
    accountType: "sole_proprietorship",
    companyName: OLABODE_COMPANY_NAME,
    companyEmail: OLABODE_EMAIL,
    companyPhone: OLABODE_PHONE,
    companyRegistration: "OE-ESTATE-001",
    companyAddress: olabodeAddress,
    homeAddress: olabodeAddress,
    isActive: true,
    isEmailVerified: true,
    isPhoneVerified: true,
    isNinVerified: true,
    ninLast4: "1207",
    businessVerificationStatus: "verified",
    businessVerificationSource: "manual_seed",
    businessVerificationRef: OLABODE_VERIFICATION_REF,
    businessVerificationMessage: null,
    businessVerifiedAt: now,
    businessRegistrationNumber: "OE-ESTATE-001",
    businessRegistrationType: "BN",
    businessIncorporationDate: "2024-01-01",
    businessIndustry: "Agriculture",
    businessTaxId: "TIN-OA-001",
    businessRegisteredAddress: olabodeAddress,
    businessDirectors: [
      {
        name: "Olabode Adams",
        role: "Proprietor",
        email: OLABODE_EMAIL,
        phone: OLABODE_PHONE,
      },
    ],
  });

  const olabodeEstateId = new mongoose.Types.ObjectId();
  await BusinessAsset.create({
    _id: olabodeEstateId,
    businessId: olabodeId,
    assetType: "estate",
    ownershipType: "owned",
    assetClass: "fixed",
    name: OLABODE_FARM_LABEL,
    description: "Seeded estate for Olabode Adams.",
    status: "active",
    location: "Abeokuta, Ogun",
    currency: "NGN",
    purchaseCost: 0,
    purchaseDate: now,
    usefulLifeMonths: 240,
    salvageValue: 0,
    estate: {
      propertyAddress: {
        houseNumber: olabodeAddress.houseNumber,
        street: olabodeAddress.street,
        city: olabodeAddress.city,
        state: olabodeAddress.state,
        postalCode: olabodeAddress.postalCode,
        country: olabodeAddress.country,
      },
      unitMix: [
        {
          unitType: "Farm Plot",
          count: 1,
          rentAmount: 0,
          rentPeriod: "yearly",
        },
      ],
      tenantRules: {
        referencesMin: 1,
        referencesMax: 2,
        guarantorsMin: 1,
        guarantorsMax: 2,
        requiresNinVerified: true,
        requiresAgreementSigned: true,
      },
    },
    createdBy: olabodeId,
    updatedBy: olabodeId,
  });

  const olabodeActor = buildAssetActorSnapshot(olabodeUser);

  await BusinessAsset.insertMany(
    OLABODE_ASSET_SEEDS.map((seed) => {
      const isInventoryAsset = seed.assetType === "inventory_asset";
      return {
        businessId: olabodeId,
        assetType: seed.assetType,
        ownershipType: "owned",
        assetClass: isInventoryAsset ? "current" : "fixed",
        name: seed.name,
        description: "Seeded from Notes_260402_172037 (1).pdf.",
        status: "active",
        location: seed.farmSection,
        currency: "NGN",
        domainContext: "farm",
        purchaseCost: isInventoryAsset ? undefined : 0,
        purchaseDate: isInventoryAsset ? undefined : now,
        usefulLifeMonths: isInventoryAsset ? undefined : 60,
        salvageValue: 0,
        inventory: isInventoryAsset
          ? {
              quantity: seed.quantity,
              unitCost: 0,
              reorderLevel: 0,
              unitOfMeasure: seed.unit,
            }
          : undefined,
        farmProfile: {
          attachedFarmLabel: OLABODE_FARM_LABEL,
          farmSection: seed.farmSection,
          farmCategory: seed.farmCategory,
          farmSubcategory: seed.farmSubcategory,
          auditFrequency: isInventoryAsset ? "yearly" : "quarterly",
          lastAuditDate: now,
          quantity: seed.quantity,
          unitOfMeasure: seed.unit,
          estimatedCurrentValue: 0,
          lastAuditSubmittedBy: olabodeActor,
          lastAuditSubmittedAt: now,
          lastAuditNote: "Seeded from Olabode farm equipment note.",
          pendingAuditRequest: null,
          productionUsageRequests: [],
        },
        createdBy: olabodeId,
        updatedBy: olabodeId,
      };
    })
  );

  const after = await collectSummary(preservedUser._id);

  const verification = {
    remainingUsers: await User.countDocuments({}),
    remainingTenants: await User.countDocuments({ role: "tenant" }),
    preservedStaffProfiles: await BusinessStaffProfile.countDocuments({
      businessId: preservedUser._id,
    }),
    preservedTenantApplications: await BusinessTenantApplication.countDocuments({
      businessId: preservedUser._id,
    }),
    remainingDraftPlans: await ProductionPlan.countDocuments({
      businessId: preservedUser._id,
      status: "draft",
    }),
    renamedEstate: await BusinessAsset.findById(preservedEstate._id)
      .select("name")
      .lean(),
    olabodeUser: {
      id: String(olabodeId),
      email: olabodeUser.email,
      companyName: olabodeUser.companyName,
    },
    adminUser: {
      id: String(adminUser._id),
      email: adminUser.email,
      role: adminUser.role,
    },
  };

  console.log("Reset complete:", {
    deleted,
    admin: {
      email: ADMIN_EMAIL,
      defaultPassword: DEFAULT_SEEDED_PASSWORD,
    },
    createdStaff,
    createdCustomers,
    olabode: {
      email: OLABODE_EMAIL,
      defaultPassword: DEFAULT_SEEDED_PASSWORD,
      companyName: OLABODE_COMPANY_NAME,
      farmAssetCount: OLABODE_ASSET_SEEDS.length + 1,
    },
    after,
    verification,
  });
}

main()
  .catch((error) => {
    console.error("Reset failed:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    try {
      await mongoose.disconnect();
    } catch (_) {}
  });
