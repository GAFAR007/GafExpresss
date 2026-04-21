library;

import 'package:flutter/material.dart';

const String _reportEmailDialogTitle = "Email progress report";
const String _reportEmailDialogHint = "name@example.com";
const String _reportEmailDialogHelper =
    "Send the current progress report as a styled HTML email, or copy a view link with this email already filled at sign-in.";
const String _reportEmailDialogCancel = "Cancel";
const String _reportEmailDialogSubmit = "Send";
const String _reportEmailDialogCopy = "Copy view link";
const String _reportEmailValidationMessage = "Enter a valid email address.";
final RegExp _reportEmailPattern = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");

enum ProductionProgressReportDialogAction { send, copyViewLink }

class ProductionProgressReportDialogResult {
  final String email;
  final ProductionProgressReportDialogAction action;

  const ProductionProgressReportDialogResult({
    required this.email,
    required this.action,
  });
}

Future<ProductionProgressReportDialogResult?>
showProductionProgressReportEmailDialog(
  BuildContext context, {
  String initialEmail = "",
}) async {
  final controller = TextEditingController(text: initialEmail.trim());
  String? validationMessage;
  final result = await showDialog<ProductionProgressReportDialogResult>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          void submit(ProductionProgressReportDialogAction action) {
            final value = controller.text.trim();
            if (!_reportEmailPattern.hasMatch(value)) {
              setDialogState(() {
                validationMessage = _reportEmailValidationMessage;
              });
              return;
            }
            Navigator.of(dialogContext).pop(
              ProductionProgressReportDialogResult(
                email: value,
                action: action,
              ),
            );
          }

          return AlertDialog(
            title: const Text(_reportEmailDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(_reportEmailDialogHelper),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: _reportEmailDialogHint,
                    errorText: validationMessage,
                  ),
                  onSubmitted: (_) =>
                      submit(ProductionProgressReportDialogAction.send),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(_reportEmailDialogCancel),
              ),
              OutlinedButton(
                onPressed: () =>
                    submit(ProductionProgressReportDialogAction.copyViewLink),
                child: const Text(_reportEmailDialogCopy),
              ),
              FilledButton(
                onPressed: () =>
                    submit(ProductionProgressReportDialogAction.send),
                child: const Text(_reportEmailDialogSubmit),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}
