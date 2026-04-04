#!/usr/bin/env node

require("dotenv").config();

const bcrypt = require("bcryptjs");
const mongoose = require("mongoose");
const User = require("../models/User");

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PASSWORD_REGEX =
  /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$/;

async function main() {
  const [emailArg, passwordArg] = process.argv.slice(2);
  const email = typeof emailArg === "string" ? emailArg.trim().toLowerCase() : "";
  const password = typeof passwordArg === "string" ? passwordArg : "";

  if (!email || !password) {
    throw new Error(
      "Usage: node scripts/reset-user-password.js <email> <new-password>",
    );
  }

  if (!process.env.MONGO_URI) {
    throw new Error("MONGO_URI is required");
  }

  if (!EMAIL_REGEX.test(email)) {
    throw new Error("Please provide a valid email address");
  }

  if (!PASSWORD_REGEX.test(password)) {
    throw new Error(
      "Password must be 8+ chars with upper, lower, number, and symbol",
    );
  }

  await mongoose.connect(process.env.MONGO_URI);

  try {
    const user = await User.findOne({ email });

    if (!user) {
      throw new Error(`User not found for email: ${email}`);
    }

    user.passwordHash = await bcrypt.hash(password, 10);
    await user.save();

    console.log(
      JSON.stringify(
        {
          message: "Password reset successful",
          email: user.email,
          userId: String(user._id),
          role: user.role,
        },
        null,
        2,
      ),
    );
  } finally {
    await mongoose.disconnect();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
