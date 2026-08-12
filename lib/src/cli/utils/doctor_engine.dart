import 'dart:convert';
import 'dart:io';

/// Runs host diagnostic checks for the selected store.
int doctor(
  Directory projectDirectory,
  String store, {
  bool quietSuccess = false,
  bool isJson = false,
}) {
  final problems = <String>[];
  final warnings = <String>[];
  final androidDirectory = Directory(
    '${projectDirectory.path}${Platform.pathSeparator}android',
  );

  final gradleTexts = readGradleFiles(androidDirectory);
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

  if (isJson) {
    final out = {
      'store': store,
      'project': projectDirectory.path,
      'problems': problems,
      'warnings': warnings,
      'status': problems.isEmpty ? 'pass' : 'fail',
    };
    stdout.writeln(jsonEncode(out));
    return problems.isEmpty ? 0 : 1;
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

/// Reads all relevant Gradle files in the given Android directory.
List<String> readGradleFiles(Directory androidDirectory) {
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

/// Returns the basename of the given path.
String _basename(String path) => path.split(Platform.pathSeparator).last;
