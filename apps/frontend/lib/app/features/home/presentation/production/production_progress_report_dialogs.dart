library;

import 'package:flutter/material.dart';

const String _reportEmailDialogTitle = "Email progress report";
const String _reportEmailDialogHint = "name@example.com";
const String _reportEmailDialogHelper =
    "Send the current progress report as a styled HTML email.";
const String _reportEmailDialogCancel = "Cancel";
const String _reportEmailDialogSubmit = "Send";
const String _reportEmailValidationMessage = "Enter a valid email address.";
final RegExp _reportEmailPattern = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");

Future<String?> showProductionProgressReportEmailDialog(
  BuildContext context, {
  String initialEmail = "",
}) async {
  final controller = TextEditingController(text: initialEmail.trim());
  String? validationMessage;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
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
                  onSubmitted: (_) {
                    final value = controller.text.trim();
                    if (_reportEmailPattern.hasMatch(value)) {
                      Navigator.of(dialogContext).pop(value);
                      return;
                    }
                    setDialogState(() {
                      validationMessage = _reportEmailValidationMessage;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(_reportEmailDialogCancel),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (!_reportEmailPattern.hasMatch(value)) {
                    setDialogState(() {
                      validationMessage = _reportEmailValidationMessage;
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
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
