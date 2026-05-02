library;

import 'package:flutter/material.dart';

const String _reportEmailDialogTitle = "Email progress report";
const String _reportEmailDialogHint = "name@example.com";
const String _reportEmailDialogHelper =
    "Send the current progress report as a styled HTML email.";
const String _reportEmailDialogCancel = "Cancel";
const String _reportEmailDialogSubmit = "Send";
const String _reportLinkDialogTitle = "Copy view link";
const String _reportLinkDialogHelper =
    "Enter the email that should be prefilled on sign-in, then generate and copy the view link.";
const String _reportLinkDialogSubmit = "Generate link";
const String _reportEmailValidationMessage = "Enter a valid email address.";
final RegExp _reportEmailPattern = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");

Future<String?> showProductionProgressReportEmailDialog(
  BuildContext context, {
  String initialEmail = "",
}) async {
  return _showProductionProgressRecipientDialog(
    context,
    initialEmail: initialEmail,
    title: _reportEmailDialogTitle,
    helper: _reportEmailDialogHelper,
    submitLabel: _reportEmailDialogSubmit,
  );
}

Future<String?> showProductionProgressReportLinkDialog(
  BuildContext context, {
  String initialEmail = "",
}) async {
  return _showProductionProgressRecipientDialog(
    context,
    initialEmail: initialEmail,
    title: _reportLinkDialogTitle,
    helper: _reportLinkDialogHelper,
    submitLabel: _reportLinkDialogSubmit,
  );
}

Future<String?> _showProductionProgressRecipientDialog(
  BuildContext context, {
  required String initialEmail,
  required String title,
  required String helper,
  required String submitLabel,
}) async {
  final controller = TextEditingController(text: initialEmail.trim());
  String? validationMessage;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final value = controller.text.trim();
            if (!_reportEmailPattern.hasMatch(value)) {
              setDialogState(() {
                validationMessage = _reportEmailValidationMessage;
              });
              return;
            }
            Navigator.of(dialogContext).pop(value);
          }

          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(helper),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: _reportEmailDialogHint,
                    errorText: validationMessage,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(_reportEmailDialogCancel),
              ),
              FilledButton(onPressed: submit, child: Text(submitLabel)),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}
