/// lib/app/features/home/presentation/purchase_request_quote_screen.dart
/// -------------------------------------------------------------------
/// WHAT:
/// - Dedicated quotation form screen for purchase requests.
///
/// WHY:
/// - Sellers need a focused workflow to build and edit customer quotations.
/// - Keeps the chat request card compact while preserving full quote controls.
///
/// HOW:
/// - Uses the existing purchase-request invoice endpoint.
/// - Computes preview totals locally while the backend remains source of truth.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/core/debug/app_debug.dart';
import 'package:frontend/app/core/formatters/currency_formatter.dart';
import 'package:frontend/app/core/formatters/date_formatter.dart';
import 'package:frontend/app/features/home/presentation/business_order_providers.dart';
import 'package:frontend/app/features/home/presentation/chat_providers.dart';
import 'package:frontend/app/features/home/presentation/order_providers.dart';
import 'package:frontend/app/features/home/presentation/presentation/providers/auth_providers.dart';
import 'package:frontend/app/features/home/presentation/purchase_request_models.dart';
import 'package:frontend/app/features/home/presentation/purchase_request_providers.dart';
import 'package:frontend/app/theme/app_colors.dart';
import 'package:frontend/app/theme/app_theme.dart';

const List<double> _sellerMarkupOptions = <double>[0, 5, 10, 15, 20];
const String _newBusinessAccountOption = "__new_business_account__";
const int _bankNameMaxLength = 80;
const int _accountNameMaxLength = 120;
const int _accountNumberLength = 10;
const int _transferInstructionMaxLength = 240;
const int _baseLogisticsMaxLength = 16;

class PurchaseRequestQuoteScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final PurchaseRequest request;

  const PurchaseRequestQuoteScreen({
    super.key,
    required this.conversationId,
    required this.request,
  });

  @override
  ConsumerState<PurchaseRequestQuoteScreen> createState() =>
      _PurchaseRequestQuoteScreenState();
}

