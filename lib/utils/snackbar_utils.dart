import 'package:flutter/material.dart';

extension SnackbarUtils on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  showReplacingSnackBar(SnackBar snackBar) {
    removeCurrentSnackBar(reason: SnackBarClosedReason.remove);
    clearSnackBars();
    return showSnackBar(snackBar);
  }
}