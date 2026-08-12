import 'dart:io';

import 'package:iran_iap/src/cli/commands/base.dart';
import 'package:iran_iap/src/cli/utils/doctor_engine.dart';

/// Command to check host Android configuration for the selected store.
class DoctorCommand extends IranIapCommand {
  /// Creates a [DoctorCommand].
  DoctorCommand() {
    argParser.addFlag(
      'json',
      help: 'Output results in JSON format.',
      negatable: false,
    );
  }

  @override
  String get name => 'doctor';
  @override
  String get description =>
      'Check host Android configuration for the selected store';

  @override
  Future<void> run() async {
    validateStore();
    final project = resolveProject(allowExplicitTarget: false);
    if (project == null) {
      exitCode = 66;
      return;
    }

    exitCode = doctor(project, store!, isJson: argResults!.flag('json'));
  }
}
