import 'dart:io';

import 'package:iran_iap/src/cli/commands/base.dart';

/// Command to run the Flutter app with the selected store.
class RunCommand extends IranIapCommand {
  @override
  String get name => 'run';
  @override
  String get description => 'Run the Flutter app with the selected store';

  @override
  Future<void> run() async {
    validateStore();
    final project = resolveProject();
    if (project == null) {
      exitCode = 66;
      return;
    }

    final flutterArgs = ['run', ...argResults!.rest];
    exitCode = await executeFlutter(project, store!, flutterArgs);
  }
}
