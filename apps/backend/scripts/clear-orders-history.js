require("dotenv").config();

const mongoose = require("mongoose");
const InventoryEvent = require("../models/InventoryEvent");
const Order = require("../models/Order");
const Payment = require("../models/Payment");
const PreorderReservation = require("../models/PreorderReservation");

async function clearOrdersHistory() {
  if (!process.env.MONGO_URI) {
    throw new Error("MONGO_URI is missing in apps/backend/.env");
  }

  await mongoose.connect(process.env.MONGO_URI);

  const before = {
    orders: await Order.countDocuments({}),
    payments: await Payment.countDocuments({}),
    inventoryEvents: await InventoryEvent.countDocuments({}),
    preorderReservations: await PreorderReservation.countDocuments({}),
  };

  const [paymentsResult, inventoryResult, preorderResult, ordersResult] =
    await Promise.all([
      Payment.deleteMany({}),
      InventoryEvent.deleteMany({}),
      PreorderReservation.deleteMany({}),
      Order.deleteMany({}),
    ]);

  const after = {
    orders: await Order.countDocuments({}),
    payments: await Payment.countDocuments({}),
    inventoryEvents: await InventoryEvent.countDocuments({}),
    preorderReservations: await PreorderReservation.countDocuments({}),
  };

  console.log(
    JSON.stringify(
      {
        before,
        deleted: {
          orders: ordersResult.deletedCount,
          payments: paymentsResult.deletedCount,
          inventoryEvents: inventoryResult.deletedCount,
          preorderReservations: preorderResult.deletedCount,
        },
        after,
      },
      null,
      2,
    ),
  );

  await mongoose.disconnect();
}

clearOrdersHistory().catch(async (error) => {
  console.error(error.message);
  try {
    await mongoose.disconnect();
  } catch (_) {}
  process.exit(1);
});
