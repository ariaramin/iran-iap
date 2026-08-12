import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:iran_iap/src/cli/commands/base.dart';
import 'package:iran_iap/src/cli/commands/build.dart';
import 'package:iran_iap/src/cli/commands/doctor.dart';
import 'package:iran_iap/src/cli/commands/run.dart';
import 'package:iran_iap/src/cli/commands/verify.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<void>(
          'iran_iap',
          'Store-aware Flutter build tools for Cafe Bazaar and Myket',
        )
        ..argParser.addOption(
          'store',
          abbr: 's',
          help: 'The target app store',
          allowed: stores.toList(),
          valueHelp: 'store',
        )
        ..argParser.addOption(
          'project-dir',
          help: 'Path to the Flutter project',
          valueHelp: 'path',
          defaultsTo: '.',
        )
        ..addCommand(DoctorCommand())
        ..addCommand(RunCommand())
        ..addCommand(BuildCommand())
        ..addCommand(VerifyCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on Object catch (e, st) {
    stderr.writeln('Error: $e');
    if (args.contains('--verbose')) {
      stderr.writeln(st);
    }
    exitCode = 1;
  }
}
