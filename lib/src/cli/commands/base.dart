import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:iran_iap/src/cli/utils/doctor_engine.dart';
import 'package:iran_iap/src/cli/utils/project_resolver.dart';
import 'package:meta/meta.dart';

/// Supported store IDs.
const stores = {'bazaar', 'myket'};

/// Base class for all `iran_iap` commands.
abstract class IranIapCommand extends Command<int> {
  /// The store ID provided via the `--store` option.
  String? get store => globalResults?.option('store');

  /// The project directory provided via the `--project-dir` option.
  String? get projectDir => globalResults?.option('project-dir');

  /// Resolves the Flutter project directory based on CLI arguments.
  Directory? resolveProject({bool allowExplicitTarget = true}) {
    final dir = resolveProjectDirectory(
      explicitPath: projectDir,
      allowExplicitTarget: allowExplicitTarget,
      flutterArgs: argResults?.rest ?? [],
    );

    if (dir == null) {
      stderr
        ..writeln(
          'Error: Could not find a Flutter Android application from '
          '${Directory.current.absolute.path}',
        )
        ..writeln(
          '\nFix:\n'
          '  - Run this command from the root of a Flutter project\n'
          '  - Or pass the path explicitly: --project-dir <path>\n',
        );
      return null;
    }
    return dir;
  }

  /// Returns the validated `--store` option.
  String requireStore() {
    final value = store;
    if (value == null || !stores.contains(value)) {
      usageException('Missing or invalid --store. Expected: bazaar | myket');
    }
    return value;
  }

  /// Executes a `flutter` command with store isolation.
  @protected
  Future<int> executeFlutter(
    Directory projectDirectory,
    String store,
    List<String> flutterArgs,
  ) async {
    final define = '--dart-define=IRAN_IAP_STORE=$store';
    final storeDefines = flutterArgs.where(
      (arg) => arg.startsWith('--dart-define=IRAN_IAP_STORE='),
    );
    if (storeDefines.any((arg) => arg != define)) {
      usageException(
        'Conflicting IRAN_IAP_STORE define. --store $store requires $define.',
      );
    }
    if (storeDefines.isEmpty) {
      flutterArgs.add(define);
    }

    final environment = Map<String, String>.from(Platform.environment)
      ..['ORG_GRADLE_PROJECT_iranIapStore'] = store;

    stdout
      ..writeln('iran_iap: store   = $store')
      ..writeln('iran_iap: project = ${projectDirectory.path}');

    final doctorCode = doctor(projectDirectory, store, quietSuccess: true);
    if (doctorCode != 0) {
      stderr.writeln(
        'iran_iap: host setup has problems. Run '
        '`dart run iran_iap doctor --store $store` for details',
      );
    }

    final process = await Process.start(
      'flutter',
      flutterArgs,
      mode: ProcessStartMode.inheritStdio,
      environment: environment,
      workingDirectory: projectDirectory.path,
    );
    return process.exitCode;
  }
}
