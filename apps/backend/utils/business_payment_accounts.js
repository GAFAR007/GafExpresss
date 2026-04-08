/**
 * apps/backend/utils/business_payment_accounts.js
 * -----------------------------------------------
 * WHAT:
 * - Shared helpers for business payment accounts used in quotations.
 *
 * WHY:
 * - Keeps validation + shaping consistent across chat and purchase requests.
 * - Avoids duplicating bank-account parsing rules in multiple services.
 */

const PAYMENT_ACCOUNT_NUMBER_DIGITS = 10;
const PAYMENT_ACCOUNT_MAX_BANK_NAME_LENGTH = 80;
const PAYMENT_ACCOUNT_MAX_ACCOUNT_NAME_LENGTH = 120;
const PAYMENT_ACCOUNT_MAX_TRANSFER_INSTRUCTION_LENGTH = 240;

function normalizeText(
  value,
  { label, required = true, maxLength = 120 } = {},
) {
  const text = (value || "").toString().trim();
  if (!text) {
    if (required) {
      throw new Error(`${label} is required`);
    }
    return "";
  }
  if (text.length > maxLength) {
    throw new Error(`${label} is too long`);
  }
  return text;
}

function normalizeAccountNumber(value) {
  const digits = (value || "").toString().replace(/\D+/g, "");
  if (!digits) {
    throw new Error("Account number is required");
  }
  if (digits.length !== PAYMENT_ACCOUNT_NUMBER_DIGITS) {
    throw new Error(
      `Account number must be ${PAYMENT_ACCOUNT_NUMBER_DIGITS} digits`,
    );
  }
  return digits;
}

function normalizeBusinessPaymentAccountInput(input = {}) {
  const source = input && typeof input === "object" ? input : {};
  return {
    accountId: (source.accountId || "").toString().trim(),
    bankName: normalizeText(source.bankName, {
      label: "Bank name",
      maxLength: PAYMENT_ACCOUNT_MAX_BANK_NAME_LENGTH,
    }),
    accountName: normalizeText(source.accountName, {
      label: "Account name",
      maxLength: PAYMENT_ACCOUNT_MAX_ACCOUNT_NAME_LENGTH,
    }),
    accountNumber: normalizeAccountNumber(source.accountNumber),
    transferInstruction: normalizeText(source.transferInstruction, {
      label: "Transfer instruction",
      maxLength: PAYMENT_ACCOUNT_MAX_TRANSFER_INSTRUCTION_LENGTH,
    }),
  };
}

function shapeBusinessPaymentAccount(account = {}) {
  const accountId = account._id || account.id || account.accountId || null;
  return {
    id: accountId ? accountId.toString() : "",
    bankName: (account.bankName || "").toString().trim(),
    accountName: (account.accountName || "").toString().trim(),
    accountNumber: (account.accountNumber || "").toString().trim(),
    transferInstruction: (account.transferInstruction || "")
      .toString()
      .trim(),
    isDefault: account.isDefault === true,
  };
}

function shapeBusinessPaymentAccounts(accounts) {
  if (!Array.isArray(accounts)) {
    return [];
  }
  return accounts
    .map(shapeBusinessPaymentAccount)
    .filter(
      (account) =>
        account.bankName &&
        account.accountName &&
        account.accountNumber &&
        account.transferInstruction,
    )
    .sort((left, right) => {
      if (left.isDefault === right.isDefault) {
        return left.bankName.localeCompare(right.bankName);
      }
      return left.isDefault ? -1 : 1;
    });
}

function businessPaymentAccountsEqual(left = {}, right = {}) {
  return (
    (left.bankName || "").toString().trim().toLowerCase() ===
      (right.bankName || "").toString().trim().toLowerCase() &&
    (left.accountName || "").toString().trim().toLowerCase() ===
      (right.accountName || "").toString().trim().toLowerCase() &&
    (left.accountNumber || "").toString().replace(/\D+/g, "") ===
      (right.accountNumber || "").toString().replace(/\D+/g, "") &&
    (left.transferInstruction || "").toString().trim() ===
      (right.transferInstruction || "").toString().trim()
  );
}

function formatBusinessPaymentInstructions(account = {}) {
  const shaped = shapeBusinessPaymentAccount(account);
  const pieces = [
    shaped.bankName ? `Bank name: ${shaped.bankName}.` : "",
    shaped.accountName ? `Account name: ${shaped.accountName}.` : "",
    shaped.accountNumber ? `Account number: ${shaped.accountNumber}.` : "",
    shaped.transferInstruction
      ? `Transfer instruction: ${shaped.transferInstruction}.`
      : "",
  ];
  return pieces.filter(Boolean).join(" ");
}

module.exports = {
  PAYMENT_ACCOUNT_NUMBER_DIGITS,
  PAYMENT_ACCOUNT_MAX_BANK_NAME_LENGTH,
  PAYMENT_ACCOUNT_MAX_ACCOUNT_NAME_LENGTH,
  PAYMENT_ACCOUNT_MAX_TRANSFER_INSTRUCTION_LENGTH,
  normalizeBusinessPaymentAccountInput,
  shapeBusinessPaymentAccount,
  shapeBusinessPaymentAccounts,
  businessPaymentAccountsEqual,
  formatBusinessPaymentInstructions,
};
