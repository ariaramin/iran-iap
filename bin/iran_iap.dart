import 'dart:io';

const _stores = {'bazaar', 'myket'};

/// Command-line entry point for store-aware Flutter run/build checks.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _usage();
    return;
  }

  final parsed = _parseArgs(args);
  final store = parsed.store;
  final remaining = parsed.remaining;

  if (store == null || !_stores.contains(store)) {
    stderr.writeln('Missing or invalid --store. Expected: bazaar | myket');
    _usage();
    exitCode = 64;
    return;
  }
  if (remaining.isEmpty) {
    stderr.writeln('Missing command.');
    _usage();
    exitCode = 64;
    return;
  }

  final command = remaining.first;
  final commandArgs = remaining.sublist(1);
  final projectDirectory = _resolveProjectDirectory(
    explicitPath: parsed.projectDirectory,
    allowExplicitTarget: command != 'doctor',
    flutterArgs: commandArgs,
  );

  if (projectDirectory == null) {
    stderr
      ..writeln(
        'Error: Could not find a Flutter Android application from '
        '${Directory.current.absolute.path}.',
      )
      ..writeln(
        '\nFix:\n'
        '  - Run this command from the root of a Flutter project.\n'
        '  - Or pass the path explicitly: --project-dir <path>\n',
      );
    exitCode = 66;
    return;
  }

  if (command == 'doctor') {
    exitCode = _doctor(projectDirectory, store);
    return;
  }

  late final List<String> flutterArgs;
  switch (command) {
    case 'build':
      if (commandArgs.isEmpty ||
          (commandArgs.first != 'apk' && commandArgs.first != 'appbundle')) {
        stderr.writeln('Build target required: apk | appbundle');
        exitCode = 64;
        return;
      }
      flutterArgs = ['build', ...commandArgs];
    case 'run':
      flutterArgs = ['run', ...commandArgs];
    default:
      stderr.writeln('Unsupported command: $command');
      _usage();
      exitCode = 64;
      return;
  }

  final define = '--dart-define=IRAN_IAP_STORE=$store';
  final hasStoreDefine = flutterArgs.any(
    (arg) => arg.startsWith('--dart-define=IRAN_IAP_STORE='),
  );
  if (!hasStoreDefine) {
    flutterArgs.add(define);
  }

  final environment = Map<String, String>.from(Platform.environment)
    ..['ORG_GRADLE_PROJECT_iranIapStore'] = store;

  stdout
    ..writeln('iran_iap: store   = $store')
    ..writeln('iran_iap: project = ${projectDirectory.path}');

  final doctorCode = _doctor(projectDirectory, store, quietSuccess: true);
  if (doctorCode != 0) {
    stderr.writeln(
      'iran_iap: host setup has problems. Run '
      '`dart run iran_iap doctor --store $store` for details.',
    );
  }

  final process = await Process.start(
    'flutter',
    flutterArgs,
    mode: ProcessStartMode.inheritStdio,
    environment: environment,
    workingDirectory: projectDirectory.path,
  );
  exitCode = await process.exitCode;
}

({String? store, String? projectDirectory, List<String> remaining}) _parseArgs(
  List<String> args,
) {
  String? store;
  String? projectDirectory;
  final remaining = <String>[];

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];

    if (arg.startsWith('--store=')) {
      store = arg.substring('--store='.length).trim().toLowerCase();
      continue;
    }
    if (arg == '--store' && index + 1 < args.length) {
      store = args[++index].trim().toLowerCase();
      continue;
    }

    if (arg.startsWith('--project-dir=')) {
      projectDirectory = arg.substring('--project-dir='.length).trim();
      continue;
    }
    if (arg == '--project-dir' && index + 1 < args.length) {
      projectDirectory = args[++index].trim();
      continue;
    }

    remaining.add(arg);
  }

  return (
    store: store,
    projectDirectory: projectDirectory,
    remaining: remaining,
  );
}

