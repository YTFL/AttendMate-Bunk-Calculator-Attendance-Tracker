import 'package:flutter/material.dart';

extension SnackbarUtils on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  showReplacingSnackBar(SnackBar snackBar) {
    removeCurrentSnackBar(reason: SnackBarClosedReason.remove);
    clearSnackBars();
    return showSnackBar(snackBar);
  }

  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  static void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }
}