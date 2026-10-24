/// Runs a breathing change and says so when it fails.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/logging.dart';

/// Awaits [action]. A failure is logged with [what] and shown in a snack bar;
/// it is never swallowed. Returns whether it worked.
Future<bool> runBreathingAction(
  BuildContext context,
  String what,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    return true;
  } on Exception catch (error, stack) {
    AppLog.failure('breathing', what, error, stack);
    messenger?.showSnackBar(
      SnackBar(content: Text("Couldn't $what. Try again.")),
    );
    return false;
  }
}
