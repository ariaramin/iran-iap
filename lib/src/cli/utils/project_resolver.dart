import 'dart:io';

/// Resolves the Flutter project directory based on the given path or defaults.
Directory? resolveProjectDirectory({
  required String? explicitPath,
  required bool allowExplicitTarget,
  required List<String> flutterArgs,
}) {
  if (explicitPath != null && explicitPath != '.') {
    final explicitDirectory = Directory(explicitPath).absolute;
    if (isFlutterApplication(
      explicitDirectory,
      allowExplicitTarget: allowExplicitTarget,
      flutterArgs: flutterArgs,
    )) {
      return explicitDirectory;
    }
    stderr.writeln(
      'The --project-dir path is not a usable Flutter Android application: '
      '${explicitDirectory.path}',
    );
    return null;
  }

  final current = Directory.current.absolute;
  if (isFlutterApplication(
    current,
    allowExplicitTarget: allowExplicitTarget,
    flutterArgs: flutterArgs,
  )) {
    return current;
  }

  final example = Directory('${current.path}${Platform.pathSeparator}example');
  if (isFlutterApplication(
    example,
    allowExplicitTarget: allowExplicitTarget,
    flutterArgs: flutterArgs,
  )) {
    return example.absolute;
  }

  return null;
}

/// Checks if the given directory contains a Flutter Android application.
bool isFlutterApplication(
  Directory directory, {
  required bool allowExplicitTarget,
  required List<String> flutterArgs,
}) {
  if (!directory.existsSync()) {
    return false;
  }

  final pubspec = File(
    '${directory.path}${Platform.pathSeparator}pubspec.yaml',
  );
  final androidDirectory = Directory(
    '${directory.path}${Platform.pathSeparator}android',
  );
  final androidAppDirectory = Directory(
    '${androidDirectory.path}${Platform.pathSeparator}app',
  );
  if (!pubspec.existsSync() || !androidAppDirectory.existsSync()) {
    return false;
  }

  if (allowExplicitTarget) {
    final hasExplicitTarget = flutterArgs.any(
      (arg) =>
          arg == '-t' ||
          arg == '--target' ||
          arg.startsWith('--target=') ||
          arg.startsWith('-t='),
    );
    if (hasExplicitTarget) {
      return true;
    }
  }

  return File(
    '${directory.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}main.dart',
  ).existsSync();
}