Directory? _resolveProjectDirectory({
  required String? explicitPath,
  required bool allowExplicitTarget,
  required List<String> flutterArgs,
}) {
  if (explicitPath != null && explicitPath.isNotEmpty) {
    final explicitDirectory = Directory(explicitPath).absolute;
    if (_isFlutterApplication(
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
  if (_isFlutterApplication(
    current,
    allowExplicitTarget: allowExplicitTarget,
    flutterArgs: flutterArgs,
  )) {
    return current;
  }

  final example = Directory('${current.path}${Platform.pathSeparator}example');
  if (_isFlutterApplication(
    example,
    allowExplicitTarget: allowExplicitTarget,
    flutterArgs: flutterArgs,
  )) {
    return example.absolute;
  }

  return null;
}

bool _isFlutterApplication(
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

int _doctor(
  Directory projectDirectory,
  String store, {
  bool quietSuccess = false,
}) {
  final problems = <String>[];
  final warnings = <String>[];
  final androidDirectory = Directory(
    '${projectDirectory.path}${Platform.pathSeparator}android',
  );

  final gradleTexts = _readGradleFiles(androidDirectory);
  if (!gradleTexts.any((text) => text.contains('jitpack.io'))) {
    problems.add(
      'JitPack is not configured in the host Android repositories. '
      'Poolakey and Myket Billing Client are resolved from JitPack.',
    );
  }

  if (store == 'bazaar') {
    final activityFiles = androidDirectory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('MainActivity.kt') ||
              file.path.endsWith('MainActivity.java'),
        );
    final hasActivityResultHost = activityFiles.any((file) {
      final text = file.readAsStringSync();
      return text.contains('FlutterFragmentActivity') ||
          text.contains('ActivityResultRegistryOwner');
    });
    if (!hasActivityResultHost) {
      warnings.add(
        'Could not confirm an ActivityResultRegistry-compatible MainActivity. '
        'Bazaar purchases normally use FlutterFragmentActivity.',
      );
    }
  }

  if (store == 'myket') {
    const requiredPlaceholders = <String>[
      'marketApplicationId',
      'marketBindAddress',
      'marketPermission',
    ];
    for (final placeholder in requiredPlaceholders) {
      if (!gradleTexts.any((text) => text.contains(placeholder))) {
        problems.add(
          'Missing Myket manifest placeholder `$placeholder` in the host '
          'Android Gradle configuration.',
        );
      }
    }
  }

  if (!quietSuccess || problems.isNotEmpty || warnings.isNotEmpty) {
    stdout
      ..writeln('iran_iap doctor')
      ..writeln('  store:   $store')
      ..writeln('  project: ${projectDirectory.path}');
  }

  for (final warning in warnings) {
    stderr.writeln('WARNING: $warning');
  }
  for (final problem in problems) {
    stderr.writeln('ERROR: $problem');
  }

  if (problems.isEmpty && warnings.isEmpty && !quietSuccess) {
    stdout.writeln('OK: required host configuration was detected.');
  }

  return problems.isEmpty ? 0 : 1;
}

List<String> _readGradleFiles(Directory androidDirectory) {
  const names = <String>{
    'settings.gradle',
    'settings.gradle.kts',
    'build.gradle',
    'build.gradle.kts',
  };
  final texts = <String>[];
  if (!androidDirectory.existsSync()) {
    return texts;
  }

  for (final entity in androidDirectory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && names.contains(_basename(entity.path))) {
      texts.add(entity.readAsStringSync());
    }
  }
  return texts;
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

void _usage() {
  stdout.writeln('''
iran_iap CLI - Store-aware Flutter build tools

Usage:
  dart run iran_iap <command> [arguments]

Commands:
  doctor  Check host Android configuration for the selected store.
  run     Run the Flutter app with the selected store.
  build   Build the Flutter app (apk|appbundle) with the selected store.

Options:
  --store <bazaar|myket>    (Required) The target app store.
  --project-dir <path>      Path to the Flutter project (default: current directory).

Examples:
  dart run iran_iap doctor --store bazaar
  dart run iran_iap run --store bazaar --debug
  dart run iran_iap build apk --store myket --release

The CLI ensures that only the selected store's native SDK and logic are included
in the build. It never modifies your pubspec.yaml.
''');
}
