/**
 * scripts/backfill-business-id.js
 * --------------------------------
 * WHAT:
 * - Backfills businessId for already-verified business users.
 *
 * WHY:
 * - Older verified users may lack businessId after new multi-tenant changes.
 * - Ensures business owners are correctly scoped for future access control.
 *
 * HOW:
 * - Finds users with businessVerificationStatus=verified and missing businessId.
 * - Sets businessId to their own userId (owner scope).
 * - Promotes role to business_owner (unless admin) for verified businesses.
 */

require('dotenv').config();

const mongoose = require('mongoose');
const debug = require('../utils/debug');
const connectDB = require('../config/db');
const User = require('../models/User');

const args = process.argv.slice(2);
const isDryRun = args.includes('--dry-run');

async function run() {
  debug('BACKFILL BUSINESS ID: start', { dryRun: isDryRun });

  await connectDB();

  // WHY: Only touch verified businesses that are missing businessId.
  const candidates = await User.find({
    businessVerificationStatus: 'verified',
    $or: [{ businessId: null }, { businessId: { $exists: false } }],
  }).select('_id role businessId email businessVerificationStatus');

  debug('BACKFILL BUSINESS ID: candidates', { count: candidates.length });

  if (isDryRun) {
    console.log('Dry run only. No changes will be written.');
  }

  let updated = 0;
  let skippedAdmins = 0;

  for (const user of candidates) {
    if (user.role === 'admin') {
      // WHY: Admins are platform-wide, never force them into business scope.
      skippedAdmins += 1;
      continue;
    }

    if (!isDryRun) {
      user.businessId = user._id;
      user.role = 'business_owner';
      await user.save();
    }

    updated += 1;
    debug('BACKFILL BUSINESS ID: updated', {
      userId: user._id.toString(),
      email: user.email,
    });
  }

  console.log('Backfill complete:', {
    candidates: candidates.length,
    updated,
    skippedAdmins,
    dryRun: isDryRun,
  });

  await mongoose.disconnect();
  debug('BACKFILL BUSINESS ID: done');
}

run().catch((err) => {
  console.error('Backfill failed:', err.message);
  process.exit(1);
});
