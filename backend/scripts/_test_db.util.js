/**
 * backend/scripts/_test_db.util.js
 * --------------------------------
 * WHAT:
 * - Shared helpers for selecting a reusable MongoDB test database.
 *
 * WHY:
 * - Some environments cap total collections and disallow dropDatabase.
 * - Reusing an existing test DB avoids collection growth across runs.
 *
 * HOW:
 * - Prefer a deterministic db name when it already exists.
 * - Otherwise, scan known test db patterns and pick one with required collections.
 */

const { MongoClient } = require("mongodb");

const DEFAULT_TEST_DB_NAME_PATTERN =
  /^(preorder_[a-z_]+_test|(pr|pav|pcf|prl|popl|prc|tpb|prm2?)_[a-z0-9]+_[a-z0-9]+)$/;

function buildDbUri(baseUri, dbName) {
  const uri = (baseUri || "").trim();
  if (!uri) {
    throw new Error(
      "MONGO_URI is required for tests",
    );
  }
  const parsed = new URL(uri);
  parsed.pathname = `/${dbName}`;
  return parsed.toString();
}

async function resolveReusableTestDbUri({
  baseUri,
  preferredDbName,
  requiredCollections = [],
  dbNamePattern =
    DEFAULT_TEST_DB_NAME_PATTERN,
}) {
  const normalizedBaseUri = (
    baseUri || ""
  ).trim();
  if (!normalizedBaseUri) {
    throw new Error(
      "MONGO_URI is required for tests",
    );
  }

  const preferredUri = buildDbUri(
    normalizedBaseUri,
    preferredDbName,
  );
  const requiredSet = new Set(
    requiredCollections,
  );
  if (requiredSet.size === 0) {
    return preferredUri;
  }

  const client = new MongoClient(
    normalizedBaseUri,
  );
  try {
    await client.connect();
    const dbs = (
      await client
        .db()
        .admin()
        .listDatabases()
    ).databases.map((entry) => entry.name);

    if (dbs.includes(preferredDbName)) {
      return preferredUri;
    }

    for (const name of dbs.sort().reverse()) {
      if (!dbNamePattern.test(name)) {
        continue;
      }

      const collections = await client
        .db(name)
        .listCollections(
          {},
          { nameOnly: true },
        )
        .toArray();
      const collectionNames = new Set(
        collections.map(
          (entry) => entry.name,
        ),
      );

      let hasAllCollections = true;
      for (const requiredName of requiredSet) {
        if (
          !collectionNames.has(
            requiredName,
          )
        ) {
          hasAllCollections = false;
          break;
        }
      }

      if (hasAllCollections) {
        return buildDbUri(
          normalizedBaseUri,
          name,
        );
      }
    }

    return preferredUri;
  } finally {
    await client.close();
  }
}

module.exports = {
  resolveReusableTestDbUri,
};
