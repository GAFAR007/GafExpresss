require("dotenv").config();

const mongoose = require("mongoose");
const Product = require("../models/Product");

async function clearProducts() {
  if (!process.env.MONGO_URI) {
    throw new Error("MONGO_URI is missing in apps/backend/.env");
  }

  await mongoose.connect(process.env.MONGO_URI);

  const beforeCount = await Product.countDocuments({});
  const result = await Product.deleteMany({});
  const afterCount = await Product.countDocuments({});

  console.log(
    JSON.stringify(
      {
        beforeCount,
        deletedCount: result.deletedCount,
        afterCount,
      },
      null,
      2,
    ),
  );

  await mongoose.disconnect();
}

clearProducts().catch(async (error) => {
  console.error(error.message);
  try {
    await mongoose.disconnect();
  } catch (_) {}
  process.exit(1);
});
