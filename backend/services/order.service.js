/**
 * apps/backend/services/order.service.js
 * --------------------------------------
 * WHAT:
 * - Business logic for user orders
 *
 * WHY:
 * - Handles checkout, stock validation, and user order history
 *
 * HOW:
 * - Validates items + stock, snapshots price, creates order in a transaction
 */

const mongoose = require("mongoose");
const Order = require("../models/Order");
const Product = require("../models/Product");
const User = require("../models/User");
const {
  verifyAddressPayload,
} = require("./address_verification.service");
const debug = require("../utils/debug");

/**
 * Create a new order (checkout)
 * @param {string} userId
 * @param {Array} items - [{productId, quantity}]
 * @param {Object} deliveryAddress
 * @returns {Object} created order
 */
async function createOrder(
  userId,
  items,
  deliveryAddress
) {
  debug("ORDER SERVICE: createOrder", {
    userId,
    itemsCount: Array.isArray(items)
      ? items.length
      : 0,
    addressSource:
      deliveryAddress?.source,
  });

  if (!items || items.length === 0) {
    throw new Error(
      "Order must have at least one item"
    );
  }

  if (!deliveryAddress) {
    throw new Error(
      "Delivery address is required"
    );
  }

  const addressSource =
    deliveryAddress.source;

  if (
    addressSource !== "home" &&
    addressSource !== "company" &&
    addressSource !== "custom"
  ) {
    throw new Error(
      "Invalid delivery address source"
    );
  }

  const session =
    await mongoose.startSession();
  session.startTransaction();

  try {
    let totalPrice = 0;
    const orderItems = [];
    let deliveryAddressSnapshot = null;

    if (addressSource === "home" || addressSource === "company") {
      // WHY: Snapshot verified profile address to keep orders immutable.
      const user = await User.findById(
        userId
      )
        .select("homeAddress companyAddress")
        .lean();

      if (!user) {
        throw new Error(
          "User not found"
        );
      }

      const selected =
        addressSource === "home"
          ? user.homeAddress
          : user.companyAddress;

      if (!selected) {
        throw new Error(
          "Selected delivery address is missing"
        );
      }

      if (!selected.isVerified) {
        throw new Error(
          "Selected delivery address is not verified"
        );
      }

      deliveryAddressSnapshot = {
        source: addressSource,
        ...selected,
      };
    }

    if (addressSource === "custom") {
      // WHY: Custom addresses must be verified before checkout completes.
      const { source, placeId, ...rawAddress } = deliveryAddress;
      const result =
        await verifyAddressPayload({
          address: rawAddress,
          source: "custom",
          placeId,
        });

      if (!result.address?.isVerified) {
        throw new Error(
          "Delivery address must be verified"
        );
      }

      deliveryAddressSnapshot = {
        source: "custom",
        ...result.address,
      };
    }

    if (!deliveryAddressSnapshot) {
      throw new Error(
        "Delivery address snapshot could not be created"
      );
    }

    for (const item of items) {
      const product =
        await Product.findById(
          item.productId
        ).session(session);

      if (!product) {
        throw new Error(
          `Product not found: ${item.productId}`
        );
      }

      // Enhanced checks
      if (product.deletedAt) {
        throw new Error(
          `Product is deleted: ${item.productId}`
        );
      }
      if (!product.isActive) {
        throw new Error(
          `Product is inactive: ${item.productId}`
        );
      }
      if (item.quantity <= 0) {
        throw new Error(
          `Invalid quantity for product: ${item.productId}`
        );
      }
      if (
        product.stock < item.quantity
      ) {
        throw new Error(
          `Insufficient stock for product: ${item.productId}`
        );
      }

      // WHY: Snapshot price now; stock is deducted ONLY on payment success.
      const itemPrice =
        product.price * item.quantity;
      totalPrice += itemPrice;

      orderItems.push({
        product: item.productId,
        quantity: item.quantity,
        price: product.price, // per unit snapshot
      });
    }

    const order = new Order({
      user: userId,
      items: orderItems,
      totalPrice,
      deliveryAddress: deliveryAddressSnapshot,
    });
    await order.save({ session });

    await session.commitTransaction();
    debug(
      "ORDER SERVICE: Order created successfully"
    );

    return order;
  } catch (err) {
    await session.abortTransaction();
    throw err;
  } finally {
    session.endSession();
  }
}

