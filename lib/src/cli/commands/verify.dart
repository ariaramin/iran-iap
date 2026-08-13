import 'dart:convert';
import 'dart:io';

import 'package:iran_iap/src/cli/commands/base.dart';
import 'package:meta/meta.dart';

/// Command to verify that a built APK/AAB does not contain forbidden traces.
class VerifyCommand extends IranIapCommand {
  @override
  String get name => 'verify';
  @override
  String get description =>
      'Verify that a built APK/AAB does not contain forbidden traces';

  @override
  Future<int> run() async {
    final store = requireStore();
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Exactly one artifact path (APK/AAB) is required');
    }

    return _verify(rest.single, store);
  }

  Future<int> _verify(String artifactPath, String store) async {
    final artifact = File(artifactPath);
    if (!artifact.existsSync()) {
      stderr.writeln('Error: artifact file not found: $artifactPath');
      return 66;
    }

    final packageDirectory = await resolveIranIapPackageDirectory();
    final pythonTool = packageDirectory == null
        ? null
        : File(
            '${packageDirectory.path}${Platform.pathSeparator}tool'
            '${Platform.pathSeparator}verify_android_artifact.py',
          );
    if (pythonTool == null || !pythonTool.existsSync()) {
      stderr.writeln(
        'Error: installed artifact verifier could not be located. '
        'Reinstall iran_iap.',
      );
      return 70;
    }

    final process = await Process.start('python3', [
      pythonTool.path,
      '--store',
      store,
      artifactPath,
    ], mode: ProcessStartMode.inheritStdio);
    return process.exitCode;
  }
}

/// Resolves the installed package directory that contains CLI runtime assets.
@visibleForTesting
Future<Directory?> resolveIranIapPackageDirectory({
  String? packageConfigLocation,
  Uri? scriptUri,
}) async {
  final location = packageConfigLocation ?? Platform.packageConfig;
  if (location != null) {
    try {
      final packageConfigUri = Uri.parse(location);
      final decoded = jsonDecode(
        await File.fromUri(packageConfigUri).readAsString(),
      );
      if (decoded case {'packages': final List<Object?> packages}) {
        for (final package in packages) {
          if (package case {
            'name': 'iran_iap',
            'rootUri': final String rootUri,
          }) {
            return Directory.fromUri(packageConfigUri.resolve(rootUri));
          }
        }
      }
    } on FileSystemException {
      // Fall through to direct script resolution.
    } on FormatException {
      // Fall through to direct script resolution.
    }
  }

  final activeScriptUri = scriptUri ?? Platform.script;
  if (activeScriptUri.scheme == 'file' &&
      activeScriptUri.path.endsWith('.dart')) {
    return File.fromUri(activeScriptUri).parent.parent;
  }
  return null;
}
