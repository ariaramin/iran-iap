import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:iran_iap/src/cli/commands/base.dart';
import 'package:iran_iap/src/cli/commands/build.dart';
import 'package:iran_iap/src/cli/commands/doctor.dart';
import 'package:iran_iap/src/cli/commands/run.dart';
import 'package:iran_iap/src/cli/commands/verify.dart';

/// Creates the `iran_iap` command runner.
CommandRunner<int> createRunner() {
  return CommandRunner<int>(
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
    ..argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show stack traces for unexpected failures.',
      negatable: false,
    )
    ..addCommand(DoctorCommand())
    ..addCommand(RunCommand())
    ..addCommand(BuildCommand())
    ..addCommand(VerifyCommand());
}

Future<void> main(List<String> args) async {
  final runner = createRunner();
  var verbose = false;
  try {
    final results = runner.parse(args);
    verbose = results.flag('verbose');
    exitCode = await runner.runCommand(results) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on Object catch (e, st) {
    stderr.writeln('Error: $e');
    if (verbose) {
      stderr.writeln(st);
    }
    exitCode = 1;
  }
}