/**
/**
 * Get orders for a specific user (paginated + searchable)
 *
 * @param {string} userId - Authenticated user's ID
 * @param {object} query - URL query params (?page, ?limit, ?q)
 *
 * WHY:
 * - Prevents returning ALL orders at once
 * - Enables search and pagination
 * - Matches product & admin patterns
 */
async function getUserOrders(
  userId,
  query
) {
  debug(
    "ORDER SERVICE: getUserOrders - entry",
    { userId, query }
  );

  /**
   * ------------------------------------
   * STEP 1: PAGINATION
   * ------------------------------------
   */
  const { page, limit, skip } =
    getPagination(query);

  /**
   * ------------------------------------
   * STEP 2: SEARCH (?q=)
   * ------------------------------------
   *
   * Allows searching orders by:
   * - status (pending, cancelled, etc)
   * - reference (if added later)
   */
  const search = query.q?.trim();

  /**
   * ------------------------------------
   * STEP 3: BASE FILTER
   * ------------------------------------
   * VERY IMPORTANT:
   * - User can ONLY see their own orders
   */
  const filter = {
    user: userId,
  };

  /**
   * Apply full-text search if provided
   */
  if (search) {
    filter.$text = { $search: search };
  }

  debug(
    "ORDER SERVICE: filter built",
    filter
  );

  /**
   * ------------------------------------
   * STEP 4: QUERY DATABASE
   * ------------------------------------
   */
  const [orders, total] =
    await Promise.all([
      Order.find(filter)
        .populate(
          "items.product",
          "name imageUrl"
        )
        .select({
          deletedAt: 0,
          deletedBy: 0,
          __v: 0,
        })
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),

      Order.countDocuments(filter),
    ]);

  debug(
    "ORDER SERVICE: orders fetched",
    {
      total,
      returned: orders.length,
      page,
      limit,
    }
  );

  /**
   * ------------------------------------
   * STEP 5: RETURN STRUCTURED RESULT
   * ------------------------------------
   */
  return {
    orders,
    total,
    page,
    limit,
  };
}

/**
 * Cancel a pending order (customer only)
 * - Only allowed if status is 'pending'
 * - Restores stock atomically
 * - Placeholder for refund logic
 *
 * @param {string} orderId
 * @param {string} userId - To verify ownership
 * @returns {Object} updated cancelled order
 */
async function cancelOrder(
  orderId,
  userId
) {
  debug("ORDER SERVICE: cancelOrder", {
    orderId,
    userId,
  });

  const session =
    await mongoose.startSession();
  session.startTransaction();

  try {
    const order = await Order.findById(
      orderId
    ).session(session);

    if (!order) {
      throw new Error(
        "Order not found"
      );
    }

    if (
      order.user.toString() !== userId
    ) {
      throw new Error(
        "Not authorized: This is not your order"
      );
    }

    if (order.status !== "pending") {
      throw new Error(
        "Can only cancel pending orders"
      );
    }

    // WHY: Stock is only adjusted on payment success, so cancel should NOT change stock.

    // Update order status
    order.status = "cancelled";
    await order.save({ session });

    // Placeholder for real refund processing
    debug(
      "REFUND PLACEHOLDER: Initiate refund for order",
      orderId
    );

    await session.commitTransaction();
    debug(
      "ORDER SERVICE: Order cancelled (no stock change)"
    );

    return order;
  } catch (err) {
    await session.abortTransaction();
    throw err;
  } finally {
    session.endSession();
  }
}

// EXPORT ALL FUNCTIONS
module.exports = {
  createOrder,
  getUserOrders,
  cancelOrder, // ← THIS WAS MISSING!
};
