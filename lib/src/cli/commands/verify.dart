import 'dart:io';

import 'package:iran_iap/src/cli/commands/base.dart';

/// Command to verify that a built APK/AAB does not contain forbidden traces.
class VerifyCommand extends IranIapCommand {
  @override
  String get name => 'verify';
  @override
  String get description =>
      'Verify that a built APK/AAB does not contain forbidden traces';

  @override
  Future<void> run() async {
    validateStore();
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('Artifact path (APK/AAB) required for verify');
    }

    exitCode = await _verify(rest, store);
  }

  Future<int> _verify(List<String> args, String? store) async {
    final artifactPath = args.first;
    final artifact = File(artifactPath);
    if (!artifact.existsSync()) {
      stderr.writeln('Error: artifact file not found: $artifactPath');
      return 66;
    }

    final packageDir = _resolvePackageDir();
    final pythonTool = '$packageDir/tool/verify_android_artifact.py';

    final process = await Process.start('python3', [
      pythonTool,
      '--store',
      store!,
      artifactPath,
    ], mode: ProcessStartMode.inheritStdio);
    return process.exitCode;
  }

  String _resolvePackageDir() {
    final script = Platform.script.toFilePath();
    if (script.endsWith('.dart')) {
      return Directory(script).parent.parent.path;
    }
    return Directory.current.path;
  }
}