class _PurchaseRequestQuoteScreenState
    extends ConsumerState<PurchaseRequestQuoteScreen> {
  late final TextEditingController _baseLogisticsCtrl;
  late final TextEditingController _bankNameCtrl;
  late final TextEditingController _accountNameCtrl;
  late final TextEditingController _accountNumberCtrl;
  late final TextEditingController _transferInstructionCtrl;
  late final TextEditingController _noteCtrl;
  late double _sellerMarkupPercent;
  late String _selectedPaymentAccountId;
  late bool _savePaymentAccount;
  DateTime? _estimatedDeliveryDate;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _baseLogisticsCtrl = TextEditingController(
      text: widget.request.charges.baseLogisticsFeeCents > 0
          ? formatNgnInputFromKobo(widget.request.charges.baseLogisticsFeeCents)
          : "",
    );
    final invoicePaymentAccount = widget.request.invoice.paymentAccount;
    _bankNameCtrl = TextEditingController(text: invoicePaymentAccount.bankName);
    _accountNameCtrl = TextEditingController(
      text: invoicePaymentAccount.accountName,
    );
    _accountNumberCtrl = TextEditingController(
      text: invoicePaymentAccount.accountNumber,
    );
    _transferInstructionCtrl = TextEditingController(
      text: invoicePaymentAccount.transferInstruction.isNotEmpty
          ? invoicePaymentAccount.transferInstruction
          : widget.request.invoice.paymentInstructions,
    );
    _noteCtrl = TextEditingController(text: widget.request.invoice.note);
    _sellerMarkupPercent = _normalizeMarkup(
      widget.request.charges.sellerMarkupPercent,
    );
    _estimatedDeliveryDate = widget.request.invoice.estimatedDeliveryDate;
    _selectedPaymentAccountId =
        invoicePaymentAccount.id.isNotEmpty &&
            widget.request.availablePaymentAccounts.any(
              (entry) => entry.id == invoicePaymentAccount.id,
            )
        ? invoicePaymentAccount.id
        : _newBusinessAccountOption;
    _savePaymentAccount =
        invoicePaymentAccount.id.isNotEmpty ||
        widget.request.availablePaymentAccounts.isEmpty;

    _baseLogisticsCtrl.addListener(_clearError);
    _bankNameCtrl.addListener(_clearError);
    _accountNameCtrl.addListener(_clearError);
    _accountNumberCtrl.addListener(_clearError);
    _transferInstructionCtrl.addListener(_clearError);
    _noteCtrl.addListener(_clearError);
  }

  @override
  void dispose() {
    _baseLogisticsCtrl.dispose();
    _bankNameCtrl.dispose();
    _accountNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _transferInstructionCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorText != null && mounted) {
      setState(() => _errorText = null);
    }
  }

  double _normalizeMarkup(double value) {
    for (final option in _sellerMarkupOptions) {
      if ((option - value).abs() < 0.001) {
        return option;
      }
    }
    return 0;
  }

  int _parseCurrencyInput(String value) {
    final parsed = parseNgnToKobo(value);
    if (parsed == null) {
      return 0;
    }
    if (parsed < 0) {
      throw const FormatException("Enter a valid amount");
    }
    return parsed;
  }

  int get _baseLogisticsFeeCents {
    try {
      return _parseCurrencyInput(_baseLogisticsCtrl.text);
    } catch (_) {
      return 0;
    }
  }

  int get _sellerMarkupAmountCents =>
      (widget.request.subtotalAmountCents * (_sellerMarkupPercent / 100))
          .round();

  int get _customerVisibleLogisticsCents =>
      _baseLogisticsFeeCents + _sellerMarkupAmountCents;

  int get _serviceChargeCents =>
      (widget.request.subtotalAmountCents * 0.05).round();

  int get _totalDueCents =>
      widget.request.subtotalAmountCents +
      _customerVisibleLogisticsCents +
      _serviceChargeCents;

  Future<void> _pickEstimatedDeliveryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _estimatedDeliveryDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(kDatePickerLastYear),
    );
    if (picked != null && mounted) {
      setState(() {
        _estimatedDeliveryDate = picked;
        _errorText = null;
      });
    }
  }

  Future<void> _refreshRequestState() async {
    ref.invalidate(chatConversationDetailProvider(widget.conversationId));
    ref.invalidate(chatThreadProvider(widget.conversationId));
    ref.invalidate(chatInboxProvider);
    ref.invalidate(myOrdersProvider);
    ref.invalidate(businessOrdersProvider);
  }

  void _applySavedPaymentAccount(PurchaseRequestPaymentAccount? account) {
    if (account == null) {
      _bankNameCtrl.clear();
      _accountNameCtrl.clear();
      _accountNumberCtrl.clear();
      _transferInstructionCtrl.clear();
      return;
    }
    _bankNameCtrl.text = account.bankName;
    _accountNameCtrl.text = account.accountName;
    _accountNumberCtrl.text = account.accountNumber;
    _transferInstructionCtrl.text = account.transferInstruction;
  }

  Map<String, dynamic> _buildPaymentAccountPayload() {
    PurchaseRequestPaymentAccount? selectedSavedAccount;
    for (final entry in widget.request.availablePaymentAccounts) {
      if (entry.id == _selectedPaymentAccountId) {
        selectedSavedAccount = entry;
        break;
      }
    }
    final accountNumber = _accountNumberCtrl.text.replaceAll(
      RegExp(r"\D+"),
      "",
    );
    if (_bankNameCtrl.text.trim().isEmpty) {
      throw const FormatException("Bank name is required");
    }
    if (_accountNameCtrl.text.trim().isEmpty) {
      throw const FormatException("Account name is required");
    }
    if (accountNumber.length != _accountNumberLength) {
      throw const FormatException("Account number must be 10 digits");
    }
    if (_transferInstructionCtrl.text.trim().isEmpty) {
      throw const FormatException("Transfer instruction is required");
    }
    return {
      if (selectedSavedAccount != null) "accountId": selectedSavedAccount.id,
      "bankName": _bankNameCtrl.text.trim(),
      "accountName": _accountNameCtrl.text.trim(),
      "accountNumber": accountNumber,
      "transferInstruction": _transferInstructionCtrl.text.trim(),
    };
  }

  Future<void> _submit() async {
    final session = ref.read(authSessionProvider);
    if (session == null || !session.isTokenValid || _isSubmitting) {
      return;
    }

    try {
      final baseLogisticsFeeCents = _parseCurrencyInput(
        _baseLogisticsCtrl.text,
      );
      if (_estimatedDeliveryDate == null) {
        throw const FormatException("Estimated delivery date is required");
      }
      final paymentAccount = _buildPaymentAccountPayload();

      setState(() {
        _isSubmitting = true;
        _errorText = null;
      });

      final api = ref.read(purchaseRequestApiProvider);
      await api.sendInvoice(
        token: session.token,
        requestId: widget.request.id,
        baseLogisticsFeeCents: baseLogisticsFeeCents,
        sellerMarkupPercent: _sellerMarkupPercent,
        estimatedDeliveryDate: _estimatedDeliveryDate!,
        paymentAccount: paymentAccount,
        savePaymentAccount: _savePaymentAccount,
        note: _noteCtrl.text.trim(),
      );

      await _refreshRequestState();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FormatException catch (error) {
      setState(() => _errorText = error.message);
    } catch (error) {
      AppDebug.log(
        "QUOTE_SCREEN",
        "submit_failed",
        extra: {"error": error.toString()},
      );
      setState(() => _errorText = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditingExisting = widget.request.invoice.isSent;
    final scheme = Theme.of(context).colorScheme;
    final requestId = widget.request.id.length > 6
        ? widget.request.id
              .substring(widget.request.id.length - 6)
              .toUpperCase()
        : widget.request.id;

    return Theme(
      data: AppTheme.business(),
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        appBar: AppBar(
          title: Text(
            isEditingExisting ? "Edit quotation" : "Create quotation",
          ),
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surfaceContainerLowest,
                scheme.surfaceContainerLow,
                scheme.surfaceContainerLowest,
              ],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                Text(
                  "Purchase request #$requestId",
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  "Build the customer quotation here. The request tracker in chat remains unchanged and will move to Quoted after you save.",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                _QuoteProgressCard(request: widget.request),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;
                    final form = _QuoteFormCard(
                      availablePaymentAccounts:
                          widget.request.availablePaymentAccounts,
                      baseLogisticsCtrl: _baseLogisticsCtrl,
                      bankNameCtrl: _bankNameCtrl,
                      accountNameCtrl: _accountNameCtrl,
                      accountNumberCtrl: _accountNumberCtrl,
                      transferInstructionCtrl: _transferInstructionCtrl,
                      noteCtrl: _noteCtrl,
                      sellerMarkupPercent: _sellerMarkupPercent,
                      selectedPaymentAccountId: _selectedPaymentAccountId,
                      savePaymentAccount: _savePaymentAccount,
                      estimatedDeliveryDate: _estimatedDeliveryDate,
                      errorText: _errorText,
                      isSubmitting: _isSubmitting,
                      onSelectedPaymentAccountChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedPaymentAccountId = value;
                          _errorText = null;
                          if (value == _newBusinessAccountOption) {
                            _savePaymentAccount = true;
                            _applySavedPaymentAccount(null);
                            return;
                          }
                          final matched = widget
                              .request
                              .availablePaymentAccounts
                              .where((entry) => entry.id == value)
                              .toList();
                          _savePaymentAccount = true;
                          _applySavedPaymentAccount(
                            matched.isEmpty ? null : matched.first,
                          );
                        });
                      },
                      onSavePaymentAccountChanged: (value) {
                        setState(() {
                          _savePaymentAccount = value;
                          _errorText = null;
                        });
                      },
                      onMarkupChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _sellerMarkupPercent = value;
                          _errorText = null;
                        });
                      },
                      onPickEstimatedDeliveryDate: _pickEstimatedDeliveryDate,
                      onSubmit: _submit,
                      submitLabel: isEditingExisting
                          ? "Save quotation"
                          : "Create quotation",
                    );

                    final preview = _QuotePreviewCard(
                      request: widget.request,
                      sellerMarkupPercent: _sellerMarkupPercent,
                      baseLogisticsFeeCents: _baseLogisticsFeeCents,
                      sellerMarkupAmountCents: _sellerMarkupAmountCents,
                      customerVisibleLogisticsCents:
                          _customerVisibleLogisticsCents,
                      serviceChargeCents: _serviceChargeCents,
                      totalDueCents: _totalDueCents,
                      estimatedDeliveryDate: _estimatedDeliveryDate,
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: form),
                          const SizedBox(width: 18),
                          Expanded(flex: 5, child: preview),
                        ],
                      );
                    }

                    return Column(
                      children: [form, const SizedBox(height: 18), preview],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuoteProgressCard extends StatelessWidget {
  final PurchaseRequest request;

  const _QuoteProgressCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = <String>[
      "Accepted",
      "Quoted",
      "Proof",
      "Approved",
      "Shipped",
      "Delivered",
    ];
    final currentIndex = switch (request.progressStage) {
      "quoted" => 1,
      "proof_submitted" => 2,
      "approved" => 3,
      "shipped" => 4,
      "delivered" => 5,
      _ => 0,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.businessAccent.withValues(alpha: 0.28),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(labels.length, (index) {
            final isCurrent = index == currentIndex;
            final isComplete = index < currentIndex;
            final accent = isCurrent || isComplete
                ? AppColors.businessAccent
                : scheme.outlineVariant.withValues(alpha: 0.72);

            return Row(
              children: [
                if (index > 0)
                  Container(
                    width: 54,
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: index <= currentIndex
                          ? AppColors.businessAccent.withValues(alpha: 0.42)
                          : scheme.outlineVariant.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isComplete
                            ? AppColors.businessAccent
                            : isCurrent
                            ? AppColors.businessAccent.withValues(alpha: 0.16)
                            : scheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 1.6),
                      ),
                      child: Center(
                        child: isComplete
                            ? Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: scheme.surface,
                              )
                            : Text(
                                "${index + 1}",
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: isCurrent
                                          ? AppColors.businessAccent
                                          : scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 74,
                      child: Text(
                        labels[index],
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isCurrent || isComplete
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                          fontWeight: isCurrent
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _QuoteFormCard extends StatelessWidget {
  final List<PurchaseRequestPaymentAccount> availablePaymentAccounts;
  final TextEditingController baseLogisticsCtrl;
  final TextEditingController bankNameCtrl;
  final TextEditingController accountNameCtrl;
  final TextEditingController accountNumberCtrl;
  final TextEditingController transferInstructionCtrl;
  final TextEditingController noteCtrl;
  final double sellerMarkupPercent;
  final String selectedPaymentAccountId;
  final bool savePaymentAccount;
  final DateTime? estimatedDeliveryDate;
  final String? errorText;
  final bool isSubmitting;
  final ValueChanged<String?> onSelectedPaymentAccountChanged;
  final ValueChanged<bool> onSavePaymentAccountChanged;
  final ValueChanged<double?> onMarkupChanged;
  final VoidCallback onPickEstimatedDeliveryDate;
  final VoidCallback onSubmit;
  final String submitLabel;

  const _QuoteFormCard({
    required this.availablePaymentAccounts,
    required this.baseLogisticsCtrl,
    required this.bankNameCtrl,
    required this.accountNameCtrl,
    required this.accountNumberCtrl,
    required this.transferInstructionCtrl,
    required this.noteCtrl,
    required this.sellerMarkupPercent,
    required this.selectedPaymentAccountId,
    required this.savePaymentAccount,
    required this.estimatedDeliveryDate,
    required this.errorText,
    required this.isSubmitting,
    required this.onSelectedPaymentAccountChanged,
    required this.onSavePaymentAccountChanged,
    required this.onMarkupChanged,
    required this.onPickEstimatedDeliveryDate,
    required this.onSubmit,
    required this.submitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Quotation form",
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            "Choose the seller service percentage, format logistics properly, and use a saved business account or enter a new one.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: baseLogisticsCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              LengthLimitingTextInputFormatter(_baseLogisticsMaxLength),
              NgnInputFormatter(),
            ],
            decoration: const InputDecoration(
              labelText: "Base logistics amount (NGN)",
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<double>(
            initialValue: _sellerMarkupOptions.contains(sellerMarkupPercent)
                ? sellerMarkupPercent
                : _sellerMarkupOptions.first,
            items: _sellerMarkupOptions
                .map(
                  (value) => DropdownMenuItem<double>(
                    value: value,
                    child: Text(
                      value == 0 ? "0% service" : "${value.toInt()}% service",
                    ),
                  ),
                )
                .toList(),
            onChanged: isSubmitting ? null : onMarkupChanged,
            decoration: const InputDecoration(
              labelText: "Seller service percentage",
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: selectedPaymentAccountId,
            items: [
              const DropdownMenuItem<String>(
                value: _newBusinessAccountOption,
                child: Text("Add new business account"),
              ),
              ...availablePaymentAccounts.map(
                (account) => DropdownMenuItem<String>(
                  value: account.id,
                  child: Text(account.maskedAccountLabel),
                ),
              ),
            ],
            onChanged: isSubmitting ? null : onSelectedPaymentAccountChanged,
            decoration: const InputDecoration(
              labelText: "Saved business account",
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: isSubmitting ? null : onPickEstimatedDeliveryDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: "Estimated delivery date",
              ),
              child: Text(
                formatDateLabel(
                  estimatedDeliveryDate,
                  fallback: "Select a delivery date",
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: bankNameCtrl,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_bankNameMaxLength),
            ],
            decoration: const InputDecoration(labelText: "Bank name"),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: accountNameCtrl,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_accountNameMaxLength),
            ],
            decoration: const InputDecoration(labelText: "Account name"),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: accountNumberCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(_accountNumberLength),
            ],
            decoration: const InputDecoration(
              labelText: "Account number",
              hintText: "10-digit bank account number",
              counterText: "",
            ),
            maxLength: _accountNumberLength,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: transferInstructionCtrl,
            maxLines: 3,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_transferInstructionMaxLength),
            ],
            decoration: const InputDecoration(
              labelText: "Transfer instruction",
              hintText:
                  "Add the transfer note or extra instruction the customer should follow.",
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: savePaymentAccount,
            onChanged: isSubmitting ? null : onSavePaymentAccountChanged,
            title: const Text("Save this business account"),
            subtitle: const Text(
              "Reuse it next time when another quotation needs payment details.",
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: "Seller note"),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 14),
            Text(
              errorText!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isSubmitting ? null : onSubmit,
              icon: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.receipt_long_rounded),
              label: Text(submitLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotePreviewCard extends StatelessWidget {
  final PurchaseRequest request;
  final double sellerMarkupPercent;
  final int baseLogisticsFeeCents;
  final int sellerMarkupAmountCents;
  final int customerVisibleLogisticsCents;
  final int serviceChargeCents;
  final int totalDueCents;
  final DateTime? estimatedDeliveryDate;

  const _QuotePreviewCard({
    required this.request,
    required this.sellerMarkupPercent,
    required this.baseLogisticsFeeCents,
    required this.sellerMarkupAmountCents,
    required this.customerVisibleLogisticsCents,
    required this.serviceChargeCents,
    required this.totalDueCents,
    required this.estimatedDeliveryDate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.businessAccent.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Customer quotation preview",
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _QuoteLine(
                label: "Item cost",
                value: formatNgnFromCents(request.subtotalAmountCents),
              ),
              _QuoteLine(
                label: "Logistics cost",
                value: formatNgnFromCents(customerVisibleLogisticsCents),
              ),
              _QuoteLine(
                label: "Estimated delivery",
                value: formatDateLabel(
                  estimatedDeliveryDate,
                  fallback: "Pending",
                ),
              ),
              _QuoteLine(
                label: "In-app service charge",
                value: formatNgnFromCents(serviceChargeCents),
              ),
              const Divider(height: 22),
              _QuoteLine(
                label: "Total due",
                value: formatNgnFromCents(totalDueCents),
                emphasize: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Internal seller breakdown",
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _QuoteLine(
                label: "Base logistics",
                value: formatNgnFromCents(baseLogisticsFeeCents),
              ),
              _QuoteLine(
                label: "Service percentage",
                value: sellerMarkupPercent == 0
                    ? "0%"
                    : "${sellerMarkupPercent.toInt()}%",
              ),
              _QuoteLine(
                label: "Markup amount",
                value: formatNgnFromCents(sellerMarkupAmountCents),
              ),
              _QuoteLine(
                label: "Customer-visible logistics",
                value: formatNgnFromCents(customerVisibleLogisticsCents),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuoteLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _QuoteLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style:
                (emphasize
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(
                      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
                    ),
          ),
        ],
      ),
    );
  }
}
