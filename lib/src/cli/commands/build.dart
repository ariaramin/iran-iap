import 'dart:io';

import 'package:iran_iap/src/cli/commands/base.dart';

/// Command to build the Flutter app with the selected store.
class BuildCommand extends IranIapCommand {
  @override
  String get name => 'build';
  @override
  String get description => 'Build the Flutter app with the selected store';

  @override
  Future<void> run() async {
    validateStore();
    final rest = argResults!.rest;
    if (rest.isEmpty || (rest.first != 'apk' && rest.first != 'appbundle')) {
      usageException('Build target required: apk | appbundle');
    }

    final project = resolveProject();
    if (project == null) {
      exitCode = 66;
      return;
    }

    final flutterArgs = ['build', ...rest];
    exitCode = await executeFlutter(project, store!, flutterArgs);
  }
}
